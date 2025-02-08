import SwiftUI
import Kingfisher

struct MemberDetailInfo: Identifiable {
    let member: MemberTrackingInfo
    var characterName: String
    var shipInfo: (name: String, iconFilename: String)?
    var locationInfo: LocationInfoDetail?
    
    // 延迟加载的信息
    var characterInfo: CharacterPublicInfo?
    var portrait: UIImage?
    
    var id: Int { member.character_id }
}

class CorpMemberListViewModel: ObservableObject {
    @Published var members: [MemberDetailInfo] = []
    @Published var isLoading = true
    @Published var error: Error?
    private let characterId: Int
    private let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    // 跟踪需要作为建筑物处理的locationId
    private var pendingStructureIds: Set<Int64> = []
    // 缓存已获取的建筑物位置信息
    private var structureLocationCache: [Int64: LocationInfoDetail] = [:]
    
    // 获取缓存的位置信息
    func getCachedLocationInfo(for locationId: Int64) -> LocationInfoDetail? {
        return structureLocationCache[locationId]
    }
    
    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }
    
    func cancelLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
    
    /// 从数据库加载星系和空间站信息
    private func loadBasicLocationInfo(locationIds: Set<Int64>) async -> (locations: [Int64: LocationInfoDetail], remainingIds: Set<Int64>) {
        var locationInfoCache: [Int64: LocationInfoDetail] = [:]
        var remainingIds = locationIds  // 初始化为所有ID
        
        // 过滤掉无效的位置ID
        remainingIds = remainingIds.filter { $0 > 0 }
        
        if remainingIds.isEmpty {
            Logger.debug("没有有效的位置ID需要加载")
            return (locations: [:], remainingIds: [])
        }
        
        // 将ID按范围分组
        let solarSystemIds = remainingIds.filter { $0 >= 30000000 && $0 < 40000000 }
        let stationIds = remainingIds.filter { $0 >= 60000000 && $0 < 70000000 }
        let structureIds = remainingIds.filter { $0 >= 100000000 }
        
        Logger.debug("""
            开始从数据库加载位置信息:
            - 星系IDs: \(solarSystemIds)
            - 空间站IDs: \(stationIds)
            - 建筑物IDs: \(structureIds)
            """)
        
        // 1. 处理星系ID
        if !solarSystemIds.isEmpty {
            let universeQuery = """
                SELECT u.solarsystem_id, u.system_security,
                       s.solarSystemName
                FROM universe u
                JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                WHERE u.solarsystem_id IN (\(solarSystemIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = databaseManager.executeQuery(universeQuery) {
                for row in rows {
                    if let systemId = row["solarsystem_id"] as? Int64,
                       let security = row["system_security"] as? Double,
                       let systemName = row["solarSystemName"] as? String {
                        locationInfoCache[systemId] = LocationInfoDetail(
                            stationName: "",
                            solarSystemName: systemName,
                            security: security
                        )
                        remainingIds.remove(systemId)
                        Logger.debug("从数据库加载到星系信息 - ID: \(systemId), 名称: \(systemName)")
                    }
                }
            }
        }
        
        // 2. 处理空间站ID
        if !stationIds.isEmpty {
            let stationQuery = """
                SELECT s.stationID, s.stationName, ss.solarSystemName, u.system_security
                FROM stations s
                JOIN solarSystems ss ON s.solarSystemID = ss.solarSystemID
                JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                WHERE s.stationID IN (\(stationIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = databaseManager.executeQuery(stationQuery) {
                for row in rows {
                    if let stationId = row["stationID"] as? Int64,
                       let stationName = row["stationName"] as? String,
                       let systemName = row["solarSystemName"] as? String,
                       let security = row["system_security"] as? Double {
                        locationInfoCache[stationId] = LocationInfoDetail(
                            stationName: stationName,
                            solarSystemName: systemName,
                            security: security
                        )
                        remainingIds.remove(stationId)
                        Logger.debug("从数据库加载到空间站信息 - ID: \(stationId), 名称: \(stationName)")
                    }
                }
            }
        }
        
        // 3. 剩余的ID只包含未能在数据库中找到的ID，以及建筑物ID
        // 我们将它们作为待处理的建筑物ID返回
        Logger.debug("剩余待处理的ID数量: \(remainingIds.count), IDs: \(remainingIds)")
        
        return (locations: locationInfoCache, remainingIds: remainingIds)
    }
    
    /// 加载单个建筑物的位置信息
    @MainActor
    func loadStructureLocationInfo(locationId: Int64) async {
        // 检查缓存
        if let cachedInfo = structureLocationCache[locationId] {
            Logger.debug("使用缓存的建筑物信息 - ID: \(locationId)")
            // 更新当前可见的成员的位置信息
            if let index = members.firstIndex(where: { 
                if let memberLocationId = $0.member.location_id {
                    return Int64(memberLocationId) == locationId
                }
                return false
            }) {
                members[index].locationInfo = cachedInfo
            }
            return
        }
        
        do {
            Logger.debug("尝试获取建筑物信息 - ID: \(locationId)")
            let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                structureId: locationId,
                characterId: characterId
            )
            
            // 获取星系信息
            let systemQuery = """
                SELECT ss.solarSystemName, u.system_security
                FROM solarSystems ss
                JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                WHERE ss.solarSystemID = ?
            """
            
            if case .success(let rows) = databaseManager.executeQuery(systemQuery, parameters: [structureInfo.solar_system_id]),
               let row = rows.first,
               let systemName = row["solarSystemName"] as? String,
               let security = row["system_security"] as? Double {
                
                // 创建位置信息
                let locationInfo = LocationInfoDetail(
                    stationName: structureInfo.name,
                    solarSystemName: systemName,
                    security: security
                )
                
                // 保存到缓存，供后续使用
                structureLocationCache[locationId] = locationInfo
                
                // 只更新触发加载的当前成员的位置信息
                if let index = members.firstIndex(where: { 
                    if let memberLocationId = $0.member.location_id {
                        return Int64(memberLocationId) == locationId
                    }
                    return false
                }) {
                    members[index].locationInfo = locationInfo
                }
                
                // 成功加载后从待处理集合中移除
                pendingStructureIds.remove(locationId)
                Logger.debug("成功获取并缓存建筑物信息 - ID: \(locationId), 名称: \(structureInfo.name), 星系: \(systemName)")
            }
        } catch {
            // 如果获取失败，也从待处理集合中移除，避免反复请求失败的ID
            pendingStructureIds.remove(locationId)
            Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
        }
    }
    
    // 重置缓存（在loadMembers开始时调用）
    private func resetCache() {
        structureLocationCache.removeAll()
        pendingStructureIds.removeAll()
    }
    
    @MainActor
    func loadMembers() {
        cancelLoading()
        
        loadingTask = Task { @MainActor in
            isLoading = true
            error = nil
            resetCache()  // 重置缓存
            
            do {
                // 1. 获取成员基本信息
                let memberList = try await CorpMembersAPI.shared.fetchMemberTracking(characterId: characterId)
                
                if Task.isCancelled { return }
                
                // 2. 获取所有角色ID
                let characterIds = memberList.map { $0.character_id }
                
                // 3. 批量获取角色名称
                let characterNames = try await UniverseAPI.shared.getNamesWithFallback(ids: characterIds)
                
                if Task.isCancelled { return }
                
                // 4. 批量获取飞船信息
                let shipTypeIds = Set(memberList.compactMap { $0.ship_type_id })
                var shipInfoMap: [Int: (name: String, iconFilename: String)] = [:]
                
                if !shipTypeIds.isEmpty {
                    let query = """
                        SELECT type_id, name, icon_filename 
                        FROM types 
                        WHERE type_id IN (\(shipTypeIds.map { String($0) }.joined(separator: ",")))
                    """
                    
                    if case .success(let rows) = databaseManager.executeQuery(query) {
                        for row in rows {
                            if let typeId = row["type_id"] as? Int,
                               let typeName = row["name"] as? String,
                               let iconFilename = row["icon_filename"] as? String {
                                shipInfoMap[typeId] = (name: typeName, iconFilename: iconFilename)
                            }
                        }
                    }
                }
                
                // 5. 创建初始成员列表
                members = memberList.map { member in
                    MemberDetailInfo(
                        member: member,
                        characterName: characterNames[member.character_id]?.name ?? String(member.character_id),
                        shipInfo: member.ship_type_id.flatMap { shipInfoMap[$0] }
                    )
                }.sorted { $0.characterName < $1.characterName }
                
                // 6. 从数据库加载基本位置信息（星系和空间站）
                let locationIds = Set(memberList.compactMap { member in
                    if let locationId = member.location_id {
                        return Int64(locationId)
                    }
                    return nil
                })
                let (locationInfoMap, remainingIds) = await loadBasicLocationInfo(locationIds: locationIds)
                
                // 7. 更新成员的基本位置信息，并记录需要作为建筑物处理的ID
                for index in members.indices {
                    if let locationId = members[index].member.location_id {
                        if let locationInfo = locationInfoMap[Int64(locationId)] {
                            members[index].locationInfo = locationInfo
                        }
                    }
                }
                
                // 设置需要处理的建筑物ID
                pendingStructureIds = remainingIds
                Logger.debug("需要加载的建筑物数量: \(pendingStructureIds.count), IDs: \(remainingIds)")
                
            } catch is CancellationError {
                Logger.debug("军团成员列表加载已取消")
            } catch {
                Logger.error("加载军团成员列表失败: \(error)")
                self.error = error
            }
            
            isLoading = false
        }
    }
    
    // 延迟加载单个成员的详细信息
    @MainActor
    func loadMemberDetails(for memberId: Int) {
        guard let index = members.firstIndex(where: { $0.id == memberId }),
              members[index].characterInfo == nil else { return }
        
        Task {
            do {
                async let characterInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(
                    characterId: memberId
                )
                async let portraitTask = CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: memberId,
                    size: 32
                )
                
                let (characterInfo, portrait) = try await (characterInfoTask, portraitTask)
                
                if !Task.isCancelled {
                    members[index].characterInfo = characterInfo
                    members[index].portrait = portrait
                }
            } catch {
                Logger.error("加载成员详细信息失败 - 角色ID: \(memberId), 错误: \(error)")
            }
        }
    }
    
    deinit {
        cancelLoading()
    }
}

struct CorpMemberListView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpMemberListViewModel
    @State private var showingFavorites = false
    
    init(characterId: Int) {
        self.characterId = characterId
        self._viewModel = StateObject(wrappedValue: CorpMemberListViewModel(
            characterId: characterId,
            databaseManager: DatabaseManager.shared
        ))
    }
    
    var body: some View {
        List {
            // 特别关注部分
            if !viewModel.isLoading && viewModel.error == nil {
                Section {
                    Button(action: {
                        showingFavorites.toggle()
                    }) {
                        Text(NSLocalizedString("Main_Corporation_Members_Favorites", comment: ""))
                    }
                }
            }
            
            // 成员列表部分
            Section {
                if viewModel.isLoading {
                    ProgressView(NSLocalizedString("Main_Corporation_Members_Loading", comment: ""))
                } else if let error = viewModel.error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("Main_Corporation_Members_Error", comment: ""))
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Button(action: {
                            viewModel.loadMembers()
                        }) {
                            Text(NSLocalizedString("Main_Corporation_Members_Refresh", comment: ""))
                        }
                        .padding(.top, 4)
                    }
                } else {
                    ForEach(viewModel.members) { member in
                        MemberRowView(member: member, viewModel: viewModel)
                            .onAppear {
                                viewModel.loadMemberDetails(for: member.id)
                            }
                    }
                }
            } header: {
                if !viewModel.isLoading && viewModel.error == nil {
                    Text(String(format: NSLocalizedString("Main_Corporation_Members_Total", comment: ""), viewModel.members.count))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Corporation_Members_Title", comment: ""))
        .refreshable {
            viewModel.loadMembers()
        }
        .task {
            viewModel.loadMembers()
        }
        .onDisappear {
            viewModel.cancelLoading()
        }
    }
}

struct MemberRowView: View {
    let member: MemberDetailInfo
    @ObservedObject var viewModel: CorpMemberListViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // 头像
            if let portrait = member.portrait {
                Image(uiImage: portrait)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.gray)
            }
            
            // 成员信息
            VStack(alignment: .leading, spacing: 2) {
                // 名称和称号
                HStack {
                    Text(member.characterName)
                        .font(.headline)
                    if let title = member.characterInfo?.title {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                // 飞船和位置信息
                if let shipInfo = member.shipInfo {
                    Text(shipInfo.name)
                        .font(.caption)
                }
                
                if let location = member.locationInfo {
                    HStack {
                        Text(String(format: "%.1f", location.security))
                            .font(.caption)
                            .foregroundColor(securityColor(location.security))
                        Text(location.solarSystemName)
                            .font(.caption)
                    }
                } else if let locationId = member.member.location_id {
                    if locationId >= 100000000 {
                        LocationLoadingView(locationId: Int64(locationId), viewModel: viewModel)
                    } else {
                        Text("Unknown Location: \(locationId)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func securityColor(_ security: Double) -> Color {
        if security >= 0.5 {
            return .green
        } else if security > 0.0 {
            return .orange
        } else {
            return .red
        }
    }
}

struct LocationLoadingView: View {
    let locationId: Int64
    @ObservedObject var viewModel: CorpMemberListViewModel
    @State private var isLoading = false
    
    var body: some View {
        if let cachedInfo = viewModel.getCachedLocationInfo(for: locationId) {
            HStack {
                Text(String(format: "%.1f", cachedInfo.security))
                    .font(.caption)
                    .foregroundColor(securityColor(cachedInfo.security))
                Text(cachedInfo.solarSystemName)
                    .font(.caption)
            }
        } else {
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.gray)
                .task {
                    if !isLoading {
                        isLoading = true
                        await viewModel.loadStructureLocationInfo(locationId: locationId)
                        isLoading = false
                    }
                }
        }
    }
    
    private func securityColor(_ security: Double) -> Color {
        if security >= 0.5 {
            return .green
        } else if security > 0.0 {
            return .orange
        } else {
            return .red
        }
    }
}
