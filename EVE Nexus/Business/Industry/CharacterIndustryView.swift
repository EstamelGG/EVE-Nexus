import SwiftUI

typealias IndustryJob = CharacterIndustryAPI.IndustryJob

@MainActor
class CharacterIndustryViewModel: ObservableObject {
    @Published var jobs: [IndustryJob] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var itemNames: [Int: String] = [:]
    @Published var locationNames: [Int64: String] = [:]
    
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
            locationIds.insert(job.blueprint_location_id)
            locationIds.insert(job.output_location_id)
        }
        
        // 先尝试从数据库获取空间站名称
        let query = """
            SELECT stationID, stationName
            FROM stations
            WHERE stationID IN (\(locationIds.map { String($0) }.joined(separator: ",")))
        """
        Logger.debug(query)
        if case .success(let rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let stationId = row["stationID"] as? Int64,
                   let name = row["stationName"] as? String {
                    locationNames[stationId] = name
                }
            }
        }
        
        // 对于未找到的ID，尝试通过API获取建筑物信息
        let remainingIds = locationIds.filter { locationNames[$0] == nil }
        for locationId in remainingIds {
            do {
                let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: locationId,
                    characterId: characterId
                )
                locationNames[locationId] = structureInfo.name
            } catch {
                Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
            }
        }
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
                        locationName: viewModel.locationNames[job.station_id] ?? "Unknown"
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
    let locationName: String
    
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
            
            // 第三行：地点和时间
            HStack {
                Text(locationName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatDate(job.end_date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
} 
