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
    @Published var itemIcons: [Int: String] = [:]
    
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
        var typeIds = Set<Int>()
        for job in jobs {
            typeIds.insert(job.blueprint_type_id)
        }
        
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(typeIds.map { String($0) }.joined(separator: ",")))
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    itemNames[typeId] = name
                    if let iconFileName = row["icon_filename"] as? String {
                        itemIcons[typeId] = iconFileName
                    }
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
                        blueprintIcon: viewModel.itemIcons[job.blueprint_type_id],
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
    let blueprintIcon: String?
    let locationInfo: LocationInfoDetail?
    @StateObject private var databaseManager = DatabaseManager()
    
    // 计算进度
    private var progress: Double {
        let totalDuration = Double(job.duration)
        let elapsedTime = Date().timeIntervalSince(job.start_date)
        let progress = elapsedTime / totalDuration
        return min(max(progress, 0), 1) // 确保进度在0-1之间
    }
    
    // 根据活动类型返回颜色
    private var progressColor: Color {
        switch job.activity_id {
        case 1: // 制造
            return Color.yellow.opacity(0.8)
        case 3, 4: // 时间效率研究、材料效率研究
            return Color.blue.opacity(0.6)
        case 5: // 复制
            return Color.blue.opacity(0.3)
        case 8: // 发明
            return Color.blue.opacity(0.6)
        case 11: // 反应
            return Color.yellow.opacity(0.8)
        default:
            return Color.gray
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        NavigationLink(destination: ShowBluePrintInfo(blueprintID: job.blueprint_type_id, databaseManager: databaseManager)) {
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：蓝图图标、名称和状态
                HStack(spacing: 12) {
                    // 蓝图图标
                    if let iconFileName = blueprintIcon {
                        IconManager.shared.loadImage(for: iconFileName)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 32, height: 32)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // 蓝图名称和状态
                        Text(blueprintName)
                            .font(.headline)
                            .lineLimit(1)
                        
                        // 数量信息
                        Text("\(job.runs) \(NSLocalizedString("Misc_number_item_x", comment: ""))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 进度条
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // 背景
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                            .cornerRadius(2)
                        
                        // 进度
                        Rectangle()
                            .fill(progressColor)
                            .frame(width: geometry.size.width * progress, height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)
                .padding(.vertical, 4)
                
                // 第二行：位置信息和结束时间
                LocationInfoView(
                    stationName: locationInfo?.stationName,
                    solarSystemName: locationInfo?.solarSystemName,
                    security: locationInfo?.security,
                    font: .caption,
                    textColor: .secondary
                ).lineLimit(1)
                HStack{
                    Text(NSLocalizedString("Industry_Status_\(job.status)", comment: ""))
                        .font(.caption)
                        .foregroundColor(job.status == "active" ? .green : .secondary)
                    Spacer()
                    Text(formatDate(job.end_date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            }
            .padding(.vertical, 4)
        }
    }
}
