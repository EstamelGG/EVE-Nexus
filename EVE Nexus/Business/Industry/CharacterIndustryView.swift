import SwiftUI

typealias IndustryJob = CharacterIndustryAPI.IndustryJob

@MainActor
class CharacterIndustryViewModel: ObservableObject {
    @Published var jobs: [IndustryJob] = []
    @Published var groupedJobs: [String: [IndustryJob]] = [:]  // 按日期分组的工作项目
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
    
    // 将工作项目按日期分组
    private func groupJobsByDate() {
        let calendar = Calendar.current
        var grouped = [String: [IndustryJob]]()
        
        for job in jobs {
            // 获取开始日期的年月日部分
            let date = calendar.startOfDay(for: job.start_date)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")!
            let dateKey = dateFormatter.string(from: date)
            
            if grouped[dateKey] == nil {
                grouped[dateKey] = []
            }
            grouped[dateKey]?.append(job)
        }
        
        // 对每个组内的工作项目按开始时间排序
        for (key, value) in grouped {
            grouped[key] = value.sorted { $0.start_date < $1.start_date }
        }
        
        groupedJobs = grouped
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
            // 对工作项目进行分组
            groupJobsByDate()
            
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
    
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: CharacterIndustryViewModel(
            characterId: characterId,
            databaseManager: databaseManager
        ))
    }
    
    // 格式化日期显示
    private func formatDateHeader(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        inputFormatter.timeZone = TimeZone(identifier: "UTC")!
        
        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MM月dd日"
        outputFormatter.timeZone = TimeZone(identifier: "UTC")!
        return "开始于" + outputFormatter.string(from: date)
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if viewModel.groupedJobs.isEmpty {
                HStack {
                    Spacer()
                    Text(NSLocalizedString("Industry_No_Jobs", comment: ""))
                        .foregroundColor(.gray)
                    Spacer()
                }
            } else {
                ForEach(Array(viewModel.groupedJobs.keys).sorted(), id: \.self) { dateKey in
                    Section(header: Text(formatDateHeader(dateKey))
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    ) {
                        ForEach(viewModel.groupedJobs[dateKey] ?? []) { job in
                            IndustryJobRow(
                                job: job,
                                blueprintName: viewModel.itemNames[job.blueprint_type_id] ?? "Unknown",
                                blueprintIcon: viewModel.itemIcons[job.blueprint_type_id],
                                locationInfo: viewModel.locationInfoCache[job.station_id]
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
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
    
    // 根据活动类型和状态返回颜色
    private var progressColor: Color {
        // 先检查是否已完成（根据状态或时间）
        if job.status == "delivered" || job.status == "ready" || Date() >= job.end_date {
            return .green
        }
        
        switch job.status {
        case "cancelled", "revoked", "failed": // 已取消或失败
            return .red
        case "active", "paused": // 进行中或暂停
            // 根据活动类型返回不同颜色
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
        default:
            return Color.gray
        }
    }
    
    // 计算进度
    private var progress: Double {
        // 先检查是否已完成（根据状态或时间）
        if job.status == "delivered" || job.status == "ready" || Date() >= job.end_date {
            return 1.0
        }
        
        switch job.status {
        case "cancelled", "revoked", "failed": // 已取消或失败
            return 1.0
        default: // 进行中
            let totalDuration = Double(job.duration)
            let elapsedTime = Date().timeIntervalSince(job.start_date)
            let progress = elapsedTime / totalDuration
            return min(max(progress, 0), 1)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter.string(from: date) + " UTC"
    }
    
    // 计算剩余时间
    private func getRemainingTime() -> String {
        let remainingTime = job.end_date.timeIntervalSinceNow
        
        if remainingTime <= 0 {
            // 根据状态返回不同的完成状态文本
            let statusText = job.status == "delivered" ?
                NSLocalizedString("Industry_Status_delivered", comment: "") :
                NSLocalizedString("Industry_Status_completed", comment: "")
            
            // 只有在runs大于1时才显示成功比例
            if job.runs > 1 {
                return "\(statusText) (\(job.successful_runs)/\(job.runs))"
            }
            return statusText
        }
        
        let days = Int(remainingTime) / (24 * 3600)
        let hours = (Int(remainingTime) % (24 * 3600)) / 3600
        let minutes = (Int(remainingTime) % 3600) / 60
        
        if days > 0 {
            if hours > 0 {
                return String(format: NSLocalizedString("Industry_Remaining_Days_Hours", comment: ""), days, hours)
            } else {
                return String(format: NSLocalizedString("Industry_Remaining_Days", comment: ""), days)
            }
        } else if hours > 0 {
            if minutes > 0 {
                return String(format: NSLocalizedString("Industry_Remaining_Hours_Minutes", comment: ""), hours, minutes)
            } else {
                return String(format: NSLocalizedString("Industry_Remaining_Hours", comment: ""), hours)
            }
        } else {
            return String(format: NSLocalizedString("Industry_Remaining_Minutes", comment: ""), minutes)
        }
    }
    
    // 修改时间显示格式
    private func getTimeDisplay() -> String {
        let dateStr = formatDate(job.end_date)
        
        // 如果已经完成，只显示完成时间
        if job.status == "delivered" || job.status == "ready" || Date() >= job.end_date {
            return dateStr
        }
        
        // 如果是活动状态，添加剩余时间
        if job.status == "active" {
            return "\(dateStr) (\(getRemainingTime()))"
        }
        
        return dateStr
    }
    
    // 获取活动状态文本
    private func getActivityStatus() -> String {
        // 先检查是否已完成（根据状态或时间）
        if job.status == "delivered" || job.status == "ready" || Date() >= job.end_date {
            let statusText = job.status == "delivered" ?
                NSLocalizedString("Industry_Status_delivered", comment: "") :
                NSLocalizedString("Industry_Status_completed", comment: "")
            
            // 只有在runs大于1时才显示成功比例
            if job.runs > 1 {
                return "\(statusText) (\(job.successful_runs)/\(job.runs))"
            }
            return statusText
        }
        
        if job.status != "active" {
            return NSLocalizedString("Industry_Status_\(job.status)", comment: "")
        }
        
        // 如果是活动状态，根据活动类型返回对应文本
        switch job.activity_id {
        case 1:
            return NSLocalizedString("Industry_Status_Manufacturing", comment: "") // "制造中"
        case 3:
            return NSLocalizedString("Industry_Status_Research_Time", comment: "") // "时间效率研究中"
        case 4:
            return NSLocalizedString("Industry_Status_Research_Material", comment: "") // "材料效率研究中"
        case 5:
            return NSLocalizedString("Industry_Status_Copying", comment: "") // "复制中"
        case 8:
            return NSLocalizedString("Industry_Status_Invention", comment: "") // "发明中"
        case 11:
            return NSLocalizedString("Industry_Status_Reaction", comment: "") // "反应中"
        default:
            return NSLocalizedString("Industry_Status_active", comment: "") // "进行中"
        }
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
                HStack {
                    Text(getActivityStatus())
                        .font(.caption)
                        .foregroundColor(job.status == "active" ? .green : .secondary)
                    Spacer()
                    Text(getTimeDisplay())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
