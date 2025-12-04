import SwiftUI

enum KillMailFilter: String {
    case all
    case kill
    case loss
}

struct KillMailEntry: Identifiable {
    let id: Int
    let data: [String: Any]
}

class KillMailViewModel: ObservableObject {
    @Published private(set) var killMails: [KillMailEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shipInfoMap: [Int: (name: String, iconFileName: String)] = [:]
    @Published private(set) var allianceIconMap: [Int: UIImage] = [:]
    @Published private(set) var corporationIconMap: [Int: UIImage] = [:]
    @Published private(set) var characterStats: CharBattleIsk?
    @Published private(set) var hasMoreData = true // 是否还有更多数据可加载

    private var cachedData: [KillMailFilter: CachedKillMailData] = [:]
    private let characterId: Int
    private let databaseManager = DatabaseManager.shared
    let kbAPI = zKbToolAPI.shared
    private var currentIndex = 0

    // 为每个 filter 维护分页状态
    private struct FilterPaginationState {
        var currentZKBPage: Int = 1 // 当前 zkillboard API 页码
        var pendingZKBEntries: [ZKBKillMailEntry] = [] // 待转换的原始数据
        var convertedKillmailIds: Set<Int> = [] // 已转换的 killmail ID（用于去重）
        var hasMore: Bool = true // 是否还有更多数据
    }

    private var paginationState: [KillMailFilter: FilterPaginationState] = [
        .all: FilterPaginationState(),
        .kill: FilterPaginationState(),
        .loss: FilterPaginationState(),
    ]
    private let fileManager = FileManager.default
    private var cacheDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let kbDirectory = documentsPath.appendingPathComponent("kb")
        try? fileManager.createDirectory(at: kbDirectory, withIntermediateDirectories: true)
        return kbDirectory
    }

    struct CachedKillMailData {
        let mails: [KillMailEntry]
        let shipInfo: [Int: (name: String, iconFileName: String)]
        let allianceIcons: [Int: UIImage]
        let corporationIcons: [Int: UIImage]
    }

    init(characterId: Int) {
        self.characterId = characterId
    }

    private func getCacheFilePath(for type: String) -> URL {
        return cacheDirectory.appendingPathComponent("\(type)_\(characterId).json")
    }

    private func saveToCache(_ data: [String: Any], for type: String, filter: KillMailFilter = .all) {
        let cacheKey = "\(type)_\(filter.rawValue)"
        let filePath = getCacheFilePath(for: cacheKey)
        var cacheData = data
        cacheData["update_time"] = Date().timeIntervalSince1970

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: cacheData, options: .prettyPrinted
            )
            try jsonData.write(to: filePath)
            Logger.info("保存到缓存文件: \(filePath)")
        } catch {
            Logger.error("保存缓存失败: \(error)")
        }
    }

    private func loadFromCache(for type: String, filter: KillMailFilter = .all) -> [String: Any]? {
        let cacheKey = "\(type)_\(filter.rawValue)"
        let filePath = getCacheFilePath(for: cacheKey)

        guard let data = try? Data(contentsOf: filePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updateTime = dict["update_time"] as? TimeInterval
        else {
            return nil
        }

        // 检查缓存是否过期（1小时）
        let cacheAge = Date().timeIntervalSince1970 - updateTime
        if cacheAge > 3600 {
            try? fileManager.removeItem(at: filePath)
            return nil
        }
        Logger.info("从缓存加载文件: \(filePath)")
        return dict
    }

    private func convertToEntries(_ mails: [[String: Any]]) -> [KillMailEntry] {
        return mails.map { mail in
            defer { currentIndex += 1 }
            return KillMailEntry(id: currentIndex, data: mail)
        }
    }

    func loadDataIfNeeded(for filter: KillMailFilter) async {
        // 切换过滤器时，先检查内存缓存，如果有就直接使用，避免重新加载
        let hasCached = await MainActor.run {
            if let cached = self.cachedData[filter] {
                // 直接从内存缓存读取，不需要重新加载
                self.killMails = cached.mails
                self.shipInfoMap = cached.shipInfo
                self.allianceIconMap = cached.allianceIcons
                self.corporationIconMap = cached.corporationIcons
                self.hasMoreData = true
                return true
            }
            return false
        }

        // 如果有内存缓存，直接返回，不需要加载
        if hasCached {
            return
        }

        // 如果没有内存缓存，重置分页状态并加载数据
        await MainActor.run {
            self.paginationState[filter] = FilterPaginationState()
            self.killMails = []
            self.hasMoreData = true
        }

        await loadData(for: filter)
    }

    private func loadData(for filter: KillMailFilter, forceRefresh: Bool = false, updateUI: Bool = true) async {
        guard characterId > 0 else {
            await MainActor.run {
                errorMessage = String(
                    format: NSLocalizedString("KillMail_Invalid_Character_ID", comment: ""),
                    characterId
                )
                isLoading = false
            }
            return
        }

        // 如果不是强制刷新，先尝试从缓存文件加载
        if !forceRefresh {
            if let cachedDict = loadFromCache(for: "km", filter: filter),
               let data = cachedDict["data"] as? [[String: Any]]
            {
                // 从缓存文件加载数据
                let entries = convertToEntries(data)
                let shipIds = data.compactMap { kbAPI.getShipInfo($0, path: "vict", "ship").id }
                let shipInfo = getShipInfo(for: shipIds)
                let (allianceIcons, corporationIcons) = await loadOrganizationIcons(for: data)

                let cachedKillMailData = CachedKillMailData(
                    mails: entries,
                    shipInfo: shipInfo,
                    allianceIcons: allianceIcons,
                    corporationIcons: corporationIcons
                )

                await MainActor.run {
                    self.cachedData[filter] = cachedKillMailData
                    if updateUI {
                        self.killMails = entries
                    }
                    self.shipInfoMap.merge(shipInfo) { current, _ in current }
                    self.allianceIconMap.merge(allianceIcons) { current, _ in current }
                    self.corporationIconMap.merge(corporationIcons) { current, _ in current }
                    self.hasMoreData = true
                    if updateUI {
                        self.isLoading = false
                    }
                }

                Logger.debug("从缓存文件加载数据成功 - filter: \(filter)")
                return
            }
        }

        if !forceRefresh {
            await MainActor.run { isLoading = true }
        }

        do {
            // 获取分页状态（在主线程上）
            // 如果是强制刷新，状态已经在 refreshData 中重置了
            var state = await MainActor.run {
                if let existing = self.paginationState[filter] {
                    return existing
                } else {
                    let newState = FilterPaginationState()
                    self.paginationState[filter] = newState
                    return newState
                }
            }

            // 强制刷新时，或者待转换数据为空时，从 zkillboard API 获取第一页
            if forceRefresh || state.pendingZKBEntries.isEmpty {
                Logger.debug("从 zkillboard 获取第一页数据 - filter: \(filter), forceRefresh: \(forceRefresh)")
                // 强制刷新时，从第一页开始获取
                let pageToFetch = forceRefresh ? 1 : state.currentZKBPage
                let zkbEntries = try await kbAPI.fetchZKBCharacterKillMails(
                    characterId: characterId,
                    page: pageToFetch,
                    filter: filter
                )

                if zkbEntries.isEmpty {
                    // 没有数据了
                    state.hasMore = false
                    // 复制 state 以避免并发访问问题
                    let finalState = state
                    await MainActor.run {
                        self.killMails = []
                        self.hasMoreData = false
                        self.isLoading = false
                        // 在主线程上更新 paginationState
                        self.paginationState[filter] = finalState
                    }
                    return
                }

                state.pendingZKBEntries = zkbEntries
                // 强制刷新时，从第1页开始，所以下一页是第2页；否则继续递增
                state.currentZKBPage = forceRefresh ? 2 : (state.currentZKBPage + 1)
            }

            // 只转换前10个（去重）
            let batchSize = 10
            var entriesToConvert: [ZKBKillMailEntry] = []
            var remainingEntries: [ZKBKillMailEntry] = []

            for entry in state.pendingZKBEntries {
                if entriesToConvert.count < batchSize, !state.convertedKillmailIds.contains(entry.killmail_id) {
                    entriesToConvert.append(entry)
                    state.convertedKillmailIds.insert(entry.killmail_id)
                } else {
                    remainingEntries.append(entry)
                }
            }

            state.pendingZKBEntries = remainingEntries

            // 如果转换的数据不足10个，且还有更多页，尝试加载下一页
            if entriesToConvert.count < batchSize, state.hasMore {
                Logger.debug("当前页数据不足10个，尝试加载下一页")
                let nextPageEntries = try await kbAPI.fetchZKBCharacterKillMails(
                    characterId: characterId,
                    page: state.currentZKBPage,
                    filter: filter
                )

                if nextPageEntries.isEmpty {
                    state.hasMore = false
                } else {
                    state.pendingZKBEntries.append(contentsOf: nextPageEntries)
                    state.currentZKBPage += 1

                    // 从新加载的数据中补齐到10个
                    for entry in state.pendingZKBEntries {
                        if entriesToConvert.count >= batchSize {
                            break
                        }
                        if !state.convertedKillmailIds.contains(entry.killmail_id) {
                            entriesToConvert.append(entry)
                            state.convertedKillmailIds.insert(entry.killmail_id)
                        }
                    }

                    // 更新剩余数据
                    state.pendingZKBEntries = state.pendingZKBEntries.filter { entry in
                        !state.convertedKillmailIds.contains(entry.killmail_id) || entriesToConvert.contains(where: { $0.killmail_id == entry.killmail_id })
                    }
                }
            }

            // 如果最终转换的数据仍不足10个，说明没有更多数据了
            if entriesToConvert.count < batchSize {
                state.hasMore = false
            }

            // 使用转换器转换数据
            let convertedMails = try await KillMailDataConverter.shared.convertZKBListToEvetoolsFormat(
                zkbEntries: entriesToConvert
            )

            let entries = convertToEntries(convertedMails)
            let shipIds = convertedMails.compactMap { kbAPI.getShipInfo($0, path: "vict", "ship").id }
            let shipInfo = getShipInfo(for: shipIds)
            let (allianceIcons, corporationIcons) = await loadOrganizationIcons(for: convertedMails)

            let cachedData = CachedKillMailData(
                mails: entries,
                shipInfo: shipInfo,
                allianceIcons: allianceIcons,
                corporationIcons: corporationIcons
            )

            // 在 MainActor 闭包外获取需要的值
            let hasMore = state.hasMore
            // 复制 state 以避免并发访问问题
            let finalState = state

            await MainActor.run {
                self.cachedData[filter] = cachedData
                if updateUI {
                    self.killMails = entries
                }
                self.shipInfoMap.merge(shipInfo) { current, _ in current }
                self.allianceIconMap.merge(allianceIcons) { current, _ in current }
                self.corporationIconMap.merge(corporationIcons) { current, _ in current }
                self.hasMoreData = hasMore
                if updateUI {
                    self.isLoading = false
                }
                // 在主线程上更新 paginationState
                self.paginationState[filter] = finalState
            }

            // 保存到缓存文件
            let cacheDict: [String: Any] = [
                "data": convertedMails,
                "update_time": Date().timeIntervalSince1970,
            ]
            saveToCache(cacheDict, for: "km", filter: filter)
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func refreshData(for filter: KillMailFilter, updateUI: Bool = true) async {
        // 强制刷新：重置分页状态，清空列表，就像重新进入页面一样
        await MainActor.run {
            self.paginationState[filter] = FilterPaginationState()
            if updateUI {
                self.killMails = []
            }
            self.hasMoreData = true
        }

        // 重新加载数据（不使用缓存，强制从 zkillboard API 获取）
        await loadData(for: filter, forceRefresh: true, updateUI: updateUI)
    }

    private func loadOrganizationIcons(for mails: [[String: Any]]) async -> (
        [Int: UIImage], [Int: UIImage]
    ) {
        var allianceIcons: [Int: UIImage] = [:]
        var corporationIcons: [Int: UIImage] = [:]

        for mail in mails {
            if let victInfo = mail["vict"] as? [String: Any] {
                // 优先检查联盟ID
                if let allyInfo = victInfo["ally"] as? [String: Any],
                   let allyId = allyInfo["id"] as? Int,
                   allyId > 0
                {
                    // 只有当联盟ID有效且图标未加载时才加载联盟图标
                    if allianceIcons[allyId] == nil,
                       let icon = await loadSingleOrganizationIcon(type: "alliance", id: allyId)
                    {
                        allianceIcons[allyId] = icon
                    }
                } else if let corpInfo = victInfo["corp"] as? [String: Any],
                          let corpId = corpInfo["id"] as? Int,
                          corpId > 0
                {
                    // 只有在没有有效联盟ID的情况下才加载军团图标
                    if corporationIcons[corpId] == nil,
                       let icon = await loadSingleOrganizationIcon(type: "corporation", id: corpId)
                    {
                        corporationIcons[corpId] = icon
                    }
                }
            }
        }

        return (allianceIcons, corporationIcons)
    }

    private func loadSingleOrganizationIcon(type: String, id: Int) async -> UIImage? {
        do {
            switch type {
            case "alliance":
                return try await AllianceAPI.shared.fetchAllianceLogo(allianceID: id, size: 64)
            case "corporation":
                return try await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: id, size: 64
                )
            default:
                return nil
            }
        } catch {
            Logger.error("加载\(type)图标失败 - ID: \(id), 错误: \(error)")
            return nil
        }
    }

    private func getShipInfo(for typeIds: [Int]) -> [Int: (name: String, iconFileName: String)] {
        guard !typeIds.isEmpty else { return [:] }

        let placeholders = String(repeating: "?,", count: typeIds.count).dropLast()
        let query = """
            SELECT type_id, name, icon_filename 
            FROM types 
            WHERE type_id IN (\(placeholders))
        """

        let result = databaseManager.executeQuery(query, parameters: typeIds)
        var infoMap: [Int: (name: String, iconFileName: String)] = [:]

        if case let .success(rows) = result {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String
                {
                    infoMap[typeId] = (name: name, iconFileName: iconFileName)
                }
            }
        }

        return infoMap
    }

    func loadStats(forceRefresh: Bool = false) async {
        if !forceRefresh, characterStats != nil {
            return
        }

        if !forceRefresh {
            await MainActor.run { isLoading = true }
        }

        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh, let cachedData = loadFromCache(for: "stats"),
           let stats = try? JSONDecoder().decode(
               CharBattleIsk.self, from: try JSONSerialization.data(withJSONObject: cachedData)
           )
        {
            await MainActor.run {
                self.characterStats = stats
                if self.killMails.isEmpty {
                    self.isLoading = false
                }
            }
            return
        }

        do {
            let stats = try await ZKillMailsAPI.shared.fetchCharacterStats(characterId: characterId)
            // 保存到缓存
            if let jsonData = try? JSONEncoder().encode(stats),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            {
                saveToCache(dict, for: "stats")
            }

            await MainActor.run {
                self.characterStats = stats
                if self.killMails.isEmpty {
                    self.isLoading = false
                }
            }
        } catch {
            Logger.error(
                String(
                    format: NSLocalizedString("KillMail_Stats_Failed", comment: ""),
                    error.localizedDescription
                ))
            await MainActor.run {
                if self.killMails.isEmpty {
                    self.isLoading = false
                }
            }
        }
    }

    func loadMoreData(for filter: KillMailFilter = .all) async {
        guard !isLoadingMore, hasMoreData else { return }

        await MainActor.run { isLoadingMore = true }

        do {
            // 在主线程上获取状态
            var state = await MainActor.run {
                self.paginationState[filter] ?? FilterPaginationState()
            }
            let batchSize = 10

            // 从待转换数据中取10个（去重）
            var entriesToConvert: [ZKBKillMailEntry] = []
            var remainingEntries: [ZKBKillMailEntry] = []

            for entry in state.pendingZKBEntries {
                if entriesToConvert.count < batchSize, !state.convertedKillmailIds.contains(entry.killmail_id) {
                    entriesToConvert.append(entry)
                    state.convertedKillmailIds.insert(entry.killmail_id)
                } else {
                    remainingEntries.append(entry)
                }
            }

            state.pendingZKBEntries = remainingEntries

            // 如果不足10个，尝试加载下一页
            if entriesToConvert.count < batchSize, state.hasMore {
                Logger.debug("加载更多：当前页数据不足10个，尝试加载下一页 - page: \(state.currentZKBPage)")
                let nextPageEntries = try await kbAPI.fetchZKBCharacterKillMails(
                    characterId: characterId,
                    page: state.currentZKBPage,
                    filter: filter
                )

                if nextPageEntries.isEmpty {
                    state.hasMore = false
                } else {
                    state.pendingZKBEntries.append(contentsOf: nextPageEntries)
                    state.currentZKBPage += 1

                    // 从新加载的数据中补齐到10个
                    var tempRemaining: [ZKBKillMailEntry] = []
                    for entry in state.pendingZKBEntries {
                        if entriesToConvert.count >= batchSize {
                            tempRemaining.append(entry)
                        } else if !state.convertedKillmailIds.contains(entry.killmail_id) {
                            entriesToConvert.append(entry)
                            state.convertedKillmailIds.insert(entry.killmail_id)
                        } else {
                            tempRemaining.append(entry)
                        }
                    }
                    state.pendingZKBEntries = tempRemaining
                }
            }

            // 如果最终转换的数据仍不足10个，说明没有更多数据了
            if entriesToConvert.count < batchSize {
                state.hasMore = false
            }

            // 使用转换器转换数据
            let convertedMails = try await KillMailDataConverter.shared.convertZKBListToEvetoolsFormat(
                zkbEntries: entriesToConvert
            )

            let entries = convertToEntries(convertedMails)
            let shipIds = convertedMails.compactMap { kbAPI.getShipInfo($0, path: "vict", "ship").id }
            let newShipInfo = getShipInfo(for: shipIds)
            let (newAllianceIcons, newCorporationIcons) = await loadOrganizationIcons(for: convertedMails)

            // 在 MainActor 闭包外获取需要的值
            let hasMore = state.hasMore
            // 复制 state 以避免并发访问问题
            let finalState = state

            await MainActor.run {
                killMails.append(contentsOf: entries)
                shipInfoMap.merge(newShipInfo) { current, _ in current }
                allianceIconMap.merge(newAllianceIcons) { current, _ in current }
                corporationIconMap.merge(newCorporationIcons) { current, _ in current }
                hasMoreData = hasMore
                isLoadingMore = false
                // 在主线程上更新 paginationState
                self.paginationState[filter] = finalState
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoadingMore = false
            }
        }
    }

    // 预加载所有过滤器的数据
    func preloadAllFilterData() async {
        await MainActor.run { isLoading = true }

        // 使用任务组并行加载所有过滤器数据
        await withTaskGroup(of: Void.self) { group in
            for filter in [KillMailFilter.all, KillMailFilter.kill, KillMailFilter.loss] {
                if cachedData[filter] == nil {
                    group.addTask {
                        await self.loadData(for: filter)
                    }
                }
            }
        }

        // 加载完成后，如果当前选择的过滤器有缓存数据，就显示它
        if let cached = cachedData[.all] {
            await MainActor.run {
                killMails = cached.mails
                shipInfoMap = cached.shipInfo
                allianceIconMap = cached.allianceIcons
                corporationIconMap = cached.corporationIcons
                isLoading = false
            }
        }
    }

    func refreshStats() async {
        // 不要立即设置isLoading=true，保持现有UI状态

        do {
            let stats = try await ZKillMailsAPI.shared.fetchCharacterStats(characterId: characterId)
            // 保存到缓存
            if let jsonData = try? JSONEncoder().encode(stats),
               let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            {
                saveToCache(dict, for: "stats")
            }

            await MainActor.run {
                self.characterStats = stats
            }
        } catch {
            Logger.error(
                String(
                    format: NSLocalizedString("KillMail_Stats_Failed", comment: ""),
                    error.localizedDescription
                ))
        }
    }
}

struct BRKillMailView: View {
    let characterId: Int
    @StateObject private var viewModel: KillMailViewModel
    @State private var selectedFilter: KillMailFilter = .all
    @State private var isLoading = false
    @State private var hasInitialized = false // 跟踪是否已执行初始加载

    // 获取当前角色信息
    private var character: EVECharacterInfo? {
        EVELogin.shared.getCharacterByID(characterId)?.character
    }

    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: KillMailViewModel(characterId: characterId))
    }

    // 执行初始数据加载，但只在第一次调用时执行
    private func loadInitialDataIfNeeded() {
        guard !hasInitialized, !isLoading else { return }

        hasInitialized = true
        isLoading = true

        Task {
            // 创建一个任务组，同时加载战斗统计信息和所有过滤器的战斗记录
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await viewModel.loadStats()
                }

                group.addTask {
                    await viewModel.preloadAllFilterData()
                }
            }

            // 所有任务完成后重置isLoading
            isLoading = false
        }
    }

    var body: some View {
        List {
            // 战斗统计信息
            Section {
                if let stats = viewModel.characterStats {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("KillMail_Destroyed_Value", comment: ""))
                        Spacer()
                        Text(FormatUtil.formatISK(stats.iskDestroyed))
                            .foregroundColor(.green)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.red)
                        Text(NSLocalizedString("KillMail_Lost_Value", comment: ""))
                        Spacer()
                        Text(FormatUtil.formatISK(stats.iskLost))
                            .foregroundColor(.red)
                            .font(.system(.body, design: .monospaced))
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            // 搜索入口
            Section {
                NavigationLink(destination: BRKillMailSearchView(characterId: characterId)) {
                    Text(NSLocalizedString("KillMail_Search_Title", comment: ""))
                }
            }

            // 战斗记录列表
            Section(header: Text(NSLocalizedString("KillMail_Battle_Records", comment: ""))) {
                Picker(
                    NSLocalizedString("KillMail_Filter", comment: ""), selection: $selectedFilter
                ) {
                    Text(NSLocalizedString("KillMail_Filter_All", comment: "")).tag(
                        KillMailFilter.all)
                    Text(NSLocalizedString("KillMail_Filter_Kills", comment: "")).tag(
                        KillMailFilter.kill)
                    Text(NSLocalizedString("KillMail_Filter_Losses", comment: "")).tag(
                        KillMailFilter.loss)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 2)
                .onChange(of: selectedFilter) { _, newValue in
                    Task {
                        await viewModel.loadDataIfNeeded(for: newValue)
                    }
                }

                if isLoading || viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else if viewModel.killMails.isEmpty {
                    Text(NSLocalizedString("KillMail_No_Records", comment: ""))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.killMails) { entry in
                        if let shipId = viewModel.kbAPI.getShipInfo(
                            entry.data, path: "vict", "ship"
                        ).id {
                            let victInfo = entry.data["vict"] as? [String: Any]
                            let allyInfo = victInfo?["ally"] as? [String: Any]
                            let corpInfo = victInfo?["corp"] as? [String: Any]

                            let allyId = allyInfo?["id"] as? Int
                            let corpId = corpInfo?["id"] as? Int

                            BRKillMailCell(
                                killmail: entry.data,
                                kbAPI: viewModel.kbAPI,
                                shipInfo: viewModel.shipInfoMap[shipId] ?? (
                                    name: String(
                                        format: NSLocalizedString(
                                            "KillMail_Unknown_Item", comment: ""
                                        ), shipId
                                    ),
                                    iconFileName: DatabaseConfig.defaultItemIcon
                                ),
                                allianceIcon: allyId.flatMap { viewModel.allianceIconMap[$0] },
                                corporationIcon: corpId.flatMap {
                                    viewModel.corporationIconMap[$0]
                                },
                                characterId: characterId,
                                searchResult: nil,
                                character: character
                            )
                        }
                    }

                    // 加载更多按钮
                    if viewModel.hasMoreData {
                        HStack {
                            Spacer()
                            if viewModel.isLoadingMore {
                                ProgressView()
                            } else {
                                Button(action: {
                                    Task {
                                        await viewModel.loadMoreData(for: selectedFilter)
                                    }
                                }) {
                                    Text(NSLocalizedString("KillMail_Load_More", comment: ""))
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("KillMail_View_Title", comment: ""))
        .refreshable {
            // 刷新战斗统计和所有三个子页面的战斗记录
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await viewModel.refreshStats()
                }
                // 刷新当前选中的类别，并更新UI
                group.addTask {
                    await viewModel.refreshData(for: selectedFilter, updateUI: true)
                }
                // 并行刷新其他两个类别，只更新缓存，不更新UI
                for filter in [KillMailFilter.all, KillMailFilter.kill, KillMailFilter.loss] {
                    if filter != selectedFilter {
                        group.addTask {
                            await viewModel.refreshData(for: filter, updateUI: false)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadInitialDataIfNeeded()
        }
    }
}

struct BRKillMailCell: View {
    let killmail: [String: Any]
    let kbAPI: zKbToolAPI
    let shipInfo: (name: String, iconFileName: String)
    let allianceIcon: UIImage?
    let corporationIcon: UIImage?
    let characterId: Int
    let searchResult: SearchResult?
    let character: EVECharacterInfo? // 添加角色信息参数

    private var isLoss: Bool {
        guard let victInfo = killmail["vict"] as? [String: Any] else { return false }

        if let searchResult = searchResult {
            switch searchResult.category {
            case .character:
                if let charInfo = victInfo["char"] as? [String: Any],
                   let victimId = charInfo["id"] as? Int
                {
                    return victimId == searchResult.id
                }
            case .corporation:
                if let corpInfo = victInfo["corp"] as? [String: Any],
                   let corpId = corpInfo["id"] as? Int
                {
                    return corpId == searchResult.id
                }
            case .alliance:
                if let allyInfo = victInfo["ally"] as? [String: Any],
                   let allyId = allyInfo["id"] as? Int
                {
                    return allyId == searchResult.id
                }
            case .inventory_type:
                if let shipId = kbAPI.getShipInfo(killmail, path: "vict", "ship").id {
                    return shipId == searchResult.id
                }
            default:
                return false
            }
            return false
        } else {
            // 非搜索场景，使用原有逻辑
            if let charInfo = victInfo["char"] as? [String: Any],
               let victimId = charInfo["id"] as? Int
            {
                return victimId == characterId
            }
            return false
        }
    }

    private var valueColor: Color {
        isLoss ? .red : .green
    }

    private var organizationIcon: UIImage? {
        let victInfo = killmail["vict"] as? [String: Any]
        let allyInfo = victInfo?["ally"] as? [String: Any]
        let corpInfo = victInfo?["corp"] as? [String: Any]

        // 先尝试获取联盟图标
        if let allyId = allyInfo?["id"] as? Int, allyId > 0, let icon = allianceIcon {
            return icon
        }

        // 如果没有联盟图标，尝试获取军团图标
        if let corpId = corpInfo?["id"] as? Int, corpId > 0, let icon = corporationIcon {
            return icon
        }

        return nil
    }

    private var locationText: Text {
        let sysInfo = kbAPI.getSystemInfo(killmail)
        let securityText = Text(formatSystemSecurity(Double(sysInfo.security ?? "0.0") ?? 0.0))
            .foregroundColor(getSecurityColor(Double(sysInfo.security ?? "0.0") ?? 0.0))
            .font(.system(size: 12, weight: .medium))

        let systemName = Text(" \(sysInfo.name ?? NSLocalizedString("Unknown", comment: ""))")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)

        let regionText = Text(" / \(sysInfo.region ?? NSLocalizedString("Unknown", comment: ""))")
            .font(.system(size: 12))
            .foregroundColor(.secondary)

        return securityText + systemName + regionText
    }

    private var displayName: String {
        let victInfo = killmail["vict"] as? [String: Any]
        let charInfo = victInfo?["char"] // 先获取原始值，不做类型转换
        let allyInfo = victInfo?["ally"] as? [String: Any]
        let corpInfo = victInfo?["corp"] as? [String: Any]

        // 如果char是字典类型，说明有完整的角色信息
        if let charDict = charInfo as? [String: Any],
           let name = charDict["name"] as? String
        {
            return name
        }

        // 如果char是数字类型且为0，或者不存在，尝试使用联盟名
        if let allyName = allyInfo?["name"] as? String,
           let allyId = allyInfo?["id"] as? Int,
           allyId > 0
        {
            return allyName
        }

        // 如果联盟也没有，使用军团名
        if let corpName = corpInfo?["name"] as? String {
            return corpName
        }

        return NSLocalizedString("Unknown", comment: "")
    }

    var body: some View {
        NavigationLink(destination: BRKillMailDetailView(killmail: killmail, character: character)) {
            VStack(alignment: .leading, spacing: 8) {
                // 第一行：图标和信息
                HStack(spacing: 12) {
                    // 左侧飞船图标
                    IconManager.shared.loadImage(for: shipInfo.iconFileName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // 右侧信息
                    VStack(alignment: .leading, spacing: 2) {
                        // 飞船名称
                        Text(shipInfo.name)
                            .font(.system(size: 16, weight: .medium))

                        // 显示名称（角色/联盟/军团）
                        Text(displayName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)

                        // 位置信息
                        locationText
                    }

                    Spacer()

                    // 右侧组织图标
                    if let icon = organizationIcon {
                        Image(uiImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                    }
                }

                // 第二行：时间和价值
                HStack {
                    if let time = kbAPI.getFormattedTime(killmail) {
                        Text(time)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let value = kbAPI.getFormattedValue(killmail) {
                        Text(value)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(valueColor)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
