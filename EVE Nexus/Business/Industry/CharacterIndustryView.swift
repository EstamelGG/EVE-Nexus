import SwiftUI

typealias IndustryJob = CharacterIndustryAPI.IndustryJob

// 全局函数：获取活动类型对应的图标文件名
func getActivityTypeIcon(for activityId: Int) -> String {
    switch activityId {
    case 1: // 制造
        return "Icon_Manufacturing.png"
    case 3: // 时间效率研究
        return "Icon_ResearchTime.png"
    case 4: // 材料效率研究
        return "Icon_ResearchMaterial.png"
    case 5: // 复制
        return "Icon_Copying.png"
    case 8: // 发明
        return "Icon_Invention.png"
    case 9: // 反应
        return "Icon_reaction.png"
    default:
        return "Icon_Manufacturing.png"
    }
}

// 扩展IndustryJob来包含角色归属信息
struct IndustryJobWithOwner {
    let job: IndustryJob
    let ownerId: Int // 该工业项目归属的角色ID（人物工业为主号；军团工业为 installer_id）
    let isFromCorporation: Bool
}

// 进度更新 Actor（用于线程安全地更新进度）
actor IndustryProgressActor {
    private var current: Int = 0
    private let total: Int
    private let onUpdate: (Int, Int) -> Void

    init(total: Int, onUpdate: @escaping (Int, Int) -> Void) {
        self.total = total
        self.onUpdate = onUpdate
    }

    func increment() {
        current += 1
        onUpdate(current, total)
    }
}

// 技能加载进度更新 Actor（用于线程安全地更新技能加载进度）
actor SkillProgressActor {
    private var current: Int = 0
    private let total: Int
    private let onUpdate: (Int, Int) -> Void

    init(total: Int, onUpdate: @escaping (Int, Int) -> Void) {
        self.total = total
        self.onUpdate = onUpdate
    }

    func increment() {
        current += 1
        onUpdate(current, total)
    }
}

// 工业项目倒计时组件 - 使用SwiftUI原生TimelineView
struct IndustryCountdownView: View {
    let endDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Text(getDisplayText(at: context.date))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func getDisplayText(at currentDate: Date) -> String {
        let remainingTime = endDate.timeIntervalSince(currentDate)

        if remainingTime <= 0 {
            return NSLocalizedString("Industry_Status_completed", comment: "")
        }

        let totalSeconds = Int(remainingTime)
        let days = totalSeconds / (24 * 3600)
        let hours = (totalSeconds % (24 * 3600)) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if days > 0 {
            if hours > 0 {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Days_Hours", comment: ""),
                    days, hours
                )
            } else {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Days", comment: ""),
                    days
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
                    format: NSLocalizedString("Industry_Remaining_Hours", comment: ""),
                    hours
                )
            }
        } else if minutes > 0 {
            return String(
                format: NSLocalizedString("Industry_Remaining_Minutes_Seconds", comment: "%d分%d秒"),
                minutes, seconds
            )
        } else {
            return String(
                format: NSLocalizedString("Industry_Remaining_Seconds", comment: "%d秒"),
                seconds
            )
        }
    }
}

// 工业项目实时进度条组件
struct IndustryProgressView: View {
    let job: IndustryJob

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            PulsingProgressBar(
                progress: getProgress(at: context.date),
                color: getProgressColor(at: context.date),
                height: 4,
                cornerRadius: 2
            )
        }
    }

    private func getProgress(at currentDate: Date) -> Double {
        // 先检查是否已完成（根据状态或时间）
        if job.status == "delivered" || job.status == "ready" || currentDate >= job.end_date {
            return 1.0
        }

        switch job.status {
        case "cancelled", "revoked", "failed": // 已取消或失败
            return 1.0
        default: // 进行中
            let totalDuration = Double(job.duration)
            let elapsedTime = currentDate.timeIntervalSince(job.start_date)
            let progress = elapsedTime / totalDuration
            return min(max(progress, 0), 1)
        }
    }

    private func getProgressColor(at _: Date) -> Color {
        // 先检查特殊状态
        switch job.status {
        case "cancelled", "revoked", "failed": // 已取消或失败
            return .red
        case "delivered", "ready": // 已完成
            return .green
        case "active", "paused": // 进行中或暂停
            // 根据活动类型返回不同颜色
            switch job.activity_id {
            case 1: // 制造
                return Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
            case 3, 4: // 时间效率研究、材料效率研究
                return Color.blue
            case 5: // 复制
                return Color.blue
            case 8: // 发明
                return Color.blue
            case 9: // 反应
                return Color.cyan
            default:
                return Color.gray
            }
        default:
            return Color.gray
        }
    }
}

// 人物详细信息结构体
struct CharacterSlotDetail {
    let characterId: Int
    let characterName: String
    let manufacturingSlots: Int
    let researchSlots: Int
    let reactionSlots: Int
    let manufacturingRange: Int
    let researchRange: Int
    let reactionRange: Int
    let manufacturingUsed: Int
    let researchUsed: Int
    let reactionUsed: Int
}

@MainActor
class CharacterIndustryViewModel: ObservableObject {
    // 配置常量
    private let soonCompleteThreshold: TimeInterval = 8 * 3600 // 即将完成阈值：8小时

    @Published var jobs: [IndustryJob] = []
    @Published var groupedJobs: [String: [IndustryJob]] = [:] // 按日期分组的工作项目
    var jobsWithOwner: [IndustryJobWithOwner] = [] // 包含所有者信息的工业项目
    @Published var isLoading = true
    @Published var isFiltering = false // 新增：过滤刷新状态
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var loadingProgress: (current: Int, total: Int)? = nil // 工业项目加载进度 (已加载/总数)
    @Published var skillLoadingProgress: (current: Int, total: Int)? = nil // 技能加载进度 (已加载/总数)
    @Published var itemNames: [Int: String] = [:]
    @Published var locationInfoCache: [Int64: LocationInfoDetail] = [:]
    @Published var itemIcons: [Int: String] = [:]

    // 多人物聚合相关
    @Published var multiCharacterMode = false {
        didSet {
            UserDefaults.standard.set(multiCharacterMode, forKey: "multiCharacterMode_industry")
            if initialLoadDone {
                Task {
                    // 重新计算槽位和操作范围
                    await loadMaxSlots(forceRefresh: true)
                    await loadOperationRanges(forceRefresh: true)
                    // 重新加载工业项目数据
                    await loadJobs(forceRefresh: true, isFiltering: true)
                }
            }
        }
    }

    @Published var selectedCharacterIds: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_industry"
            )
            if initialLoadDone, multiCharacterMode {
                Task {
                    // 重新计算槽位和操作范围
                    await loadMaxSlots(forceRefresh: true)
                    await loadOperationRanges(forceRefresh: true)
                    // 重新加载工业项目数据
                    await loadJobs(forceRefresh: true, isFiltering: true)
                }
            }
        }
    }

    @Published var availableCharacters: [(id: Int, name: String)] = []

    // 发起人信息缓存
    @Published var installerNames: [Int: String] = [:]
    @Published var installerImages: [Int: UIImage] = [:]

    // 过滤设置
    @Published var hideCompletedAndCancelled = false {
        didSet {
            UserDefaults.standard.set(
                hideCompletedAndCancelled, forKey: "hideCompletedAndCancelled_global"
            )
            // 当隐藏完成项目设置发生变化时，强制刷新数据
            if initialLoadDone {
                Task {
                    await loadJobs(forceRefresh: true, isFiltering: true)
                }
            }
        }
    }

    @Published var selectedActivityTypes: Set<Int> = [1, 3, 4, 5, 8, 9] // 默认全选
    @Published var selectedInstallers: Set<Int> = [] // 发起人筛选（仅在聚合模式下使用）
    @Published var selectedSolarSystems: Set<String> = []

    // 可用的活动类型
    let availableActivityTypes = [1, 3, 4, 5, 8, 9] // 制造、ME研究、TE研究、复制、发明、反应

    // 可用的发起人列表（仅在聚合模式下使用）
    @Published var availableInstallers: [Int] = []

    // 可用的星系列表
    @Published var availableSolarSystems: [String] = []

    // 添加工业槽位统计相关属性
    @Published var manufacturingSlots: (used: Int, total: Int) = (0, 0)
    @Published var researchSlots: (used: Int, total: Int) = (0, 0)
    @Published var reactionSlots: (used: Int, total: Int) = (0, 0)

    // 添加操作范围相关属性
    @Published var manufacturingRange: Int = 0 // 加工类项目操作范围
    @Published var researchRange: Int = 0 // 科研类项目操作范围
    @Published var reactionRange: Int = 0 // 反应类项目操作范围

    // 缓存最大槽位数据，在初始化时计算一次
    private var maxSlots: (manufacturing: Int, research: Int, reaction: Int) = (1, 1, 1)

    // 缓存每个角色的详细信息
    @Published var characterSlotDetails: [CharacterSlotDetail] = []

    // 生产清单数据
    struct ProductionItem {
        let typeId: Int
        let typeName: String
        let typeIcon: String
        var totalQuantity: Int
    }

    @Published var productionList: [ProductionItem] = []

    private let characterId: Int
    private let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    private var initialLoadDone = false
    private var cachedJobs: [IndustryJob]? // 缓存工业项目数据

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        self.databaseManager = databaseManager

        // 从 UserDefaults 读取全局设置
        hideCompletedAndCancelled = UserDefaults.standard.bool(
            forKey: "hideCompletedAndCancelled_global")

        // 从 UserDefaults 读取多人物聚合设置
        multiCharacterMode = UserDefaults.standard.bool(forKey: "multiCharacterMode_industry")
        let savedCharacterIds =
            UserDefaults.standard.array(forKey: "selectedCharacterIds_industry") as? [Int] ?? []
        selectedCharacterIds = Set(savedCharacterIds)

        // 加载可用角色列表
        availableCharacters = CharacterSkillsUtils.getAllCharacters()

        // 过滤掉已保存但已不在可用角色列表中的角色ID
        let availableCharacterIds = Set(availableCharacters.map { $0.id })
        let validSelectedIds = selectedCharacterIds.intersection(availableCharacterIds)

        // 如果有角色被过滤掉，更新 UserDefaults
        if validSelectedIds.count != selectedCharacterIds.count {
            selectedCharacterIds = validSelectedIds
            UserDefaults.standard.set(
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_industry"
            )
        }

        // 如果没有选中的角色，默认选择当前角色
        if selectedCharacterIds.isEmpty {
            selectedCharacterIds.insert(characterId)
        }

        // 在初始化时立即加载技能数据和工业任务数据
        Task {
            // 先加载技能数据计算最大槽位和操作范围
            await loadMaxSlots()
            await loadOperationRanges()
            // 然后加载工业任务数据
            await loadJobs()
        }
    }

    deinit {
        loadingTask?.cancel()
    }

    // 刷新所有数据（包括技能数据）
    func refreshAllIndustryData() async {
        // 重新加载技能数据（槽位和操作范围）- 强制刷新
        await loadMaxSlots(forceRefresh: true)
        await loadOperationRanges(forceRefresh: true)
        // 重新加载工业项目数据
        await loadJobs(forceRefresh: true)
    }

    // 将工作项目按状态分组
    private func groupJobsByStatus() {
        var grouped = [String: [IndustryJob]]()
        let currentTime = Date()

        for job in jobs {
            let groupKey: String

            if job.status == "ready" || (job.status == "active" && job.end_date <= currentTime) {
                // 已完成但未交付的项目
                groupKey = "ready"
            } else if job.status == "active" && job.end_date > currentTime {
                // 检查是否即将完成（剩余时间小于阈值）
                let remainingTime = job.end_date.timeIntervalSince(currentTime)

                if remainingTime <= soonCompleteThreshold {
                    // 即将完成的项目
                    groupKey = "soon"
                } else {
                    // 正在进行中的项目
                    groupKey = "active"
                }
            } else if job.status == "delivered" || job.status == "cancelled"
                || job.status == "revoked" || job.status == "failed"
            {
                // 已交付或已取消的项目
                groupKey = "completed"
            } else {
                // 其他状态归为已完成
                groupKey = "completed"
            }

            if grouped[groupKey] == nil {
                grouped[groupKey] = []
            }
            grouped[groupKey]?.append(job)
        }

        // 对每个组内的工作项目排序
        for (key, value) in grouped {
            switch key {
            case "ready":
                // 已完成未交付：按job_id排序
                grouped[key] = value.sorted { $0.job_id > $1.job_id }
            case "soon":
                // 即将完成：按剩余时间从短到长排序
                grouped[key] = value.sorted { $0.end_date < $1.end_date }
            case "active":
                // 正在进行中：按剩余时间从短到长排序
                grouped[key] = value.sorted { $0.end_date < $1.end_date }
            case "completed":
                // 已交付/已取消：按完成时间从近到远排序
                grouped[key] = value.sorted {
                    let date1 = $0.completed_date ?? $0.end_date
                    let date2 = $1.completed_date ?? $1.end_date
                    return date1 > date2
                }
            default:
                break
            }
        }

        groupedJobs = grouped
    }

    func loadJobs(forceRefresh: Bool = false, isFiltering: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone, !forceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            // 根据是否是过滤刷新来设置不同的加载状态
            if isFiltering {
                self.isFiltering = true
            } else {
                self.isLoading = true
            }
            errorMessage = nil
            showError = false

            do {
                // 加载数据
                let jobs = try await fetchJobs(forceRefresh: forceRefresh)

                if Task.isCancelled { return }

                // 更新数据
                self.jobs = jobs
                await loadItemNames()

                if Task.isCancelled { return }

                await loadLocationNames()

                if Task.isCancelled { return }

                groupJobsByStatus()

                // 更新过滤选项
                updateFilterOptions()

                // 计算工业槽位统计
                calculateIndustrySlotStats()

                // 更新characterSlotDetails中的已用槽位数
                updateCharacterSlotUsedCounts()

                // 计算生产清单
                calculateProductionList()

                // 根据是否是过滤刷新来清除相应的加载状态
                if isFiltering {
                    self.isFiltering = false
                } else {
                    self.isLoading = false
                }
                self.initialLoadDone = true

                // 如果是多人物模式，在后台加载发起人信息（不阻塞列表显示）
                if multiCharacterMode {
                    Task {
                        await loadInstallerInfo()
                    }
                }

            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isLoading = false
                    self.isFiltering = false
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    // 封装获取数据逻辑，处理缓存
    private func fetchJobs(forceRefresh: Bool = false) async throws -> [IndustryJob] {
        // 如果不是强制刷新且有缓存，直接返回缓存
        if !forceRefresh, let cached = cachedJobs {
            Logger.info("使用内存缓存的工业项目数据")
            return cached
        }

        var allJobs: [IndustryJob] = []
        var allJobsWithOwner: [IndustryJobWithOwner] = []

        if multiCharacterMode, selectedCharacterIds.count > 1 {
            // 多人物模式：并发获取所有选中人物的工业项目
            let totalCharacters = selectedCharacterIds.count

            // 初始化加载进度
            await MainActor.run {
                self.loadingProgress = (current: 0, total: totalCharacters)
            }

            // 使用 Actor 来线程安全地更新进度
            let progressActor = IndustryProgressActor(total: totalCharacters) { current, total in
                Task { @MainActor in
                    self.loadingProgress = (current: current, total: total)
                }
            }

            await withTaskGroup(of: (Int, Result<[IndustryJob], Error>).self) { group in
                for characterId in selectedCharacterIds {
                    group.addTask { [weak self] in
                        guard let self = self else { return (characterId, .failure(NSError(domain: "CharacterIndustryViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "ViewModel已释放"]))) }
                        do {
                            let jobs = try await CharacterIndustryAPI.shared.fetchIndustryJobs(
                                characterId: characterId,
                                forceRefresh: forceRefresh,
                                includeCompleted: !self.hideCompletedAndCancelled
                            )
                            return (characterId, .success(jobs))
                        } catch {
                            Logger.error("获取角色\(characterId)工业项目失败: \(error)")
                            return (characterId, .failure(error))
                        }
                    }
                }

                // 收集结果
                for await (characterId, result) in group {
                    switch result {
                    case let .success(jobs):
                        allJobs.append(contentsOf: jobs)
                        // 为每个项目添加所有者信息
                        for job in jobs {
                            allJobsWithOwner.append(
                                IndustryJobWithOwner(
                                    job: job, ownerId: characterId, isFromCorporation: false
                                ))
                        }
                    case .failure:
                        // 失败时继续处理，不中断
                        break
                    }

                    // 更新进度
                    await progressActor.increment()
                }
            }

            // 清除加载进度
            await MainActor.run {
                self.loadingProgress = nil
            }
        } else {
            // 单人物模式：只获取当前角色或选中的唯一角色
            let targetCharacterId =
                multiCharacterMode && !selectedCharacterIds.isEmpty
                    ? selectedCharacterIds.first!
                    : characterId

            allJobs = try await CharacterIndustryAPI.shared.fetchIndustryJobs(
                characterId: targetCharacterId,
                forceRefresh: forceRefresh,
                includeCompleted: !hideCompletedAndCancelled
            )

            // 单人模式也创建所有者信息
            for job in allJobs {
                allJobsWithOwner.append(
                    IndustryJobWithOwner(
                        job: job, ownerId: targetCharacterId, isFromCorporation: false
                    ))
            }
        }

        let characterIdsForCorpMerge: Set<Int> = {
            if multiCharacterMode, !selectedCharacterIds.isEmpty {
                return selectedCharacterIds
            }
            return [characterId]
        }()

        await appendCorpIndustryJobs(
            forCharacterIds: characterIdsForCorpMerge,
            allJobs: &allJobs,
            allJobsWithOwner: &allJobsWithOwner,
            forceRefresh: forceRefresh
        )

        // 更新缓存
        cachedJobs = allJobs
        jobsWithOwner = allJobsWithOwner

        return allJobs
    }

    /// 在个人工业列表之后，合并这些角色所在军团（军团 ID 去重）的工业项目。
    private func appendCorpIndustryJobs(
        forCharacterIds characterIds: Set<Int>,
        allJobs: inout [IndustryJob],
        allJobsWithOwner: inout [IndustryJobWithOwner],
        forceRefresh: Bool
    ) async {
        let includeCompleted = !hideCompletedAndCancelled

        var corpIdToCharacterIds: [Int: [Int]] = [:]
        for cid in characterIds {
            do {
                if let corpId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                    characterId: cid)
                {
                    corpIdToCharacterIds[corpId, default: []].append(cid)
                }
            } catch {
                continue
            }
        }

        let uniqueCorpIds = Array(corpIdToCharacterIds.keys)
        guard !uniqueCorpIds.isEmpty else { return }

        var corpJobBatches: [[CorpIndustryAPI.CorpIndustryJob]] = []

        await withTaskGroup(of: Result<[CorpIndustryAPI.CorpIndustryJob], Error>.self) { group in
            for corpId in uniqueCorpIds {
                guard let tokenCharacterId = corpIdToCharacterIds[corpId]?.sorted().first else {
                    continue
                }
                group.addTask {
                    do {
                        let jobs = try await CorpIndustryAPI.shared.fetchCorpIndustryJobsForCorporation(
                            corporationId: corpId,
                            characterId: tokenCharacterId,
                            forceRefresh: forceRefresh,
                            includeCompleted: includeCompleted,
                            progressCallback: nil
                        )
                        return .success(jobs)
                    } catch {
                        Logger.error(
                            "获取军团 \(corpId) 工业项目失败（跳过，可能无权限）: \(error.localizedDescription)"
                        )
                        return .failure(error)
                    }
                }
            }

            for await result in group {
                if case let .success(jobs) = result {
                    corpJobBatches.append(jobs)
                }
            }
        }

        var seenJobIds = Set(allJobs.map(\.job_id))
        let allowedInstallers = characterIds

        for batch in corpJobBatches {
            for cj in batch {
                guard allowedInstallers.contains(cj.installer_id) else { continue }
                let ij = Self.industryJob(fromCorpJob: cj)
                if seenJobIds.insert(ij.job_id).inserted {
                    allJobs.append(ij)
                    allJobsWithOwner.append(
                        IndustryJobWithOwner(
                            job: ij, ownerId: cj.installer_id, isFromCorporation: true
                        ))
                }
            }
        }
    }

    private static func industryJob(fromCorpJob corp: CorpIndustryAPI.CorpIndustryJob) -> IndustryJob {
        IndustryJob(
            activity_id: corp.activity_id,
            blueprint_id: corp.blueprint_id,
            blueprint_location_id: corp.blueprint_location_id,
            blueprint_type_id: corp.blueprint_type_id,
            completed_character_id: corp.completed_character_id,
            completed_date: corp.completed_date,
            cost: corp.cost,
            duration: corp.duration,
            end_date: corp.end_date,
            facility_id: corp.facility_id,
            installer_id: corp.installer_id,
            job_id: corp.job_id,
            licensed_runs: corp.licensed_runs,
            output_location_id: corp.output_location_id,
            pause_date: corp.pause_date,
            probability: corp.probability,
            product_type_id: corp.product_type_id,
            runs: corp.runs,
            start_date: corp.start_date,
            station_id: corp.location_id,
            status: corp.status,
            successful_runs: corp.successful_runs
        )
    }

    func isJobFromCorporation(_ job: IndustryJob) -> Bool {
        jobsWithOwner.first(where: { $0.job.job_id == job.job_id })?.isFromCorporation ?? false
    }

    private func loadItemNames() async {
        var typeIds = Set<Int>()
        for job in jobs {
            typeIds.insert(job.blueprint_type_id)
        }

        // 如果没有物品ID，直接返回
        if typeIds.isEmpty {
            return
        }

        Logger.debug("开始批量加载\(typeIds.count)个蓝图信息")

        // 使用IN查询一次性获取所有物品信息
        let placeholders = Array(repeating: "?", count: typeIds.count).joined(separator: ",")
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(placeholders))
        """

        // 将Set转换为数组作为参数
        let parameters = typeIds.map { $0 as Any }

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: parameters) {
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
            Logger.success("成功加载了\(rows.count)个蓝图信息")
        } else {
            Logger.error("批量加载蓝图信息失败")
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

    // 加载发起人信息
    private func loadInstallerInfo() async {
        // 从jobsWithOwner中收集所有唯一的角色ID
        let installerIds = Set(jobsWithOwner.map { $0.ownerId })

        // 如果没有发起人ID，直接返回
        if installerIds.isEmpty {
            return
        }

        Logger.debug("开始加载\(installerIds.count)个发起人信息")

        // 并发获取发起人信息（网络请求在后台线程执行，只有更新UI时才切换到主线程）
        await withTaskGroup(of: Void.self) { group in
            for installerId in installerIds {
                group.addTask {
                    do {
                        // 网络请求在后台线程执行
                        let info = try await CharacterAPI.shared.fetchCharacterPublicInfo(
                            characterId: installerId, forceRefresh: false
                        )
                        let image = try await CharacterAPI.shared.fetchCharacterPortrait(
                            characterId: installerId, size: 64, forceRefresh: false,
                            catchImage: true
                        )

                        // 更新UI相关的@Published属性时切换到主线程
                        await MainActor.run {
                            self.installerNames[installerId] = info.name
                            self.installerImages[installerId] = image
                        }

                        Logger.success("成功加载发起人信息 - ID: \(installerId), 名称: \(info.name)")
                    } catch {
                        Logger.error("加载发起人信息失败 - ID: \(installerId), 错误: \(error)")
                        // 设置默认值，避免重复尝试
                        await MainActor.run {
                            self.installerNames[installerId] = "Unknown"
                        }
                    }
                }
            }
        }

        Logger.debug("完成加载发起人信息")
    }

    // 过滤后的分组数据
    var filteredGroupedJobs: [String: [IndustryJob]] {
        var filtered = [String: [IndustryJob]]()

        for (groupKey, jobs) in groupedJobs {
            // 如果隐藏已交付和已取消，跳过completed组
            if hideCompletedAndCancelled, groupKey == "completed" {
                continue
            }

            let filteredJobs = jobs.filter { job in
                // 按活动类型过滤
                let activityMatches = selectedActivityTypes.contains(job.activity_id)

                // 按发起人过滤（仅在聚合模式下且选择了多个人物时才应用）
                var installerMatches = true
                if multiCharacterMode, selectedCharacterIds.count > 1,
                   !selectedInstallers.isEmpty
                {
                    // 从jobsWithOwner中找到该项目的所有者
                    if let jobWithOwner = jobsWithOwner.first(where: { $0.job.job_id == job.job_id }
                    ) {
                        installerMatches = selectedInstallers.contains(jobWithOwner.ownerId)
                    } else {
                        installerMatches = false
                    }
                }

                // 按星系过滤
                var solarSystemMatches = true
                if !selectedSolarSystems.isEmpty {
                    if let locationInfo = locationInfoCache[job.station_id] {
                        solarSystemMatches = selectedSolarSystems.contains(
                            locationInfo.solarSystemName)
                    } else {
                        solarSystemMatches = false
                    }
                }

                return activityMatches && installerMatches && solarSystemMatches
            }

            if !filteredJobs.isEmpty {
                filtered[groupKey] = filteredJobs
            }
        }

        return filtered
    }

    // 更新过滤选项
    private func updateFilterOptions() {
        // 更新可用的发起人列表（仅在聚合模式下且选择了多个人物时）
        if multiCharacterMode, selectedCharacterIds.count > 1 {
            let installerIds = Array(Set(jobsWithOwner.map { $0.ownerId }))
            let newAvailableInstallers = installerIds.sorted { id1, id2 in
                let name1 = installerNames[id1] ?? "Unknown"
                let name2 = installerNames[id2] ?? "Unknown"
                return name1.localizedCompare(name2) == .orderedAscending
            }

            // 检查发起人列表是否发生了变化
            let installersChanged = Set(newAvailableInstallers) != Set(availableInstallers)
            availableInstallers = newAvailableInstallers

            // 如果发起人列表发生了变化，自动选中所有发起人
            if installersChanged, !availableInstallers.isEmpty {
                selectedInstallers = Set(availableInstallers)
            } else if selectedInstallers.isEmpty, !availableInstallers.isEmpty {
                // 自动初始化过滤器选择（只在首次加载时）
                selectedInstallers = Set(availableInstallers)
            }
        } else {
            // 非聚合模式或只选择了一个人物，清空发起人筛选
            availableInstallers = []
            selectedInstallers = []
        }

        // 更新可用的星系列表，按星系名称排序
        var solarSystems = Set<String>()
        for job in jobs {
            if let locationInfo = locationInfoCache[job.station_id] {
                solarSystems.insert(locationInfo.solarSystemName)
            }
        }
        let newAvailableSolarSystems = Array(solarSystems).sorted {
            $0.localizedCompare($1) == .orderedAscending
        }

        // 检查星系列表是否发生了变化
        let solarSystemsChanged = Set(newAvailableSolarSystems) != Set(availableSolarSystems)
        availableSolarSystems = newAvailableSolarSystems

        // 如果星系列表发生了变化（比如切换了hideCompletedAndCancelled设置），自动选中所有星系
        if solarSystemsChanged, !availableSolarSystems.isEmpty {
            selectedSolarSystems = Set(availableSolarSystems)
        } else if selectedSolarSystems.isEmpty, !availableSolarSystems.isEmpty {
            // 自动初始化过滤器选择（只在首次加载时）
            selectedSolarSystems = Set(availableSolarSystems)
        }
    }

    // 获取星系的安全等级信息
    func getSolarSystemSecurity(_ systemName: String) -> Double? {
        // 从locationInfoCache中查找该星系的安全等级
        for (_, locationInfo) in locationInfoCache {
            if locationInfo.solarSystemName == systemName {
                return locationInfo.security
            }
        }
        return nil
    }

    // 加载最大槽位数据
    private func loadMaxSlots(forceRefresh: Bool = false) async {
        maxSlots = await calculateMaxIndustrySlots(forceRefresh: forceRefresh)
    }

    // 计算并缓存所有角色的详细信息
    private func calculateCharacterSlotDetails(forceRefresh: Bool = false) async -> [CharacterSlotDetail] {
        // 获取技能槽位增加属性的映射
        let attributeQuery = """
            SELECT type_id, attribute_id, value 
            FROM typeAttributes 
            WHERE attribute_id IN (450, 471, 2661)
        """

        var skillSlotBonuses: [Int: (manufacturing: Int, research: Int, reaction: Int)] = [:]

        if case let .success(rows) = databaseManager.executeQuery(attributeQuery) {
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                      let attributeId = row["attribute_id"] as? Int,
                      let value = row["value"] as? Double
                else { continue }

                if skillSlotBonuses[typeId] == nil {
                    skillSlotBonuses[typeId] = (manufacturing: 0, research: 0, reaction: 0)
                }

                let intValue = Int(value)
                switch attributeId {
                case 450: // 加工任务槽位增加数
                    skillSlotBonuses[typeId]?.manufacturing = intValue
                case 471: // 科研槽位增加数
                    skillSlotBonuses[typeId]?.research = intValue
                case 2661: // 反应任务增加数
                    skillSlotBonuses[typeId]?.reaction = intValue
                default:
                    break
                }
            }
        }

        // 确定要计算的角色ID列表（按ID排序）
        let characterIdsToCalculate: [Int]
        if multiCharacterMode, selectedCharacterIds.count > 1 {
            characterIdsToCalculate = Array(selectedCharacterIds).sorted()
        } else if multiCharacterMode, !selectedCharacterIds.isEmpty {
            characterIdsToCalculate = Array(selectedCharacterIds).sorted()
        } else {
            characterIdsToCalculate = [characterId]
        }

        // 初始化技能加载进度
        let totalCharacters = characterIdsToCalculate.count
        await MainActor.run {
            self.skillLoadingProgress = (current: 0, total: totalCharacters)
        }

        // 使用 Actor 来线程安全地更新进度
        let progressActor = SkillProgressActor(total: totalCharacters) { current, total in
            Task { @MainActor in
                self.skillLoadingProgress = (current: current, total: total)
            }
        }

        // 技能数据结果结构（仅包含需要并发获取的数据）
        struct SkillData {
            let characterId: Int
            let manufacturingSlots: Int
            let researchSlots: Int
            let reactionSlots: Int
            let manufacturingRange: Int
            let researchRange: Int
            let reactionRange: Int
        }

        var skillDataResults: [SkillData] = []

        // 并发获取所有角色的技能数据（仅网络请求部分）
        await withTaskGroup(of: SkillData?.self) { group in
            for charId in characterIdsToCalculate {
                group.addTask {
                    // 每个角色的基础槽位数
                    var manufacturingSlots = 1
                    var researchSlots = 1
                    var reactionSlots = 1
                    var manufacturingRange = 0
                    var researchRange = 0
                    var reactionRange = 0

                    // 使用 CharacterSkillsAPI 获取角色技能数据
                    do {
                        let skillsResponse = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                            characterId: charId,
                            forceRefresh: forceRefresh
                        )

                        // 遍历技能槽位加成，从技能映射中查找对应技能
                        for (skillId, bonus) in skillSlotBonuses {
                            if let skill = skillsResponse.skillsMap[skillId] {
                                let level = skill.trained_skill_level
                                manufacturingSlots += bonus.manufacturing * level
                                researchSlots += bonus.research * level
                                reactionSlots += bonus.reaction * level
                            }
                        }

                        // 计算操作范围
                        manufacturingRange = (skillsResponse.skillsMap[24268]?.trained_skill_level ?? 0) * 5
                        researchRange = (skillsResponse.skillsMap[24270]?.trained_skill_level ?? 0) * 5
                        reactionRange = (skillsResponse.skillsMap[45750]?.trained_skill_level ?? 0) * 5

                        // 更新技能加载进度
                        await progressActor.increment()
                    } catch {
                        Logger.error("获取角色\(charId)技能数据失败: \(error)")
                        // 即使失败也要更新进度
                        await progressActor.increment()
                        return nil
                    }

                    return SkillData(
                        characterId: charId,
                        manufacturingSlots: manufacturingSlots,
                        researchSlots: researchSlots,
                        reactionSlots: reactionSlots,
                        manufacturingRange: manufacturingRange,
                        researchRange: researchRange,
                        reactionRange: reactionRange
                    )
                }
            }

            // 收集结果
            for await skillData in group {
                if let skillData = skillData {
                    skillDataResults.append(skillData)
                }
            }
        }

        // 在并发任务外处理本地数据（角色名称和已用槽位数）
        let availableCharactersSnapshot = await MainActor.run { self.availableCharacters }
        let jobsWithOwnerSnapshot = await MainActor.run { self.jobsWithOwner }

        var details: [CharacterSlotDetail] = []
        for skillData in skillDataResults {
            // 获取角色名称
            let characterName = availableCharactersSnapshot.first(where: { $0.id == skillData.characterId })?.name ?? "Unknown"

            // 计算该角色的已用槽位数
            let characterJobs = jobsWithOwnerSnapshot.filter { $0.ownerId == skillData.characterId }.map { $0.job }
            let activeJobs = characterJobs.filter { job in
                (job.status == "active" && job.end_date > Date()) // 正在进行中
                    || job.status == "ready" // 已完成但未交付
                    || (job.status == "active" && job.end_date <= Date()) // 已完成但状态未更新
            }

            let manufacturingUsed = activeJobs.filter { $0.activity_id == 1 }.count
            let researchUsed = activeJobs.filter { [3, 4, 5, 8].contains($0.activity_id) }.count
            let reactionUsed = activeJobs.filter { $0.activity_id == 9 }.count

            details.append(CharacterSlotDetail(
                characterId: skillData.characterId,
                characterName: characterName,
                manufacturingSlots: skillData.manufacturingSlots,
                researchSlots: skillData.researchSlots,
                reactionSlots: skillData.reactionSlots,
                manufacturingRange: skillData.manufacturingRange,
                researchRange: skillData.researchRange,
                reactionRange: skillData.reactionRange,
                manufacturingUsed: manufacturingUsed,
                researchUsed: researchUsed,
                reactionUsed: reactionUsed
            ))
        }

        // 按角色ID排序，保持一致性
        details.sort { $0.characterId < $1.characterId }

        // 清除技能加载进度
        await MainActor.run {
            self.skillLoadingProgress = nil
        }

        return details
    }

    // 计算生产清单
    func calculateProductionList() {
        // 计算制造项目（activity_id == 1）和反应项目（activity_id == 9）
        // 只计算正在加工（status == "active" && end_date > Date()）和待交付（status == "ready"）的项目
        let productionJobs = jobs.filter { job in
            (job.activity_id == 1 || job.activity_id == 9) && (
                (job.status == "active" && job.end_date > Date()) ||
                    job.status == "ready"
            )
        }

        // 统计每个产品的总数量
        var productMap: [Int: ProductionItem] = [:]

        for job in productionJobs {
            if let productInfo = BlueprintCalcUtil.getBlueprintProductInfo(
                blueprintId: job.blueprint_type_id,
                runs: job.runs
            ) {
                if let existing = productMap[productInfo.typeId] {
                    // 如果已存在，累加数量
                    productMap[productInfo.typeId] = ProductionItem(
                        typeId: existing.typeId,
                        typeName: existing.typeName,
                        typeIcon: existing.typeIcon,
                        totalQuantity: existing.totalQuantity + productInfo.totalQuantity
                    )
                } else {
                    // 如果不存在，创建新条目
                    productMap[productInfo.typeId] = ProductionItem(
                        typeId: productInfo.typeId,
                        typeName: productInfo.typeName,
                        typeIcon: productInfo.typeIcon,
                        totalQuantity: productInfo.totalQuantity
                    )
                }
            }
        }

        // 转换为数组并按产品名称排序
        productionList = Array(productMap.values).sorted { $0.typeName.localizedCompare($1.typeName) == .orderedAscending }
    }

    // 更新已用槽位数（在loadJobs完成后调用）
    private func updateCharacterSlotUsedCounts() {
        // 如果characterSlotDetails为空，说明还没有计算过，直接返回
        guard !characterSlotDetails.isEmpty else { return }

        // 重新创建characterSlotDetails数组，更新已用槽位数
        characterSlotDetails = characterSlotDetails.map { detail in
            // 计算该角色的已用槽位数
            let characterJobs = jobsWithOwner.filter { $0.ownerId == detail.characterId }.map { $0.job }
            let activeJobs = characterJobs.filter { job in
                (job.status == "active" && job.end_date > Date()) // 正在进行中
                    || job.status == "ready" // 已完成但未交付
                    || (job.status == "active" && job.end_date <= Date()) // 已完成但状态未更新
            }

            let manufacturingUsed = activeJobs.filter { $0.activity_id == 1 }.count
            let researchUsed = activeJobs.filter { [3, 4, 5, 8].contains($0.activity_id) }.count
            let reactionUsed = activeJobs.filter { $0.activity_id == 9 }.count

            return CharacterSlotDetail(
                characterId: detail.characterId,
                characterName: detail.characterName,
                manufacturingSlots: detail.manufacturingSlots,
                researchSlots: detail.researchSlots,
                reactionSlots: detail.reactionSlots,
                manufacturingRange: detail.manufacturingRange,
                researchRange: detail.researchRange,
                reactionRange: detail.reactionRange,
                manufacturingUsed: manufacturingUsed,
                researchUsed: researchUsed,
                reactionUsed: reactionUsed
            )
        }
    }

    // 加载操作范围技能等级
    private func loadOperationRanges(forceRefresh: Bool = false) async {
        // 如果已经有缓存的详细信息，直接使用
        if !characterSlotDetails.isEmpty, !forceRefresh {
            let maxManufacturingRange = characterSlotDetails.map { $0.manufacturingRange }.max() ?? 0
            let maxResearchRange = characterSlotDetails.map { $0.researchRange }.max() ?? 0
            let maxReactionRange = characterSlotDetails.map { $0.reactionRange }.max() ?? 0

            manufacturingRange = maxManufacturingRange
            researchRange = maxResearchRange
            reactionRange = maxReactionRange
            return
        }

        // 重新计算详细信息
        let details = await calculateCharacterSlotDetails(forceRefresh: forceRefresh)
        characterSlotDetails = details

        // 计算最大操作范围
        let maxManufacturingRange = details.map { $0.manufacturingRange }.max() ?? 0
        let maxResearchRange = details.map { $0.researchRange }.max() ?? 0
        let maxReactionRange = details.map { $0.reactionRange }.max() ?? 0

        manufacturingRange = maxManufacturingRange
        researchRange = maxResearchRange
        reactionRange = maxReactionRange
    }

    // 获取操作范围显示文本
    func getOperationRangeText(_ range: Int) -> String {
        if range == 0 {
            return NSLocalizedString("Industry_Range_Current_System", comment: "当前星系")
        } else {
            return String.localizedStringWithFormat(NSLocalizedString("Industry_Range_Jumps", comment: "%d 跳"), range)
        }
    }

    // 计算工业槽位统计（只计算使用数量，不重新计算最大值）
    private func calculateIndustrySlotStats() {
        // 计算当前使用的槽位数，包括已完成但未交付的任务
        let activeJobs = jobs.filter { job in
            (job.status == "active" && job.end_date > Date()) // 正在进行中
                || job.status == "ready" // 已完成但未交付
                || (job.status == "active" && job.end_date <= Date()) // 已完成但状态未更新
        }

        let manufacturingUsed = activeJobs.filter { $0.activity_id == 1 }.count
        let researchUsed = activeJobs.filter { [3, 4, 5, 8].contains($0.activity_id) }.count
        let reactionUsed = activeJobs.filter { $0.activity_id == 9 }.count

        // 取计算出的最大槽位数和实际使用数量中的较大值，避免缓存不同步问题
        let actualManufacturingTotal = max(maxSlots.manufacturing, manufacturingUsed)
        let actualResearchTotal = max(maxSlots.research, researchUsed)
        let actualReactionTotal = max(maxSlots.reaction, reactionUsed)

        manufacturingSlots = (used: manufacturingUsed, total: actualManufacturingTotal)
        researchSlots = (used: researchUsed, total: actualResearchTotal)
        reactionSlots = (used: reactionUsed, total: actualReactionTotal)
    }

    // 计算最大工业槽位数
    private func calculateMaxIndustrySlots(forceRefresh: Bool = false) async -> (
        manufacturing: Int, research: Int, reaction: Int
    ) {
        // 如果已经有缓存的详细信息，直接使用
        if !characterSlotDetails.isEmpty, !forceRefresh {
            let totalManufacturingSlots = characterSlotDetails.reduce(0) { $0 + $1.manufacturingSlots }
            let totalResearchSlots = characterSlotDetails.reduce(0) { $0 + $1.researchSlots }
            let totalReactionSlots = characterSlotDetails.reduce(0) { $0 + $1.reactionSlots }

            return (
                manufacturing: totalManufacturingSlots,
                research: totalResearchSlots,
                reaction: totalReactionSlots
            )
        }

        // 重新计算详细信息
        let details = await calculateCharacterSlotDetails(forceRefresh: forceRefresh)
        characterSlotDetails = details

        // 累计所有角色的槽位
        let totalManufacturingSlots = details.reduce(0) { $0 + $1.manufacturingSlots }
        let totalResearchSlots = details.reduce(0) { $0 + $1.researchSlots }
        let totalReactionSlots = details.reduce(0) { $0 + $1.reactionSlots }

        return (
            manufacturing: totalManufacturingSlots,
            research: totalResearchSlots,
            reaction: totalReactionSlots
        )
    }
}

struct CharacterIndustryView: View {
    let characterId: Int
    @StateObject private var viewModel: CharacterIndustryViewModel
    @State private var showFilterSheet = false
    @State private var showSettingsSheet = false
    @State private var showSlotDetailSheet = false
    @State private var showProductionListSheet = false

    init(characterId: Int, databaseManager: DatabaseManager = DatabaseManager()) {
        self.characterId = characterId
        // 创建ViewModel
        let vm = CharacterIndustryViewModel(
            characterId: characterId, databaseManager: databaseManager
        )
        _viewModel = StateObject(wrappedValue: vm)

        // ViewModel已在其init方法中启动数据加载，此处无需重复加载
    }

    // 格式化状态组标题
    private func formatStatusGroupHeader(_ statusKey: String) -> String {
        switch statusKey {
        case "ready":
            return NSLocalizedString("Industry_Ready_For_Delivery", comment: "准备交付")
        case "soon":
            return NSLocalizedString("Industry_Soon_Complete", comment: "即将完成")
        case "active":
            return NSLocalizedString("Industry_In_Progress", comment: "进行中")
        case "completed":
            return NSLocalizedString("Industry_Completed_Cancelled", comment: "已交付/已取消")
        default:
            return statusKey
        }
    }

    // 获取工业项目的发起人名称
    private func getInstallerName(for job: IndustryJob) -> String? {
        // 从jobsWithOwner中找到该项目的所有者
        if let jobWithOwner = viewModel.jobsWithOwner.first(where: { $0.job.job_id == job.job_id }) {
            return viewModel.installerNames[jobWithOwner.ownerId]
        }
        return nil
    }

    // 获取工业项目的发起人头像
    private func getInstallerImage(for job: IndustryJob) -> UIImage? {
        // 从jobsWithOwner中找到该项目的所有者
        if let jobWithOwner = viewModel.jobsWithOwner.first(where: { $0.job.job_id == job.job_id }) {
            return viewModel.installerImages[jobWithOwner.ownerId]
        }
        return nil
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                VStack(alignment: .center, spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)

                    // 显示工业项目加载进度（如果有多人物模式且正在加载）
                    if let progress = viewModel.loadingProgress, progress.total > 1 {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Industry_Loading_Progress", comment: "已加载人物 %d/%d"), progress.current, progress.total))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // 显示技能加载进度
                    if let skillProgress = viewModel.skillLoadingProgress, skillProgress.total > 0 {
                        Text(String.localizedStringWithFormat(NSLocalizedString("Industry_Loading_Skills_Progress", comment: "正在加载技能数据 %d/%d"), skillProgress.current, skillProgress.total))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                // 工业槽位统计 Section - 始终显示
                Section(
                    header: HStack {
                        Text(NSLocalizedString("Industry_Slots_Header", comment: "工业槽位"))
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                        Spacer()
                        Button(action: {
                            showSlotDetailSheet = true
                        }) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                        }
                    }
                ) {
                    // 加工任务
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString(
                                        "Industry_Slots_Manufacturing", comment: "加工任务"
                                    )
                                )
                                .font(.body)
                                Text(
                                    "\(NSLocalizedString("Industry_Operation_Range", comment: "操作范围"))：\(viewModel.getOperationRangeText(viewModel.manufacturingRange))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(viewModel.manufacturingSlots.used)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(.secondary)
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.manufacturingSlots.total)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255))
                            }
                        }
                    }

                    // 研究任务
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Industry_Slots_Research", comment: "研究任务"))
                                    .font(.body)
                                Text(
                                    "\(NSLocalizedString("Industry_Operation_Range", comment: "操作范围"))：\(viewModel.getOperationRangeText(viewModel.researchRange))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(viewModel.researchSlots.used)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(.secondary)
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.researchSlots.total)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(Color.blue) // 蓝色
                            }
                        }
                    }

                    // 反应任务
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Industry_Slots_Reaction", comment: "反应任务"))
                                    .font(.body)
                                Text(
                                    "\(NSLocalizedString("Industry_Operation_Range", comment: "操作范围"))：\(viewModel.getOperationRangeText(viewModel.reactionRange))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(viewModel.reactionSlots.used)")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .fontDesign(.monospaced)
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(viewModel.reactionSlots.total)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(Color.cyan) // 青蓝色
                            }
                        }
                    }

                    // 生产清单
                    Button(action: {
                        showProductionListSheet = true
                    }) {
                        HStack {
                            Text(NSLocalizedString("Industry_Production_List", comment: "生产清单"))
                                .font(.body)
                                .foregroundColor(.primary)
                            Spacer()
                            if !viewModel.productionList.isEmpty {
                                Text("\(viewModel.productionList.count)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                .listSectionSpacing(.compact)

                // 过滤刷新指示器
                if viewModel.isFiltering {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(
                                    NSLocalizedString(
                                        "Industry_Filtering_Data", comment: "正在更新数据..."
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                }

                // 工业任务列表部分
                if viewModel.filteredGroupedJobs.isEmpty && !viewModel.isFiltering {
                    Section {
                        // 计算总项目数和过滤后的项目数
                        let totalJobsCount = viewModel.groupedJobs.values.reduce(0) {
                            $0 + $1.count
                        }
                        let _ = viewModel.filteredGroupedJobs.values.reduce(0) { $0 + $1.count }

                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 30))
                                    .foregroundColor(.secondary)
                                Text(NSLocalizedString("Misc_No_Data", comment: ""))
                                    .foregroundColor(.secondary)

                                // 如果有总项目但被过滤完了，显示过滤信息
                                if totalJobsCount > 0 {
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Industry_Filtered_Count", comment: "已过滤 %d 个项目"
                                            ),
                                            totalJobsCount
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                }
                            }
                            .padding()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                } else if !viewModel.isFiltering {
                    // 按优先级排序：ready -> soon -> active -> completed
                    ForEach(
                        ["ready", "soon", "active", "completed"].filter {
                            viewModel.filteredGroupedJobs.keys.contains($0)
                        },
                        id: \.self
                    ) { statusKey in
                        Section(
                            header: HStack {
                                Text(formatStatusGroupHeader(statusKey))
                                    .fontWeight(.semibold)
                                    .font(.system(size: 18))
                                    .foregroundColor(.primary)
                                    .textCase(.none)

                                Spacer()

                                // 显示每个section的项目数量
                                let sectionCount =
                                    viewModel.filteredGroupedJobs[statusKey]?.count ?? 0
                                Text("(\(sectionCount))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        ) {
                            ForEach(viewModel.filteredGroupedJobs[statusKey] ?? [], id: \.job_id) {
                                job in
                                IndustryJobRow(
                                    job: job,
                                    blueprintName: viewModel.itemNames[job.blueprint_type_id]
                                        ?? "Unknown BP",
                                    blueprintIcon: viewModel.itemIcons[job.blueprint_type_id],
                                    locationInfo: viewModel.locationInfoCache[job.station_id],
                                    currentTime: Date(), // 使用当前时间作为倒计时基准
                                    showInstaller: viewModel.multiCharacterMode,
                                    installerName: getInstallerName(for: job),
                                    installerImage: getInstallerImage(for: job),
                                    isFromCorporation: viewModel.isJobFromCorporation(job)
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refreshAllIndustryData()
        }
        .navigationTitle(NSLocalizedString("Main_Industry_Jobs", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: {
                        showSettingsSheet = true
                    }) {
                        Image(systemName: "gear")
                    }

                    Button(action: {
                        showFilterSheet = true
                    }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            IndustryFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSettingsSheet) {
            IndustrySettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showSlotDetailSheet) {
            IndustrySlotDetailSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showProductionListSheet) {
            IndustryProductionListSheet(viewModel: viewModel)
        }
    }
}

struct IndustryJobRow: View {
    let job: IndustryJob
    let blueprintName: String
    let blueprintIcon: String?
    let locationInfo: LocationInfoDetail?
    let currentTime: Date
    let showInstaller: Bool
    let installerName: String?
    let installerImage: UIImage?
    let isFromCorporation: Bool
    @StateObject private var databaseManager = DatabaseManager()
    @Environment(\.colorScheme) private var colorScheme

    // 带颜色的状态文本结构体
    struct StatusText {
        let text: String
        let color: Color
    }

    // 修改时间显示格式
    private func getTimeDisplay() -> String {
        let currentTime = Date()
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

    // 获取活动状态文本和颜色
    private func getActivityStatus() -> StatusText {
        // 先检查特殊状态
        switch job.status {
        case "cancelled":
            return StatusText(
                text:
                "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_cancelled", comment: ""))",
                color: .red
            )
        case "revoked":
            return StatusText(
                text:
                "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_revoked", comment: ""))",
                color: .red
            )
        case "failed":
            return StatusText(
                text:
                "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_failed", comment: ""))",
                color: .red
            )
        case "delivered":
            let statusText = NSLocalizedString("Industry_Status_delivered", comment: "")
            var finalText = "\(getActivityTypeText())·\(statusText)"
            // 只针对发明类项目显示成功率数量
            if job.probability != nil && job.runs > 0 && job.activity_id == 8 {
                let successfulRuns = job.successful_runs ?? 0
                finalText = "\(getActivityTypeText())·\(statusText) (\(successfulRuns)/\(job.runs))"
            }
            return StatusText(text: finalText, color: .secondary)
        case "ready":
            return StatusText(
                text:
                "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_ready", comment: ""))",
                color: .green
            )
        default:
            // 检查是否已完成但未交付
            if Date() >= job.end_date {
                return StatusText(
                    text:
                    "\(getActivityTypeText())·\(NSLocalizedString("Industry_Status_ready", comment: ""))",
                    color: .green
                )
            }

            if job.status != "active" {
                return StatusText(
                    text: NSLocalizedString("Industry_Status_\(job.status)", comment: ""),
                    color: .secondary
                )
            }

            // 如果是活动状态，根据活动类型返回对应文本和颜色
            // https://sde.hoboleaks.space/tq/industryactivities.json
            switch job.activity_id {
            case 1:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
                )
            case 3:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.blue
                )
            case 4:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.blue
                )
            case 5:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.blue
                )
            case 8:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.blue
                )
            case 9:
                return StatusText(
                    text: getActivityTypeText(),
                    color: Color.cyan
                )
            default:
                return StatusText(
                    text: NSLocalizedString("Industry_Status_active", comment: ""),
                    color: .secondary
                )
            }
        }
    }

    // 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    // 获取活动类型文本（军团挂接任务会附加后缀）
    private func getActivityTypeText() -> String {
        let base: String
        switch job.activity_id {
        case 1:
            base = NSLocalizedString("Industry_Type_Manufacturing_Short", comment: "")
        case 3:
            base = NSLocalizedString("Industry_Type_Research_Time_Short", comment: "")
        case 4:
            base = NSLocalizedString("Industry_Type_Research_Material_Short", comment: "")
        case 5:
            base = NSLocalizedString("Industry_Type_Copying", comment: "")
        case 8:
            base = NSLocalizedString("Industry_Type_Invention", comment: "")
        case 9:
            base = NSLocalizedString("Industry_Type_Reaction", comment: "")
        default:
            base = ""
        }
        if isFromCorporation, !base.isEmpty {
            return base + NSLocalizedString("Industry_Job_Source_Corp_Suffix", comment: "")
        }
        return base
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
                        HStack(spacing: 6) {
                            // 工业类型图标
                            if colorScheme == .light {
                                IconManager.shared.loadImage(
                                    for: getActivityTypeIcon(for: job.activity_id)
                                )
                                .resizable()
                                .frame(width: 14, height: 14)
                                .cornerRadius(2)
                                .colorInvert()
                            } else {
                                IconManager.shared.loadImage(
                                    for: getActivityTypeIcon(for: job.activity_id)
                                )
                                .resizable()
                                .frame(width: 14, height: 14)
                                .cornerRadius(2)
                            }

                            Text(blueprintName)
                                .font(.headline)
                                .lineLimit(1)

                            Spacer()

                            // 已完成可交付标记
                            if job.status == "ready" || (job.status == "active" && currentTime >= job.end_date) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16))
                            }
                        }

                        // 数量信息
                        HStack {
                            Text(
                                job.activity_id == 5
                                    ? String(
                                        format: NSLocalizedString(
                                            "Industry_Runs_With_Copies_Format", comment: ""
                                        ),
                                        job.runs, job.licensed_runs ?? 1
                                    )
                                    : String(
                                        format: NSLocalizedString(
                                            "Industry_Runs_Format", comment: ""
                                        ), job.runs
                                    )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            Spacer()
                            if job.status == "active" {
                                IndustryCountdownView(endDate: job.end_date)
                            }
                        }
                    }
                }

                // 进度条
                IndustryProgressView(job: job)
                    .padding(.vertical, 4)

                // 第二行：位置信息和发起人信息
                if showInstaller && installerName != nil {
                    GeometryReader { geometry in
                        HStack(spacing: 8) {
                            // 左侧 2/3：位置信息
                            LocationInfoView(
                                stationName: locationInfo?.stationName,
                                solarSystemName: locationInfo?.solarSystemName,
                                security: locationInfo?.security,
                                font: .caption,
                                textColor: .secondary
                            )
                            .lineLimit(1)
                            .frame(width: geometry.size.width * 0.67, alignment: .leading)

                            Spacer()

                            // 右侧 1/3：发起人信息
                            if let installerName = installerName {
                                HStack(spacing: 4) {
                                    // 发起人头像
                                    if let installerImage = installerImage {
                                        Image(uiImage: installerImage)
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    } else {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 18, height: 18)
                                    }

                                    // 发起人名称
                                    Text(installerName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: geometry.size.width * 0.33 - 8, alignment: .trailing)
                            }
                        }
                    }
                    .frame(height: 16)
                } else {
                    // 单人模式：只显示位置信息
                    LocationInfoView(
                        stationName: locationInfo?.stationName,
                        solarSystemName: locationInfo?.solarSystemName,
                        security: locationInfo?.security,
                        font: .caption,
                        textColor: .secondary
                    )
                    .lineLimit(1)
                }
                HStack {
                    let statusInfo = getActivityStatus()
                    Text(statusInfo.text)
                        .font(.caption)
                        .foregroundColor(statusInfo.color)
                    Spacer()

                    // 根据完成状态显示不同的时间前缀
                    let isCompleted = job.status == "delivered" || job.status == "ready" || currentTime >= job.end_date
                    let timePrefix = isCompleted
                        ? NSLocalizedString("Industry_Completed_At", comment: "已完成于")
                        : NSLocalizedString("Finished_on", comment: "")

                    Text("\(timePrefix) \(getTimeDisplay())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .contextMenu {
            // 复制发起人名称
            if showInstaller, let installerName = installerName {
                Button {
                    UIPasteboard.general.string = installerName
                } label: {
                    Label(
                        NSLocalizedString("Industry_Copy_Installer_Name", comment: "复制发起人名称: %@"),
                        systemImage: "person.crop.circle"
                    )
                }
            }

            // 复制地点信息
            if let locationInfo = locationInfo {
                Button {
                    let locationText =
                        !locationInfo.stationName.isEmpty
                            ? locationInfo.stationName : locationInfo.solarSystemName
                    UIPasteboard.general.string = locationText
                } label: {
                    Label(
                        NSLocalizedString("Misc_Copy_Location", comment: "复制地点"),
                        systemImage: "doc.on.doc"
                    )
                }
            }
        }
    }
}

struct IndustrySettingsSheet: View {
    @ObservedObject var viewModel: CharacterIndustryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: $viewModel.multiCharacterMode) {
                        VStack(alignment: .leading) {
                            Text(
                                NSLocalizedString(
                                    "Industry_Settings_Multi_Character", comment: "多人物聚合"
                                ))
                            Text(
                                NSLocalizedString(
                                    "Industry_Settings_Multi_Character_Description",
                                    comment: "聚合显示多个角色的工业项目数据"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                // 只有在多人物模式开启时才显示角色选择
                if viewModel.multiCharacterMode {
                    Section(
                        header: Text(
                            NSLocalizedString(
                                "Industry_Settings_Select_Characters", comment: "选择角色"
                            ))
                    ) {
                        ForEach(viewModel.availableCharacters, id: \.id) { character in
                            Button(action: {
                                if viewModel.selectedCharacterIds.contains(character.id) {
                                    viewModel.selectedCharacterIds.remove(character.id)
                                } else {
                                    viewModel.selectedCharacterIds.insert(character.id)
                                }
                            }) {
                                HStack {
                                    // 角色头像
                                    CharacterPortraitView(characterId: character.id)
                                        .padding(.trailing, 8)

                                    Text(character.name)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if viewModel.selectedCharacterIds.contains(character.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // 全选/全不选按钮
                        Button(action: {
                            if viewModel.selectedCharacterIds.count
                                == viewModel.availableCharacters.count
                            {
                                viewModel.selectedCharacterIds = []
                            } else {
                                viewModel.selectedCharacterIds = Set(
                                    viewModel.availableCharacters.map { $0.id })
                            }
                        }) {
                            HStack {
                                Text(NSLocalizedString("Industry_Filter_Select_All", comment: "全选"))
                                Spacer()
                                if viewModel.selectedCharacterIds.count
                                    == viewModel.availableCharacters.count
                                {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Industry_Settings_Title", comment: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct IndustryFilterSheet: View {
    @ObservedObject var viewModel: CharacterIndustryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // 获取活动类型的本地化名称
    private func getActivityTypeName(_ activityId: Int) -> String {
        switch activityId {
        case 1:
            return NSLocalizedString("Industry_Type_Manufacturing_Short", comment: "制造")
        case 3:
            return NSLocalizedString("Industry_Type_Research_Time_Short", comment: "时间效率研究")
        case 4:
            return NSLocalizedString("Industry_Type_Research_Material_Short", comment: "材料效率研究")
        case 5:
            return NSLocalizedString("Industry_Type_Copying", comment: "复制")
        case 8:
            return NSLocalizedString("Industry_Type_Invention", comment: "发明")
        case 9:
            return NSLocalizedString("Industry_Type_Reaction", comment: "反应")
        default:
            return "Unknown Activity \(activityId)"
        }
    }

    // 获取活动类型对应的颜色
    private func getActivityTypeColor(_ activityId: Int) -> Color {
        switch activityId {
        case 1: // 制造
            return Color(red: 0.9, green: 0.7, blue: 0.3) // 土黄色
        case 3, 4, 5, 8: // 时间效率研究、材料效率研究、复制、发明
            return Color.blue // 蓝色
        case 9: // 反应
            return Color.cyan // 青蓝色
        default:
            return Color.gray
        }
    }

    var body: some View {
        NavigationView {
            Form {
                // 第一个section：隐藏已交付和已取消的项目
                Section {
                    Toggle(isOn: $viewModel.hideCompletedAndCancelled) {
                        VStack(alignment: .leading) {
                            Text(
                                NSLocalizedString(
                                    "Industry_Filter_Hide_Completed", comment: "隐藏已交付和已取消的项目"
                                ))
                            Text(
                                NSLocalizedString(
                                    "Industry_Filter_Hide_Completed_Description",
                                    comment: "隐藏已完成、已取消、已撤销等状态的项目"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                // 第二个section：按项目类型过滤
                Section {
                    ForEach(viewModel.availableActivityTypes, id: \.self) { activityId in
                        Button(action: {
                            if viewModel.selectedActivityTypes.contains(activityId) {
                                viewModel.selectedActivityTypes.remove(activityId)
                            } else {
                                viewModel.selectedActivityTypes.insert(activityId)
                            }
                        }) {
                            HStack {
                                // 添加彩色圆点
                                Circle()
                                    .fill(getActivityTypeColor(activityId))
                                    .frame(width: 8, height: 8)

                                // 添加工业类型图标
                                if colorScheme == .light {
                                    IconManager.shared.loadImage(
                                        for: getActivityTypeIcon(for: activityId)
                                    )
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .cornerRadius(4)
                                    .colorInvert()
                                } else {
                                    IconManager.shared.loadImage(
                                        for: getActivityTypeIcon(for: activityId)
                                    )
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                    .cornerRadius(4)
                                }
                                Text(getActivityTypeName(activityId))
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.selectedActivityTypes.contains(activityId) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                } header: {
                    HStack {
                        Text(NSLocalizedString("Industry_Filter_Activity_Types", comment: "项目类型"))
                        Spacer()
                        Button(action: {
                            if viewModel.selectedActivityTypes.count
                                == viewModel.availableActivityTypes.count
                            {
                                viewModel.selectedActivityTypes = []
                            } else {
                                viewModel.selectedActivityTypes = Set(
                                    viewModel.availableActivityTypes)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Industry_Filter_Select_All", comment: "全选"))
                                    .font(.caption)
                                if viewModel.selectedActivityTypes.count
                                    == viewModel.availableActivityTypes.count
                                {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // 第三个section：按发起人过滤（仅在聚合模式下且选择了多个人物时显示）
                if viewModel.multiCharacterMode && viewModel.selectedCharacterIds.count > 1
                    && !viewModel.availableInstallers.isEmpty
                {
                    Section {
                        ForEach(viewModel.availableInstallers, id: \.self) { installerId in
                            Button(action: {
                                if viewModel.selectedInstallers.contains(installerId) {
                                    viewModel.selectedInstallers.remove(installerId)
                                } else {
                                    viewModel.selectedInstallers.insert(installerId)
                                }
                            }) {
                                HStack {
                                    // 显示发起人头像和名称
                                    if let installerImage = viewModel.installerImages[installerId] {
                                        Image(uiImage: installerImage)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                    } else {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 32, height: 32)
                                    }

                                    Text(viewModel.installerNames[installerId] ?? "Unknown")
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if viewModel.selectedInstallers.contains(installerId) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Industry_Filter_Installers", comment: "发起人"))
                            Spacer()
                            Button(action: {
                                if viewModel.selectedInstallers.count
                                    == viewModel.availableInstallers.count
                                {
                                    viewModel.selectedInstallers = []
                                } else {
                                    viewModel.selectedInstallers = Set(
                                        viewModel.availableInstallers)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(
                                        NSLocalizedString(
                                            "Industry_Filter_Select_All", comment: "全选"
                                        )
                                    )
                                    .font(.caption)
                                    if viewModel.selectedInstallers.count
                                        == viewModel.availableInstallers.count
                                    {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // 第四个section：按星系过滤
                if !viewModel.availableSolarSystems.isEmpty {
                    Section {
                        ForEach(viewModel.availableSolarSystems, id: \.self) { solarSystem in
                            Button(action: {
                                if viewModel.selectedSolarSystems.contains(solarSystem) {
                                    viewModel.selectedSolarSystems.remove(solarSystem)
                                } else {
                                    viewModel.selectedSolarSystems.insert(solarSystem)
                                }
                            }) {
                                HStack {
                                    // 安全等级和星系名称
                                    if let security = viewModel.getSolarSystemSecurity(solarSystem) {
                                        Text(formatSystemSecurity(security))
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(getSecurityColor(security))
                                        Text(solarSystem)
                                            .foregroundColor(.primary)
                                    } else {
                                        Text(solarSystem)
                                            .foregroundColor(.primary)
                                    }

                                    Spacer()
                                    if viewModel.selectedSolarSystems.contains(solarSystem) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Industry_Filter_Solar_Systems", comment: "星系"))
                            Spacer()
                            Button(action: {
                                if viewModel.selectedSolarSystems.count
                                    == viewModel.availableSolarSystems.count
                                {
                                    viewModel.selectedSolarSystems = []
                                } else {
                                    viewModel.selectedSolarSystems = Set(
                                        viewModel.availableSolarSystems)
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Text(
                                        NSLocalizedString(
                                            "Industry_Filter_Select_All", comment: "全选"
                                        )
                                    )
                                    .font(.caption)
                                    if viewModel.selectedSolarSystems.count
                                        == viewModel.availableSolarSystems.count
                                    {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Industry_Filter_Title", comment: "过滤设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct IndustrySlotDetailSheet: View {
    @ObservedObject var viewModel: CharacterIndustryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                // 只显示选中的人物信息
                ForEach(viewModel.characterSlotDetails, id: \.characterId) { detail in
                    Section(
                        header: HStack {
                            CharacterPortraitView(characterId: detail.characterId)
                                .padding(.trailing, 8)
                            Text(detail.characterName)
                                .fontWeight(.semibold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        }
                    ) {
                        // 加工任务槽位
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString(
                                        "Industry_Slots_Manufacturing", comment: "加工任务"
                                    )
                                )
                                .font(.body)
                                Text(
                                    viewModel.getOperationRangeText(detail.manufacturingRange)
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(detail.manufacturingUsed)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        detail.manufacturingUsed >= detail.manufacturingSlots ? .red : .green
                                    )
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(detail.manufacturingSlots)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
                                    )
                            }
                        }
                        .padding(.vertical, 4)

                        // 研究任务槽位
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString("Industry_Slots_Research", comment: "研究任务")
                                )
                                .font(.body)
                                Text(
                                    viewModel.getOperationRangeText(detail.researchRange)
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(detail.researchUsed)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        detail.researchUsed >= detail.researchSlots ? .red : .green
                                    )
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(detail.researchSlots)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(Color.blue)
                            }
                        }
                        .padding(.vertical, 4)

                        // 反应任务槽位
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString("Industry_Slots_Reaction", comment: "反应任务")
                                )
                                .font(.body)
                                Text(
                                    viewModel.getOperationRangeText(detail.reactionRange)
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 0) {
                                Text("\(detail.reactionUsed)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(
                                        detail.reactionUsed >= detail.reactionSlots ? .red : .green
                                    )
                                Text(" / ")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                Text("\(detail.reactionSlots)")
                                    .font(.body)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(Color.cyan)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Industry_Slots_Detail_Title", comment: "槽位详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct IndustryProductionListSheet: View {
    @ObservedObject var viewModel: CharacterIndustryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if viewModel.productionList.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 30))
                                    .foregroundColor(.secondary)
                                Text(NSLocalizedString("Industry_Production_List_Empty", comment: "暂无生产项目"))
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                } else {
                    ForEach(viewModel.productionList, id: \.typeId) { item in
                        HStack(spacing: 12) {
                            // 产品图标
                            if !item.typeIcon.isEmpty {
                                IconManager.shared.loadImage(for: item.typeIcon)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 40, height: 40)
                            }

                            // 产品名称和数量
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.typeName)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Industry_Production_Quantity", comment: "数量: %d"
                                        ),
                                        item.totalQuantity
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }

                            Spacer()

                            // 数量（右侧显示）
                            Text("\(item.totalQuantity)")
                                .font(.body)
                                .fontDesign(.monospaced)
                                .foregroundColor(
                                    Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
                                )
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Industry_Production_List", comment: "生产清单"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
