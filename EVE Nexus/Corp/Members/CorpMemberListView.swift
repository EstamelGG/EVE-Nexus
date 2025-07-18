import SwiftUI

// 移除HTML标签的扩展
extension String {
    fileprivate func removeHTMLTags() -> String {
        // 移除所有HTML标签
        let text = replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        // 将HTML实体转换为对应字符
        return text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Data Models

struct MemberDetailInfo: Identifiable {
    let member: MemberTrackingInfo
    var characterName: String
    var shipInfo: (name: String, iconFilename: String)?

    // 延迟加载的信息
    var characterInfo: CharacterPublicInfo?
    var portrait: UIImage?
    var isLoadingDetails = false
    var isPinned: Bool = false

    var id: Int { member.character_id }
}

// MARK: - Location Cache Info

struct LocationCacheInfo {
    let systemName: String
    let security: Double
    let stationName: String?

    static let unknown = LocationCacheInfo(
        systemName: NSLocalizedString("Unknown", comment: ""),
        security: 0.0,
        stationName: nil
    )
}

// MARK: - View Model

class CorpMemberListViewModel: ObservableObject {
    @Published var members: [MemberDetailInfo] = []
    @Published var isLoading = true
    @Published var error: Error? {
        didSet {
            if error != nil {
                showError = true
            }
        }
    }

    @Published var showError = false
    @Published var currentPage = 0
    @Published var totalPages = 0
    @Published var searchText: String = ""
    @AppStorage("MemberSortOption") private var sortOptionRaw: String = "name"

    var sortOption: MemberSortOption {
        get {
            MemberSortOption(rawValue: sortOptionRaw) ?? .name
        }
        set {
            sortOptionRaw = newValue.rawValue
            Task { @MainActor in
                sortMembers()
            }
        }
    }

    private let pageSize = 100
    var allMembers: [MemberDetailInfo] = []
    private let characterId: Int
    private let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    private var initialLoadDone = false

    // 位置信息缓存
    private var locationCache: [Int64: LocationCacheInfo] = [:]

    @Published var pinnedMembers: [MemberDetailInfo] = []

    enum MemberSortOption: String {
        case name
        case ship

        var localizedString: String {
            switch self {
            case .name:
                return NSLocalizedString("Main_Corporation_Members_Sort_By_Name", comment: "")
            case .ship:
                return NSLocalizedString("Main_Corporation_Members_Sort_By_Ship", comment: "")
            }
        }
    }

    // 特别关注成员ID集合
    private var pinnedMemberIds: Set<Int> {
        get {
            // 使用当前用户角色ID作为缓存key的一部分
            let cacheKey = "PinnedMembers_\(characterId)"

            if let data = UserDefaults.standard.data(forKey: cacheKey),
                let ids = try? JSONDecoder().decode(Set<Int>.self, from: data)
            {
                return ids
            }
            return []
        }
        set {
            let cacheKey = "PinnedMembers_\(characterId)"
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: cacheKey)
            }
        }
    }

    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }

    // 切换成员的置顶状态
    @MainActor
    func togglePinStatus(for memberId: Int) {
        Task {
            var ids = pinnedMemberIds
            let isPinning = !ids.contains(memberId)

            if isPinning {
                ids.insert(memberId)
            } else {
                ids.remove(memberId)
            }
            pinnedMemberIds = ids

            // 更新成员列表中的状态
            if let allMembersIndex = allMembers.firstIndex(where: { $0.id == memberId }) {
                allMembers[allMembersIndex].isPinned = isPinning

                // 同时更新当前页面显示的成员状态
                if let currentIndex = members.firstIndex(where: { $0.id == memberId }) {
                    members[currentIndex].isPinned = isPinning
                }

                // 更新收藏列表
                if isPinning {
                    // 添加到收藏列表
                    pinnedMembers.append(allMembers[allMembersIndex])
                } else {
                    // 从收藏列表中移除
                    pinnedMembers.removeAll { $0.id == memberId }
                }

                // 重新排序以确保UI更新
                sortMembers()
            }
        }
    }

    private var filteredMembers: [MemberDetailInfo] {
        if searchText.isEmpty {
            return allMembers
        }

        let searchQuery = searchText.lowercased()
        return allMembers.filter { member in
            // 搜索名称
            if member.characterName.lowercased().contains(searchQuery) {
                return true
            }
            // 搜索船名
            if let shipName = member.shipInfo?.name,
                shipName.lowercased().contains(searchQuery)
            {
                return true
            }
            return false
        }
    }

    @MainActor
    func updatePage() {
        let filtered = filteredMembers
        totalPages = max(1, (filtered.count + pageSize - 1) / pageSize)
        currentPage = min(currentPage, max(0, totalPages - 1))

        let start = currentPage * pageSize
        let end = min(start + pageSize, filtered.count)

        // 安全检查
        if start >= filtered.count {
            members = []
            return
        }

        members = Array(filtered[start..<end])
    }

    @MainActor
    func nextPage() {
        if currentPage < totalPages - 1 {
            currentPage += 1
            updatePage()
        }
    }

    @MainActor
    func previousPage() {
        if currentPage > 0 {
            currentPage -= 1
            updatePage()
        }
    }

    // MARK: - Location Methods

    /// 获取位置信息，优先从缓存获取
    @MainActor
    func getLocationInfo(locationId: Int64) async -> LocationCacheInfo {
        // 1. 检查缓存
        if let cached = locationCache[locationId] {
            Logger.debug("从缓存获取位置信息 - ID: \(locationId), 名称: \(cached.systemName)")
            return cached
        }

        Logger.debug("缓存未命中 - ID: \(locationId), 类型: \(LocationType.from(id: locationId))")

        // 2. 根据ID类型处理
        switch LocationType.from(id: locationId) {
        case .structure:
            // 对于建筑物，需要通过API获取
            return await loadStructureLocationInfo(locationId: locationId)
        default:
            // 其他类型如果缓存中没有，说明是未知位置
            Logger.error("位置信息未找到 - ID: \(locationId)")
            return LocationCacheInfo.unknown
        }
    }

    /// 初始化基础位置信息（星系和空间站）
    @MainActor
    private func initializeBasicLocationInfo(locationIds: Set<Int64>) async {
        Logger.debug("开始初始化位置信息 - 总数: \(locationIds.count)")

        // 按类型分组
        let groupedIds = Dictionary(grouping: locationIds) { LocationType.from(id: $0) }

        // 加载星系信息
        if let solarSystemIds = groupedIds[.solarSystem] {
            Logger.debug("加载星系信息 - 数量: \(solarSystemIds.count)")
            let query = """
                    SELECT u.solarsystem_id, u.system_security,
                           s.solarSystemName
                    FROM universe u
                    JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                    WHERE u.solarsystem_id IN (\(solarSystemIds.sorted().map { String($0) }.joined(separator: ",")))
                """

            if case let .success(rows) = databaseManager.executeQuery(query) {
                Logger.debug("查询到星系数量: \(rows.count)")
                for row in rows {
                    // Logger.debug("处理星系数据行: \(row)")
                    // 先获取原始值
                    let rawSystemId = row["solarsystem_id"]
                    let rawSystemNameLocal = row["solarSystemName"]
                    let rawSecurity = row["system_security"]

                    // Logger.debug("原始数据类型 - systemId: \(type(of: rawSystemId)), systemName: \(type(of: rawSystemNameLocal)), security: \(type(of: rawSecurity))")

                    // 尝试不同的类型转换
                    let systemId: Int64
                    if let id = rawSystemId as? Int64 {
                        systemId = id
                    } else if let id = rawSystemId as? Int {
                        systemId = Int64(id)
                    } else {
                        Logger.error("systemId 类型转换失败: \(String(describing: rawSystemId))")
                        continue
                    }

                    let systemNameLocal: String
                    if let name = rawSystemNameLocal as? String {
                        systemNameLocal = name
                    } else {
                        Logger.error(
                            "systemNameLocal 类型转换失败: \(String(describing: rawSystemNameLocal))")
                        continue
                    }

                    let security: Double
                    if let sec = rawSecurity as? Double {
                        security = sec
                    } else if let sec = rawSecurity as? String {
                        security = Double(sec) ?? 0.0
                    } else {
                        Logger.error("security 类型转换失败: \(String(describing: rawSecurity))")
                        continue
                    }

                    let systemName = systemNameLocal

                    let info = LocationCacheInfo(
                        systemName: systemName,
                        security: security,
                        stationName: nil
                    )
                    locationCache[systemId] = info
                    // Logger.debug("成功缓存星系信息 - ID: \(systemId), 名称: \(systemName), 安全等级: \(security)")
                }
            } else {
                Logger.error("星系查询失败 - SQL: \(query)")
            }
        }

        // 加载空间站信息
        if let stationIds = groupedIds[.station] {
            Logger.debug("加载空间站信息 - 数量: \(stationIds.count)")
            let query = """
                    SELECT s.stationID, s.stationName,
                           ss.solarSystemName, u.system_security
                    FROM stations s
                    JOIN solarsystems ss ON s.solarSystemID = ss.solarSystemID
                    JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                    WHERE s.stationID IN (\(stationIds.map { String($0) }.joined(separator: ",")))
                """

            if case let .success(rows) = databaseManager.executeQuery(query) {
                Logger.debug("查询到空间站数量: \(rows.count)")
                for row in rows {
                    // Logger.debug("处理空间站数据行: \(row)")
                    // 先获取原始值
                    let rawStationId = row["stationID"]
                    let stationName =
                        row["stationName"] as? String ?? NSLocalizedString("Unknown", comment: "")
                    let rawSystemNameLocal = row["solarSystemName"]
                    let rawSecurity = row["system_security"]

                    // 尝试不同的类型转换
                    let stationId: Int64
                    if let id = rawStationId as? Int64 {
                        stationId = id
                    } else if let id = rawStationId as? Int {
                        stationId = Int64(id)
                    } else {
                        Logger.error("stationID 类型转换失败: \(String(describing: rawStationId))")
                        continue
                    }

                    let systemNameLocal: String
                    if let name = rawSystemNameLocal as? String {
                        systemNameLocal = name
                    } else {
                        Logger.error(
                            "systemNameLocal 类型转换失败: \(String(describing: rawSystemNameLocal))")
                        continue
                    }

                    let systemName = systemNameLocal

                    let security: Double
                    if let sec = rawSecurity as? Double {
                        security = sec
                    } else if let sec = rawSecurity as? String {
                        security = Double(sec) ?? 0.0
                    } else {
                        Logger.error("security 类型转换失败: \(String(describing: rawSecurity))")
                        continue
                    }

                    let info = LocationCacheInfo(
                        systemName: systemName,
                        security: security,
                        stationName: stationName
                    )
                    locationCache[stationId] = info
                    // Logger.debug("成功缓存空间站信息 - ID: \(stationId), 名称: \(stationNameLocal), 星系: \(systemName), 安全等级: \(security)")
                }
            } else {
                Logger.error("空间站查询失败 - SQL: \(query)")
            }
        }

        Logger.debug("位置信息缓存初始化完成 - 缓存数量: \(locationCache.count)")

        // 打印前20个缓存项
        Logger.debug("缓存内容预览（前20个）:")
        for (index, (id, info)) in locationCache.prefix(20).enumerated() {
            let type = LocationType.from(id: id)
            Logger.debug(
                "\(index + 1). ID: \(id) (\(type)) - 星系: \(info.systemName), 安全等级: \(info.security)"
                    + (info.stationName.map { ", 空间站: \($0)" } ?? ""))
        }
    }

    /// 加载建筑物位置信息
    @MainActor
    private func loadStructureLocationInfo(locationId: Int64) async -> LocationCacheInfo {
        do {
            let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                structureId: locationId,
                characterId: characterId
            )

            let query = """
                    SELECT s.solarSystemName, u.system_security
                    FROM solarsystems s
                    JOIN universe u ON u.solarsystem_id = s.solarSystemID
                    WHERE s.solarSystemID = ?
                """

            if case let .success(rows) = databaseManager.executeQuery(
                query, parameters: [structureInfo.solar_system_id]
            ),
                let row = rows.first,
                let systemNameLocal = row["solarSystemName"] as? String,
                let security = row["system_security"] as? Double
            {
                let systemName = systemNameLocal

                let locationInfo = LocationCacheInfo(
                    systemName: systemName,
                    security: security,
                    stationName: structureInfo.name
                )
                locationCache[locationId] = locationInfo
                return locationInfo
            }
        } catch {
            Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
        }

        return LocationCacheInfo.unknown
    }

    // MARK: - Loading Methods

    @MainActor
    func loadMembers(forceRefresh: Bool = false) {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone && !forceRefresh {
            return
        }

        cancelLoading(clearData: false)

        loadingTask = Task { @MainActor in
            isLoading = true
            error = nil
            locationCache.removeAll()

            do {
                // 1. 获取成员基本信息
                let memberList = try await CorpMembersAPI.shared.fetchMemberTracking(
                    characterId: characterId,
                    forceRefresh: forceRefresh
                )

                if Task.isCancelled { return }

                // 2. 获取所有角色ID
                let characterIds = memberList.map { $0.character_id }

                // 3. 批量获取角色名称
                let characterNames = try await UniverseAPI.shared.getNamesWithFallback(
                    ids: characterIds)

                if Task.isCancelled { return }

                // 4. 批量获取飞船信息
                let shipTypeIds = Set(memberList.compactMap { $0.ship_type_id })
                var shipInfoMap: [Int: (name: String, iconFilename: String)] = [:]

                if !shipTypeIds.isEmpty {
                    let query = """
                            SELECT type_id, name, icon_filename 
                            FROM types 
                            WHERE type_id IN (\(shipTypeIds.sorted().map { String($0) }.joined(separator: ",")))
                        """

                    if case let .success(rows) = databaseManager.executeQuery(query) {
                        for row in rows {
                            if let typeId = row["type_id"] as? Int,
                                let typeName = row["name"] as? String,
                                let iconFilename = row["icon_filename"] as? String
                            {
                                shipInfoMap[typeId] = (name: typeName, iconFilename: iconFilename)
                            }
                        }
                    }
                }

                // 5. 创建初始成员列表
                let pinnedIds = pinnedMemberIds
                allMembers = memberList.map { member in
                    MemberDetailInfo(
                        member: member,
                        characterName: characterNames[member.character_id]?.name
                            ?? String(member.character_id),
                        shipInfo: member.ship_type_id.flatMap { shipInfoMap[$0] },
                        isPinned: pinnedIds.contains(member.character_id)
                    )
                }

                // 根据当前排序选项进行排序
                sortMembers()

                // 计算总页数
                totalPages = (allMembers.count + pageSize - 1) / pageSize
                // 重置到第一页
                currentPage = 0
                updatePage()

                // 6. 初始化基础位置信息
                let locationIds = Set(
                    memberList.compactMap { member in
                        if let locationId = member.location_id {
                            return Int64(locationId)
                        }
                        return nil
                    })
                await initializeBasicLocationInfo(locationIds: locationIds)

                initialLoadDone = true

            } catch is CancellationError {
                Logger.debug("军团成员列表加载已取消")
            } catch {
                Logger.error("加载军团成员列表失败: \(error)")
                self.error = error
            }

            isLoading = false
        }
    }

    // MARK: - Member Detail Loading

    @MainActor
    func loadMemberDetails(for memberId: Int) {
        Logger.info("Loading \(memberId)")

        // 在所有可能的数组中查找成员
        let memberIndex = members.firstIndex(where: { $0.id == memberId })
        let allMemberIndex = allMembers.firstIndex(where: { $0.id == memberId })
        let pinnedIndex = pinnedMembers.firstIndex(where: { $0.id == memberId })

        // 如果成员不在任何列表中，或者已经加载过详情，则返回
        if allMemberIndex == nil || (memberIndex.map { members[$0].characterInfo != nil } ?? false)
            || (allMemberIndex.map { allMembers[$0].characterInfo != nil } ?? false)
            || (pinnedIndex.map { pinnedMembers[$0].characterInfo != nil } ?? false)
        {
            return
        }

        Task {
            do {
                async let characterInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(
                    characterId: memberId
                )
                async let portraitTask = CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: memberId,
                    size: 64,
                    catchImage: false
                )

                let (characterInfo, portrait) = try await (characterInfoTask, portraitTask)

                if !Task.isCancelled {
                    // 更新所有包含该成员的数组
                    if let idx = memberIndex, idx < members.count {
                        members[idx].characterInfo = characterInfo
                        members[idx].portrait = portrait
                    }

                    if let idx = allMemberIndex, idx < allMembers.count {
                        allMembers[idx].characterInfo = characterInfo
                        allMembers[idx].portrait = portrait
                    }

                    if let idx = pinnedIndex, idx < pinnedMembers.count {
                        pinnedMembers[idx].characterInfo = characterInfo
                        pinnedMembers[idx].portrait = portrait
                    }
                }
            } catch {
                Logger.error("加载成员详细信息失败 - 角色ID: \(memberId), 错误: \(error)")
            }
        }
    }

    func cancelLoading(clearData: Bool = false) {
        loadingTask?.cancel()
        loadingTask = nil

        if clearData {
            allMembers.removeAll()
            members.removeAll()
            locationCache.removeAll()
            currentPage = 0
            totalPages = 0
            initialLoadDone = false
        }
    }

    deinit {
        cancelLoading(clearData: true)
    }

    // 仅更新大头针状态
    @MainActor
    func refreshPinStatus() {
        let ids = pinnedMemberIds
        // 更新所有成员的置顶状态
        for index in allMembers.indices {
            allMembers[index].isPinned = ids.contains(allMembers[index].id)
        }
        // 更新当前页面显示的成员状态
        updatePage()
    }

    @MainActor
    func sortMembers() {
        // 定义排序函数
        let sortFunction: (MemberDetailInfo, MemberDetailInfo) -> Bool = { member1, member2 in
            switch self.sortOption {
            case .name:
                return member1.characterName.localizedCaseInsensitiveCompare(member2.characterName)
                    == .orderedAscending
            case .ship:
                let ship1 = member1.shipInfo?.name ?? ""
                let ship2 = member2.shipInfo?.name ?? ""
                // 如果两个都是空，则按人名排序
                if ship1.isEmpty && ship2.isEmpty {
                    return member1.characterName.localizedCaseInsensitiveCompare(
                        member2.characterName) == .orderedAscending
                }
                // 如果其中一个是空，空的排在后面
                if ship1.isEmpty { return false }
                if ship2.isEmpty { return true }
                // 都不为空，则按船名排序
                return ship1.localizedCaseInsensitiveCompare(ship2) == .orderedAscending
            }
        }

        // 对主列表排序
        allMembers.sort(by: sortFunction)
        // 对收藏列表排序
        pinnedMembers.sort(by: sortFunction)
        // 更新当前页面
        updatePage()
    }

    @MainActor
    func setSortOption(_ option: MemberSortOption) {
        sortOption = option
        // 确保在设置排序选项时也会触发收藏列表的排序
        sortMembers()
    }

    // 添加公共方法获取过滤后的成员数量
    @MainActor
    func getFilteredMembersCount() -> Int {
        if searchText.isEmpty {
            return allMembers.count
        }

        let searchQuery = searchText.lowercased()
        return allMembers.filter { member in
            member.characterName.lowercased().contains(searchQuery)
                || (member.shipInfo?.name.lowercased().contains(searchQuery) ?? false)
        }.count
    }

    // 添加公共方法获取过滤后的收藏成员
    @MainActor
    func getFilteredPinnedMembers() -> [MemberDetailInfo] {
        if searchText.isEmpty {
            return pinnedMembers
        }

        let searchQuery = searchText.lowercased()
        return pinnedMembers.filter { member in
            member.characterName.lowercased().contains(searchQuery)
                || (member.shipInfo?.name.lowercased().contains(searchQuery) ?? false)
        }
    }

    @MainActor
    func loadPinnedMembers() {
        let ids = pinnedMemberIds
        // 从 allMembers 中获取基本信息
        pinnedMembers = allMembers.filter { ids.contains($0.id) }

        // 为每个关注的成员加载详细信息
        for memberId in ids {
            loadMemberDetails(for: memberId)
        }
    }

    // 添加公共方法来获取过滤后的收藏成员数量
    @MainActor
    func getFilteredPinnedMembersCount() -> Int {
        if searchText.isEmpty {
            return pinnedMembers.count
        }

        return getFilteredPinnedMembers().count
    }
}

// MARK: - Views

struct LocationView: View {
    let locationId: Int64
    @ObservedObject var viewModel: CorpMemberListViewModel
    @State private var locationInfo: LocationCacheInfo?
    @State private var loadingTask: Task<Void, Never>?

    var body: some View {
        if let info = locationInfo {
            HStack(spacing: 4) {
                Text(String(format: "%.1f", info.security))
                    .font(.caption)
                    .foregroundColor(getSecurityColor(info.security))
                Text(info.systemName)
                    .font(.caption)
            }
        } else {
            Text(NSLocalizedString("Misc_Loading", comment: ""))
                .font(.caption)
                .foregroundColor(.gray)
                .onAppear {
                    // 取消之前的任务
                    loadingTask?.cancel()

                    // 创建新的延迟加载任务
                    loadingTask = Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1秒延迟
                        if !Task.isCancelled {
                            locationInfo = await viewModel.getLocationInfo(locationId: locationId)
                        }
                    }
                }
                .onDisappear {
                    loadingTask?.cancel()
                    loadingTask = nil
                }
        }
    }
}

struct MemberRowView: View {
    let member: MemberDetailInfo
    @ObservedObject var viewModel: CorpMemberListViewModel
    @State private var loadingTask: Task<Void, Never>?
    @State private var isLoadingPortrait: Bool = false
    @State private var hasAttemptedPortraitLoad: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            if isLoadingPortrait {
                ProgressView()
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let portrait = member.portrait {
                Image(uiImage: portrait)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                UniversePortrait(
                    id: member.id,
                    type: .character,
                    size: 64,
                    displaySize: 48
                )
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // 成员信息
            VStack(alignment: .leading, spacing: 4) {
                // 名称和称号
                Text(member.characterName)
                    .font(.headline)
                if let title = member.characterInfo?.title {
                    Text(title.removeHTMLTags())
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                // 飞船和位置信息
                HStack(spacing: 4) {
                    if let shipInfo = member.shipInfo {
                        // 飞船图标和名称
                        IconManager.shared.loadImage(for: shipInfo.iconFilename)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(shipInfo.name)
                            .font(.caption)
                        Text(" · ")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // 位置信息
                    if let locationId = member.member.location_id {
                        LocationView(locationId: Int64(locationId), viewModel: viewModel)
                    }
                }
            }

            Spacer()

            // 大头针按钮
            Button {
                viewModel.togglePinStatus(for: member.id)
            } label: {
                Image(systemName: member.isPinned ? "pin.fill" : "pin")
                    .foregroundColor(member.isPinned ? .blue : .gray)
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .onAppear {
            scheduleLoad()
        }
        .onDisappear {
            loadingTask?.cancel()
            loadingTask = nil
        }
    }

    private func scheduleLoad() {
        loadingTask?.cancel()
        loadingTask = Task {
            if !Task.isCancelled && !hasAttemptedPortraitLoad {
                await loadPortrait()
            }
        }
    }

    private func loadPortrait() async {
        guard !isLoadingPortrait && !hasAttemptedPortraitLoad else { return }

        isLoadingPortrait = true
        hasAttemptedPortraitLoad = true

        do {
            viewModel.loadMemberDetails(for: member.id)
        }

        if !Task.isCancelled {
            await MainActor.run {
                isLoadingPortrait = false
            }
        }
    }
}

struct SortMenuView: View {
    @ObservedObject var viewModel: CorpMemberListViewModel
    @Binding var isPresented: Bool

    var body: some View {
        Menu {
            ForEach(
                [
                    CorpMemberListViewModel.MemberSortOption.name,
                    .ship,
                ], id: \.self
            ) { option in
                Button(action: {
                    viewModel.setSortOption(option)
                }) {
                    HStack {
                        Text(option.localizedString)
                        if viewModel.sortOption == option {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundColor(.blue)
        }
    }
}

struct CorpMemberListView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpMemberListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshing = false

    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(
            wrappedValue: CorpMemberListViewModel(
                characterId: characterId,
                databaseManager: DatabaseManager.shared
            ))
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                // 特别关注部分
                if !viewModel.isLoading {
                    Section {
                        NavigationLink(destination: FavoriteMembersView(viewModel: viewModel)) {
                            Text(
                                NSLocalizedString("Main_Corporation_Members_Favorites", comment: "")
                            )
                        }
                    }
                }

                // 成员列表部分
                Section {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            VStack {
                                ProgressView()
                                    .padding(.bottom, 4)
                                Text(
                                    NSLocalizedString(
                                        "Main_Corporation_Members_Loading", comment: ""
                                    )
                                )
                                .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                        .listRowBackground(Color.clear)
                    } else {
                        let filteredMembers = viewModel.members
                        if filteredMembers.isEmpty {
                            Section {
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.3")
                                            .font(.system(size: 30))
                                            .foregroundColor(.gray)
                                        Text(
                                            viewModel.searchText.isEmpty
                                                ? NSLocalizedString(
                                                    "Main_Corporation_Members_No_Data", comment: "")
                                                : NSLocalizedString(
                                                    "Main_Corporation_Members_No_Search_Results",
                                                    comment: "")
                                        )
                                        .foregroundColor(.gray)
                                    }
                                    .padding()
                                    Spacer()
                                }
                            }
                        } else {
                            ForEach(filteredMembers) { member in
                                MemberRowView(member: member, viewModel: viewModel)
                            }
                        }
                    }
                } header: {
                    if !viewModel.isLoading {
                        let totalCount = viewModel.allMembers.count
                        let filteredCount = viewModel.getFilteredMembersCount()
                        if viewModel.searchText.isEmpty {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Corporation_Members_Total", comment: ""
                                    ), totalCount
                                ))
                        } else {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Corporation_Members_Total", comment: ""
                                    ), totalCount
                                )
                                    + " · "
                                    + String(
                                        format: NSLocalizedString(
                                            "Main_Corporation_Members_Filtered_Total", comment: ""
                                        ),
                                        filteredCount
                                    ))
                        }
                    }
                }
            }

            // 分页控制器
            if !viewModel.isLoading && viewModel.totalPages > 1 {
                HStack(spacing: 20) {
                    Button(action: { viewModel.previousPage() }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(viewModel.currentPage > 0 ? .blue : .gray)
                    }
                    .disabled(viewModel.currentPage == 0)

                    Text("\(viewModel.currentPage + 1) / \(viewModel.totalPages)")
                        .font(.caption)

                    Button(action: { viewModel.nextPage() }) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(
                                viewModel.currentPage < viewModel.totalPages - 1 ? .blue : .gray)
                    }
                    .disabled(viewModel.currentPage == viewModel.totalPages - 1)
                }
                .padding(.vertical, 8)
                .background(Color(UIColor.systemBackground))
            }
        }
        .navigationTitle(NSLocalizedString("Main_Corporation_Members_Title", comment: ""))
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Corporation_Members_Search_Placeholder", comment: "")
        )
        .refreshable {
            viewModel.loadMembers(forceRefresh: true)
        }
        .task {
            viewModel.loadMembers(forceRefresh: false)
        }
        .onAppear {
            viewModel.refreshPinStatus()
        }
        .onDisappear {
            viewModel.cancelLoading(clearData: false)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: {
                        refreshData()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                    }
                    .disabled(isRefreshing || viewModel.isLoading)
                    
                    SortMenuView(viewModel: viewModel, isPresented: .constant(false))
                }
            }
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.updatePage()
        }
        .alert(isPresented: $viewModel.showError) {
            Alert(
                title: Text(NSLocalizedString("Common_Error", comment: "")),
                message: Text(
                    viewModel.error?.localizedDescription
                        ?? NSLocalizedString("Common_Unknown_Error", comment: "")),
                dismissButton: .default(Text(NSLocalizedString("Common_OK", comment: ""))) {
                    dismiss()
                }
            )
        }
    }
    
    private func refreshData() {
        isRefreshing = true
        
        Task {
            viewModel.loadMembers(forceRefresh: true)
            isRefreshing = false
        }
    }
}

struct FavoriteMembersView: View {
    @ObservedObject var viewModel: CorpMemberListViewModel

    var body: some View {
        List {
            Section {
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        VStack {
                            ProgressView()
                                .padding(.bottom, 4)
                            Text(
                                NSLocalizedString(
                                    "Main_Corporation_Members_Loading", comment: ""
                                )
                            )
                            .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding()
                    .listRowBackground(Color.clear)
                } else if let error = viewModel.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("Main_Corporation_Members_Error", comment: ""))
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Button(action: {
                            viewModel.loadMembers(forceRefresh: true)
                        }) {
                            Text(
                                NSLocalizedString(
                                    "Main_Corporation_Members_Refresh", comment: ""
                                ))
                        }
                        .padding(.top, 4)
                    }
                } else {
                    let filteredMembers = viewModel.getFilteredPinnedMembers()

                    if filteredMembers.isEmpty {
                        Section {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "star")
                                        .font(.system(size: 30))
                                        .foregroundColor(.gray)
                                    Text(
                                        viewModel.searchText.isEmpty
                                            ? NSLocalizedString(
                                                "Main_Corporation_Members_No_Favorites", comment: ""
                                            )
                                            : NSLocalizedString(
                                                "Main_Corporation_Members_No_Search_Results",
                                                comment: "")
                                    )
                                    .foregroundColor(.gray)
                                }
                                .padding()
                                Spacer()
                            }
                        }
                    } else {
                        ForEach(filteredMembers) { member in
                            MemberRowView(member: member, viewModel: viewModel)
                        }
                    }
                }
            } header: {
                if !viewModel.isLoading && viewModel.error == nil {
                    let totalCount = viewModel.pinnedMembers.count
                    let filteredCount = viewModel.getFilteredPinnedMembersCount()
                    if viewModel.searchText.isEmpty {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Main_Corporation_Members_Favorites_Total", comment: ""
                                ),
                                totalCount
                            ))
                    } else {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Main_Corporation_Members_Favorites_Total", comment: ""
                                ),
                                totalCount
                            ) + " · "
                                + String(
                                    format: NSLocalizedString(
                                        "Main_Corporation_Members_Filtered_Total", comment: ""
                                    ),
                                    filteredCount
                                ))
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Corporation_Members_Favorites_Title", comment: ""))
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Corporation_Members_Search_Placeholder", comment: "")
        )
        .refreshable {
            viewModel.loadMembers(forceRefresh: true)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                SortMenuView(viewModel: viewModel, isPresented: .constant(false))
            }
        }
        .onAppear {
            viewModel.loadPinnedMembers()
        }
    }
}
