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
    @Published private(set) var currentPage = 1
    @Published private(set) var totalPages = 1

    private var cachedData: [KillMailFilter: CachedKillMailData] = [:]
    private let characterId: Int
    private let databaseManager = DatabaseManager.shared
    let kbAPI = KbEvetoolAPI.shared
    private var currentIndex = 0
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

    private func saveToCache(_ data: [String: Any], for type: String, filter: KillMailFilter = .all)
    {
        let cacheKey = "\(type)_\(filter.rawValue)"
        let filePath = getCacheFilePath(for: cacheKey)
        var cacheData = data
        cacheData["update_time"] = Date().timeIntervalSince1970

        do {
            let jsonData = try JSONSerialization.data(
                withJSONObject: cacheData, options: .prettyPrinted)
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
        if cachedData[filter] == nil {
            await loadData(for: filter)
            return
        }

        if let cached = cachedData[filter] {
            await MainActor.run {
                killMails = cached.mails
                shipInfoMap = cached.shipInfo
                allianceIconMap = cached.allianceIcons
                corporationIconMap = cached.corporationIcons
            }
        }
    }

    private func loadData(for filter: KillMailFilter, forceRefresh: Bool = false) async {
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

        if !forceRefresh {
            await MainActor.run { isLoading = true }
        }

        do {
            let response: [String: Any]

            // 如果不是强制刷新，尝试从缓存加载
            if !forceRefresh, let cachedData = loadFromCache(for: "km", filter: filter) {
                response = cachedData
            } else {
                // 从API加载
                switch filter {
                case .all:
                    response = try await kbAPI.fetchCharacterKillMails(characterId: characterId)
                case .kill:
                    response = try await kbAPI.fetchCharacterKillMails(
                        characterId: characterId, filter: .kill
                    )
                case .loss:
                    response = try await kbAPI.fetchCharacterKillMails(
                        characterId: characterId, filter: .loss
                    )
                }

                // 保存到缓存
                saveToCache(response, for: "km", filter: filter)
            }

            guard let mails = response["data"] as? [[String: Any]] else {
                throw NSError(
                    domain: "BRKillMailView", code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString(
                            "KillMail_Invalid_Response_Format", comment: ""
                        )
                    ]
                )
            }

            let entries = convertToEntries(mails)
            let shipIds = mails.compactMap { kbAPI.getShipInfo($0, path: "vict", "ship").id }
            let shipInfo = getShipInfo(for: shipIds)
            let (allianceIcons, corporationIcons) = await loadOrganizationIcons(for: mails)

            let cachedData = CachedKillMailData(
                mails: entries,
                shipInfo: shipInfo,
                allianceIcons: allianceIcons,
                corporationIcons: corporationIcons
            )

            await MainActor.run {
                self.cachedData[filter] = cachedData
                self.killMails = entries
                self.shipInfoMap = shipInfo
                self.allianceIconMap = allianceIcons
                self.corporationIconMap = corporationIcons
                self.currentPage = 1
                if let total = response["totalPages"] as? Int {
                    self.totalPages = total
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func refreshData(for filter: KillMailFilter) async {
        // 不要立即设置isLoading=true，这会导致UI显示加载状态并清空列表

        do {
            let response: [String: Any]

            // 从API加载
            switch filter {
            case .all:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId)
            case .kill:
                response = try await kbAPI.fetchCharacterKillMails(
                    characterId: characterId, filter: .kill
                )
            case .loss:
                response = try await kbAPI.fetchCharacterKillMails(
                    characterId: characterId, filter: .loss
                )
            }

            // 保存到缓存
            saveToCache(response, for: "km", filter: filter)

            guard let mails = response["data"] as? [[String: Any]] else {
                throw NSError(
                    domain: "BRKillMailView", code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: NSLocalizedString(
                            "KillMail_Invalid_Response_Format", comment: ""
                        )
                    ]
                )
            }

            let entries = convertToEntries(mails)
            let shipIds = mails.compactMap { kbAPI.getShipInfo($0, path: "vict", "ship").id }
            let shipInfo = getShipInfo(for: shipIds)
            let (allianceIcons, corporationIcons) = await loadOrganizationIcons(for: mails)

            let cachedData = CachedKillMailData(
                mails: entries,
                shipInfo: shipInfo,
                allianceIcons: allianceIcons,
                corporationIcons: corporationIcons
            )

            await MainActor.run {
                self.cachedData[filter] = cachedData
                self.killMails = entries
                self.shipInfoMap = shipInfo
                self.allianceIconMap = allianceIcons
                self.corporationIconMap = corporationIcons
                self.currentPage = 1
                if let total = response["totalPages"] as? Int {
                    self.totalPages = total
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
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
                    corporationId: id, size: 64)
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
        if !forceRefresh && characterStats != nil {
            return
        }

        if !forceRefresh {
            await MainActor.run { isLoading = true }
        }

        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh, let cachedData = loadFromCache(for: "stats"),
            let stats = try? JSONDecoder().decode(
                CharBattleIsk.self, from: try JSONSerialization.data(withJSONObject: cachedData))
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
        guard !isLoadingMore && currentPage < totalPages else { return }

        await MainActor.run { isLoadingMore = true }

        do {
            let nextPage = currentPage + 1
            let response: [String: Any]

            // 根据filter类型调用不同的API
            switch filter {
            case .all:
                response = try await kbAPI.fetchCharacterKillMails(
                    characterId: characterId, page: nextPage
                )
            case .kill:
                response = try await kbAPI.fetchCharacterKillMails(
                    characterId: characterId, page: nextPage, filter: .kill
                )
            case .loss:
                response = try await kbAPI.fetchCharacterKillMails(
                    characterId: characterId, page: nextPage, filter: .loss
                )
            }

            guard let mails = response["data"] as? [[String: Any]] else {
                throw NSError(
                    domain: "BRKillMailView", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "无效的响应数据格式"]
                )
            }

            let entries = convertToEntries(mails)
            let shipIds = mails.compactMap { kbAPI.getShipInfo($0, path: "vict", "ship").id }
            let newShipInfo = getShipInfo(for: shipIds)
            let (newAllianceIcons, newCorporationIcons) = await loadOrganizationIcons(for: mails)

            await MainActor.run {
                killMails.append(contentsOf: entries)
                shipInfoMap.merge(newShipInfo) { current, _ in current }
                allianceIconMap.merge(newAllianceIcons) { current, _ in current }
                corporationIconMap.merge(newCorporationIcons) { current, _ in current }
                currentPage = nextPage
                if let total = response["totalPages"] as? Int {
                    totalPages = total
                }
                isLoadingMore = false
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
    @State private var hasInitialized = false  // 跟踪是否已执行初始加载

    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: KillMailViewModel(characterId: characterId))
    }

    // 执行初始数据加载，但只在第一次调用时执行
    private func loadInitialDataIfNeeded() {
        guard !hasInitialized && !isLoading else { return }

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
                                        ), shipId),
                                    iconFileName: DatabaseConfig.defaultItemIcon
                                ),
                                allianceIcon: allyId.flatMap { viewModel.allianceIconMap[$0] },
                                corporationIcon: corpId.flatMap {
                                    viewModel.corporationIconMap[$0]
                                },
                                characterId: characterId,
                                searchResult: nil
                            )
                        }
                    }

                    // 加载更多按钮
                    if viewModel.totalPages > 1 {
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
            // 依次刷新战斗统计和战斗记录
            await viewModel.refreshStats()
            await viewModel.refreshData(for: selectedFilter)
        }
        .onAppear {
            loadInitialDataIfNeeded()
        }
    }
}

struct BRKillMailCell: View {
    let killmail: [String: Any]
    let kbAPI: KbEvetoolAPI
    let shipInfo: (name: String, iconFileName: String)
    let allianceIcon: UIImage?
    let corporationIcon: UIImage?
    let characterId: Int
    let searchResult: SearchResult?

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
        let charInfo = victInfo?["char"]  // 先获取原始值，不做类型转换
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
        NavigationLink(destination: BRKillMailDetailView(killmail: killmail)) {
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
