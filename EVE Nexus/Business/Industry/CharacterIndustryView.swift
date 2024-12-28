import SwiftUI

typealias IndustryJob = CharacterIndustryAPI.IndustryJob

@MainActor
class CharacterIndustryViewModel: ObservableObject {
    @Published var jobs: [IndustryJob] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var itemNames: [Int: String] = [:]
    @Published var locationInfoCache: [Int64: LocationInfoDetail] = [:]
    
    private let characterId: Int
    private let databaseManager: DatabaseManager
    
    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }
    
    func loadJobs(forceRefresh: Bool = false) async {
        isLoading = true
        
        do {
            jobs = try await CharacterIndustryAPI.shared.fetchIndustryJobs(
                characterId: characterId,
                forceRefresh: forceRefresh
            )
            
            // 加载物品名称
            await loadItemNames()
            // 加载地点名称
            await loadLocationNames()
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isLoading = false
    }
    
    private func loadItemNames() async {
        // 收集所有需要查询的type_id
        var typeIds = Set<Int>()
        for job in jobs {
            typeIds.insert(job.blueprint_type_id)
            if let productTypeId = job.product_type_id {
                typeIds.insert(productTypeId)
            }
        }
        
        // 查询数据库获取名称
        let query = """
            SELECT type_id, name
            FROM types
            WHERE type_id IN (\(typeIds.map { String($0) }.joined(separator: ",")))
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    itemNames[typeId] = name
                }
            }
        }
    }
    
    private func loadLocationNames() async {
        // 收集所有需要查询的location_id
        var locationIds = Set<Int64>()
        for job in jobs {
            locationIds.insert(job.station_id)
            locationIds.insert(job.facility_id)
        }
        
        // 使用LocationInfoLoader加载位置信息
        let locationLoader = LocationInfoLoader(databaseManager: databaseManager, characterId: Int64(characterId))
        locationInfoCache = await locationLoader.loadLocationInfo(locationIds: locationIds)
    }
}

struct CharacterIndustryView: View {
    let characterId: Int
    @StateObject private var viewModel: CharacterIndustryViewModel
    
    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: CharacterIndustryViewModel(
            characterId: characterId,
            databaseManager: databaseManager
        ))
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if viewModel.jobs.isEmpty {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("Industry_No_Jobs", comment: ""))
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else {
                ForEach(viewModel.jobs) { job in
                    IndustryJobRow(
                        job: job,
                        blueprintName: viewModel.itemNames[job.blueprint_type_id] ?? "Unknown",
                        productName: job.product_type_id.flatMap { viewModel.itemNames[$0] } ?? "Unknown",
                        locationInfo: viewModel.locationInfoCache[job.station_id]
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadJobs(forceRefresh: true)
        }
        .alert(NSLocalizedString("Error", comment: ""), isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .navigationTitle(NSLocalizedString("Main_Industry_Jobs", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadJobs()
        }
    }
}

struct IndustryJobRow: View {
    let job: IndustryJob
    let blueprintName: String
    let productName: String
    let locationInfo: LocationInfoDetail?
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第一行：蓝图名称和状态
            HStack {
                Text(blueprintName)
                    .font(.headline)
                Spacer()
                Text(NSLocalizedString("Industry_Status_\(job.status)", comment: ""))
                    .font(.caption)
                    .foregroundColor(job.status == "active" ? .green : .secondary)
            }
            
            // 第二行：产品名称和数量
            HStack {
                Text(productName)
                    .font(.subheadline)
                Spacer()
                Text("\(job.runs) \(NSLocalizedString("Misc_number_item", comment: ""))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // 第三行：使用LocationInfoView显示位置信息
            HStack {
                LocationInfoView(
                    stationName: locationInfo?.stationName,
                    solarSystemName: locationInfo?.solarSystemName,
                    security: locationInfo?.security,
                    font: .caption,
                    textColor: .secondary
                )
                Spacer()
                Text(formatDate(job.end_date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
