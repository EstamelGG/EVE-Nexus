import SwiftUI

enum KillMailFilter: String {
    case all
    case kill
    case loss

    var title: String {
        switch self {
        case .all: return NSLocalizedString("KillMail_All_Records", comment: "")
        case .kill: return NSLocalizedString("KillMail_Kill_Records", comment: "")
        case .loss: return NSLocalizedString("KillMail_Loss_Records", comment: "")
        }
    }
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

    struct CachedKillMailData {
        let mails: [KillMailEntry]
        let shipInfo: [Int: (name: String, iconFileName: String)]
        let allianceIcons: [Int: UIImage]
        let corporationIcons: [Int: UIImage]
    }

    init(characterId: Int) {
        self.characterId = characterId
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

    private func loadData(for filter: KillMailFilter) async {
        guard characterId > 0 else {
            errorMessage = String(
                format: NSLocalizedString("KillMail_Invalid_Character_ID", comment: ""), characterId
            )
            return
        }

        // 设置加载状态
        await MainActor.run { isLoading = true }

        do {
            let response: [String: Any]
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
                // 始终重置isLoading，因为loadData是最后一个完成的操作
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
        cachedData.removeValue(forKey: filter)
        await loadData(for: filter)
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
                        let icon = await loadOrganizationIcon(type: "alliance", id: allyId)
                    {
                        allianceIcons[allyId] = icon
                    }
                } else if let corpInfo = victInfo["corp"] as? [String: Any],
                    let corpId = corpInfo["id"] as? Int,
                    corpId > 0
                {
                    // 只有在没有有效联盟ID的情况下才加载军团图标
                    if corporationIcons[corpId] == nil,
                        let icon = await loadOrganizationIcon(type: "corporation", id: corpId)
                    {
                        corporationIcons[corpId] = icon
                    }
                }
            }
        }

        return (allianceIcons, corporationIcons)
    }

    private func loadOrganizationIcon(type: String, id: Int) async -> UIImage? {
        do {
            switch type {
            case "alliance":
                return try await AllianceAPI.shared.fetchAllianceLogo(allianceID: id, size: 64)
            case "corporation":
                return try await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: id, size: 64
                )
            case "character":
                // 暂时保持原有的获取方式，直到我们实现CharacterAPI
                let urlString = "https://images.evetech.net/characters/\(id)/portrait?size=64"
                guard let url = URL(string: urlString) else { return nil }
                let data = try await NetworkManager.shared.fetchData(from: url)
                return UIImage(data: data)
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

    func loadStats() async {
        // 如果已经加载过数据，则直接返回
        if characterStats != nil {
            return
        }

        // 设置加载状态
        await MainActor.run { isLoading = true }

        do {
            let stats = try await ZKillMailsAPI.shared.fetchCharacterStats(characterId: characterId)
            await MainActor.run {
                self.characterStats = stats
                // 只有在没有加载killMails时才重置isLoading
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
            // 出错时也需要重置isLoading
            await MainActor.run {
                if self.killMails.isEmpty {
                    self.isLoading = false
                }
            }
        }
    }

    func loadMoreData() async {
        guard !isLoadingMore && currentPage < totalPages else { return }

        await MainActor.run { isLoadingMore = true }

        do {
            let nextPage = currentPage + 1
            let response = try await kbAPI.fetchCharacterKillMails(
                characterId: characterId, page: nextPage
            )

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
}

struct BRKillMailView: View {
    let characterId: Int
    @StateObject private var viewModel: KillMailViewModel
    @State private var selectedFilter: KillMailFilter = .all
    @State private var isLoading = false

    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: KillMailViewModel(characterId: characterId))
    }

    private func formatISK(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.2fT ISK", value / 1_000_000_000_000)
        } else if value >= 1_000_000_000 {
            return String(format: "%.2fB ISK", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM ISK", value / 1_000_000)
        } else if value >= 1000 {
            return String(format: "%.2fK ISK", value / 1000)
        } else {
            return String(format: "%.2f ISK", value)
        }
    }

    private func loadData() {
        guard !isLoading else { return }

        isLoading = true
        Task {
            // 创建一个任务组，同时加载战斗统计信息和战斗记录
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await viewModel.loadStats()
                }

                group.addTask {
                    await viewModel.loadDataIfNeeded(for: selectedFilter)
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
                        Text(formatISK(stats.iskDestroyed))
                            .foregroundColor(.green)
                            .font(.system(.body, design: .monospaced))
                    }

                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.red)
                        Text(NSLocalizedString("KillMail_Lost_Value", comment: ""))
                        Spacer()
                        Text(formatISK(stats.iskLost))
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
                                    name: NSLocalizedString("KillMail_Unknown_Item", comment: ""),
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
                                        await viewModel.loadMoreData()
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
            await viewModel.loadStats()
            await viewModel.refreshData(for: selectedFilter)
        }
        .onAppear {
            loadData()
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

        let systemName = Text(" \(sysInfo.name ?? "Unknown")")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.secondary)

        let regionText = Text(" / \(sysInfo.region ?? "Unknown")")
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

        return "Unknown"
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
