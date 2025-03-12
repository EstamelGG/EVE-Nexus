import SwiftUI

typealias IndustryJob = CharacterIndustryAPI.IndustryJob

@MainActor
class CharacterIndustryViewModel: ObservableObject {
    @Published var jobs: [IndustryJob] = []
    @Published var groupedJobs: [String: [IndustryJob]] = [:]  // 按日期分组的工作项目
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var itemNames: [Int: String] = [:]
    @Published var locationInfoCache: [Int64: LocationInfoDetail] = [:]
    @Published var itemIcons: [Int: String] = [:]
    @Published var currentTime: Date = .init()  // 当前时间，用于进度计算

    private let characterId: Int
    private let databaseManager: DatabaseManager
    private var updateTask: Task<Void, Never>?
    private var loadingTask: Task<Void, Never>?
    private var initialLoadDone = false

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }

    deinit {
        updateTask?.cancel()
        loadingTask?.cancel()
    }

    // 启动更新任务
    private func startUpdateTask() {
        stopUpdateTask()  // 确保先停止已有的任务

        updateTask = Task { @MainActor in
            while !Task.isCancelled {
                self.currentTime = Date()  // 更新当前时间，触发UI刷新
                try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5秒
            }
        }
    }

    // 停止更新任务
    private func stopUpdateTask() {
        updateTask?.cancel()
        updateTask = nil
    }

    // 将工作项目按日期分组
    private func groupJobsByDate() {
        var grouped = [String: [IndustryJob]]()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")!

        // 首先筛选出进行中和未交付的任务
        let activeJobs = jobs.filter { job in
            (job.status == "active" && job.end_date > Date())  // 正在进行中
                || job.status == "ready"  // 已完成但未交付
                || (job.status == "active" && job.end_date <= Date())  // 已完成但状态未更新
        }

        if !activeJobs.isEmpty {
            let sortedActiveJobs = activeJobs.sorted {
                let isActive1 = $0.status == "active" && $0.end_date > Date()
                let isActive2 = $1.status == "active" && $1.end_date > Date()
                if isActive1 != isActive2 {
                    return isActive1
                }

                if $0.start_date == $1.start_date {
                    return $0.job_id > $1.job_id
                }
                return $0.start_date > $1.start_date
            }
            grouped["active"] = sortedActiveJobs
        }

        // 创建一个已处理任务的ID集合
        let processedJobIds = Set(activeJobs.map { $0.job_id })

        // 处理其他任务
        for job in jobs {
            if processedJobIds.contains(job.job_id) {
                continue
            }

            let dateKey = dateFormatter.string(from: job.start_date)

            if grouped[dateKey] == nil {
                grouped[dateKey] = []
            }
            grouped[dateKey]?.append(job)
        }

        // 对每个组内的工作项目按开始时间降序排序
        for (key, value) in grouped where key != "active" {
            grouped[key] = value.sorted {
                if $0.start_date == $1.start_date {
                    return $0.job_id > $1.job_id
                }
                return $0.start_date > $1.start_date
            }
        }

        groupedJobs = grouped
    }

    func loadJobs(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone && !forceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil
            showError = false

            do {
                // 加载数据
                let jobs = try await CharacterIndustryAPI.shared.fetchIndustryJobs(
                    characterId: characterId,
                    forceRefresh: forceRefresh
                )

                if Task.isCancelled { return }

                // 更新数据
                self.jobs = jobs
                await loadItemNames()

                if Task.isCancelled { return }

                await loadLocationNames()

                if Task.isCancelled { return }

                groupJobsByDate()
                startUpdateTask()

                self.isLoading = false
                self.initialLoadDone = true

            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    private func loadItemNames() async {
        var typeIds = Set<Int>()
        for job in jobs {
            typeIds.insert(job.blueprint_type_id)
        }

        let query = """
                SELECT type_id, name, icon_filename
                FROM types
                WHERE type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ",")))
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String
                {
                    itemNames[typeId] = name
                    if let iconFileName = row["icon_filename"] as? String {
                        itemIcons[typeId] = iconFileName
                    }
                }
            }
        }
    }

    private func loadLocationNames() async {
        var locationIds = Set<Int64>()
        for job in jobs {
            locationIds.insert(job.station_id)
            locationIds.insert(job.facility_id)
        }

        let locationLoader = LocationInfoLoader(
            databaseManager: databaseManager, characterId: Int64(characterId)
        )
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

    private let outputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        _viewModel = StateObject(
            wrappedValue: CharacterIndustryViewModel(
                characterId: characterId,
                databaseManager: databaseManager
            ))
    }

    // 格式化日期显示
    private func formatDateHeader(_ dateKey: String) -> String {
        if dateKey == "active" {
            return NSLocalizedString("Industry_In_Progress", comment: "")
        }

        guard let date = displayDateFormatter.date(from: dateKey) else {
            return dateKey
        }

        outputDateFormatter.dateFormat = NSLocalizedString("Date_Format_Month_Day", comment: "")
        let dateText = outputDateFormatter.string(from: date)
        return String(format: NSLocalizedString("Industry_Started_On", comment: ""), dateText)
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
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                            Text(NSLocalizedString("Orders_No_Data", comment: ""))
                                .foregroundColor(.gray)
                        }
                        .padding()
                        Spacer()
                    }
                }
                .listSectionSpacing(.compact)
            } else {
                ForEach(
                    Array(viewModel.groupedJobs.keys).sorted { key1, key2 in
                        if key1 == "active" { return true }
                        if key2 == "active" { return false }
                        return key1 > key2
                    }, id: \.self
                ) { dateKey in
                    Section(
                        header: Text(formatDateHeader(dateKey))
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(viewModel.groupedJobs[dateKey] ?? [], id: \.job_id) { job in
                            IndustryJobRow(
                                job: job,
                                blueprintName: viewModel.itemNames[job.blueprint_type_id]
                                    ?? "Unknown",
                                blueprintIcon: viewModel.itemIcons[job.blueprint_type_id],
                                locationInfo: viewModel.locationInfoCache[job.station_id],
                                currentTime: viewModel.currentTime
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.loadJobs(forceRefresh: true)
        }
        .task {
            await viewModel.loadJobs()
        }
        .navigationTitle(NSLocalizedString("Main_Industry_Jobs", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct IndustryJobRow: View {
    let job: IndustryJob
    let blueprintName: String
    let blueprintIcon: String?
    let locationInfo: LocationInfoDetail?
    let currentTime: Date
    @StateObject private var databaseManager = DatabaseManager()

    // 计算进度
    private var progress: Double {
        // 先检查是否已完成（根据状态或时间）
        if job.status == "delivered" || job.status == "ready" || currentTime >= job.end_date {
            return 1.0
        }

        switch job.status {
        case "cancelled", "revoked", "failed":  // 已取消或失败
            return 1.0
        default:  // 进行中
            let totalDuration = Double(job.duration)
            let elapsedTime = currentTime.timeIntervalSince(job.start_date)
            let progress = elapsedTime / totalDuration
            return min(max(progress, 0), 1)
        }
    }

    // 根据活动类型和状态返回颜色
    private var progressColor: Color {
        // 先检查特殊状态
        switch job.status {
        case "cancelled", "revoked", "failed":  // 已取消或失败
            return .red
        case "delivered", "ready":  // 已完成
            return .green
        case "active", "paused":  // 进行中或暂停
            // 根据活动类型返回不同颜色
            switch job.activity_id {
            case 1:  // 制造
                return Color.yellow.opacity(0.8)
            case 3, 4:  // 时间效率研究、材料效率研究
                return Color.blue.opacity(0.6)
            case 5:  // 复制
                return Color.blue.opacity(0.3)
            case 8:  // 发明
                return Color.blue.opacity(0.6)
            case 11:  // 反应
                return Color.yellow.opacity(0.8)
            default:
                return Color.gray
            }
        default:
            return Color.gray
        }
    }

    // 计算剩余时间
    private func getRemainingTime() -> String {
        let remainingTime = job.end_date.timeIntervalSince(currentTime)

        if remainingTime <= 0 {
            // 根据状态返回不同的完成状态文本
            let statusText =
                job.status == "delivered"
                ? NSLocalizedString("Industry_Status_delivered", comment: "")
                : NSLocalizedString("Industry_Status_completed", comment: "")

            // 只在概率不为1且runs大于1时显示成功比例
            if job.probability != 1.0 && job.runs > 1 {
                let successfulRuns = job.successful_runs ?? 0
                return "\(statusText) (\(successfulRuns)/\(job.runs))"
            }
            return statusText
        }

        let days = Int(remainingTime) / (24 * 3600)
        let hours = (Int(remainingTime) % (24 * 3600)) / 3600
        let minutes = (Int(remainingTime) % 3600) / 60

        if days > 0 {
            if hours > 0 {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Days_Hours", comment: ""), days,
                    hours
                )
            } else {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Days", comment: ""), days
                )
            }
        } else if hours > 0 {
            if minutes > 0 {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Hours_Minutes", comment: ""),
                    hours, minutes
                )
            } else {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Hours", comment: ""), hours
                )
            }
        } else {
            return String(
                format: NSLocalizedString("Industry_Remaining_Minutes", comment: ""), minutes
            )
        }
    }

    // 修改时间显示格式
    private func getTimeDisplay() -> String {
        let dateStr = formatDate(job.end_date)

        // 如果已经完成，只显示完成时间
        if job.status == "delivered" || job.status == "ready" || currentTime >= job.end_date {
            return dateStr
        }

        // 如果是活动状态，添加剩余时间
        if job.status == "active" {
            return "\(dateStr)"
        }

        return dateStr
    }

    // 获取活动状态文本
    private func getActivityStatus() -> String {
        // 先检查特殊状态
        switch job.status {
        case "cancelled":
            return NSLocalizedString("Industry_Status_cancelled", comment: "")
        case "revoked":
            return NSLocalizedString("Industry_Status_revoked", comment: "")
        case "failed":
            return NSLocalizedString("Industry_Status_failed", comment: "")
        case "delivered":
            let statusText = NSLocalizedString("Industry_Status_delivered", comment: "")
            // 只在概率不为1且runs大于1时显示成功比例
            if job.probability != 1.0 && job.runs > 1 {
                let successfulRuns = job.successful_runs ?? 0
                return "\(statusText) (\(successfulRuns)/\(job.runs))"
            }
            return statusText
        case "ready":
            return NSLocalizedString("Industry_Status_ready", comment: "")
        default:
            // 检查是否已完成但未交付
            if currentTime >= job.end_date {
                return NSLocalizedString("Industry_Status_ready", comment: "")
            }

            if job.status != "active" {
                return NSLocalizedString("Industry_Status_\(job.status)", comment: "")
            }

            // 如果是活动状态，根据活动类型返回对应文本
            switch job.activity_id {
            case 1:
                return NSLocalizedString("Industry_Type_Manufacturing", comment: "")
            case 3:
                return NSLocalizedString("Industry_Type_Research_Time", comment: "")
            case 4:
                return NSLocalizedString("Industry_Type_Research_Material", comment: "")
            case 5:
                return NSLocalizedString("Industry_Type_Copying", comment: "")
            case 8:
                return NSLocalizedString("Industry_Type_Invention", comment: "")
            case 11:
                return NSLocalizedString("Industry_Type_Reaction", comment: "")
            default:
                return NSLocalizedString("Industry_Status_active", comment: "")
            }
        }
    }

    // 获取状态文本颜色
    private func getStatusColor() -> Color {
        switch job.status {
        case "cancelled", "revoked", "failed":
            return .red
        case "delivered":
            return .secondary
        case "ready":
            return .yellow
        case "active":
            if currentTime >= job.end_date {
                return .yellow  // 已完成但未交付
            }
            return .green
        default:
            return .secondary
        }
    }

    // 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter.string(from: date) + " UTC"
    }

    // 获取活动类型文本
    private func getActivityTypeText() -> String {
        switch job.activity_id {
        case 1:
            return NSLocalizedString("Industry_Type_Manufacturing", comment: "")
        case 3:
            return NSLocalizedString("Industry_Type_Research_Time", comment: "")
        case 4:
            return NSLocalizedString("Industry_Type_Research_Material", comment: "")
        case 5:
            return NSLocalizedString("Industry_Type_Copying", comment: "")
        case 8:
            return NSLocalizedString("Industry_Type_Invention", comment: "")
        case 11:
            return NSLocalizedString("Industry_Type_Reaction", comment: "")
        default:
            return ""
        }
    }

    var body: some View {
        NavigationLink(
            destination: ShowBluePrintInfo(
                blueprintID: job.blueprint_type_id, databaseManager: databaseManager
            )
        ) {
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
                        HStack(spacing: 4) {
                            Text("[\(getActivityTypeText())]")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(blueprintName)
                                .font(.headline)
                        }
                        .lineLimit(1)

                        // 数量信息
                        HStack {
                            Text(
                                job.activity_id == 5
                                    ? "\(job.runs) runs \(NSLocalizedString("Misc_number_item_x", comment: "")) \(job.licensed_runs ?? 0) copies"
                                    : "\(job.runs) runs \(NSLocalizedString("Misc_number_item_x", comment: ""))"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            Spacer()
                            if job.status == "active" {
                                Text("\(getRemainingTime())")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
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
                        .foregroundColor(getStatusColor())
                    Spacer()
                    Text("Finish on \(getTimeDisplay())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
