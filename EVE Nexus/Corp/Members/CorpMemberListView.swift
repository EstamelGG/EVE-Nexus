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
    
    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }
    
    func cancelLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
    
    /// 从数据库加载星系和空间站信息
    private func loadBasicLocationInfo(locationIds: Set<Int64>) async -> [Int64: LocationInfoDetail] {
        var locationInfoCache: [Int64: LocationInfoDetail] = [:]
        
        // 过滤掉无效的位置ID
        let validIds = locationIds.filter { $0 > 0 }
        
        if validIds.isEmpty {
            Logger.debug("没有有效的位置ID需要加载")
            return locationInfoCache
        }
        
        Logger.debug("开始从数据库加载位置信息 - 有效位置IDs: \(validIds)")
        
        // 1. 尝试作为星系ID查询
        let universeQuery = """
            SELECT u.solarsystem_id, u.system_security,
                   s.solarSystemName
            FROM universe u
            JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
            WHERE u.solarsystem_id IN (\(validIds.map { String($0) }.joined(separator: ",")))
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
                    Logger.debug("从数据库加载到星系信息 - ID: \(systemId), 名称: \(systemName)")
                }
            }
        }
        
        // 2. 对于未解析的ID，尝试作为空间站ID查询
        let remainingIds = validIds.filter { !locationInfoCache.keys.contains($0) }
        if !remainingIds.isEmpty {
            let stationQuery = """
                SELECT s.stationID, s.stationName, ss.solarSystemName, u.system_security
                FROM stations s
                JOIN solarSystems ss ON s.solarSystemID = ss.solarSystemID
                JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                WHERE s.stationID IN (\(remainingIds.map { String($0) }.joined(separator: ",")))
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
                        Logger.debug("从数据库加载到空间站信息 - ID: \(stationId), 名称: \(stationName)")
                    }
                }
            }
        }
        
        return locationInfoCache
    }
    
    /// 加载单个建筑物的位置信息
    @MainActor
    func loadStructureLocationInfo(locationId: Int64) async {
        
        // 检查是否已经加载过
        if let index = members.firstIndex(where: { 
            if let memberLocationId = $0.member.location_id {
                return memberLocationId == locationId
            }
            return false
        }),
           members[index].locationInfo != nil {
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
                
                // 更新对应成员的位置信息
                if let index = members.firstIndex(where: { 
                    if let memberLocationId = $0.member.location_id {
                        return memberLocationId == locationId
                    }
                    return false
                }) {
                    members[index].locationInfo = LocationInfoDetail(
                        stationName: structureInfo.name,
                        solarSystemName: systemName,
                        security: security
                    )
                    Logger.debug("成功获取建筑物信息 - ID: \(locationId), 名称: \(structureInfo.name)")
                }
            }
        } catch {
            Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
        }
    }
    
    @MainActor
    func loadMembers() {
        cancelLoading()
        
        loadingTask = Task { @MainActor in
            isLoading = true
            error = nil
            
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
                let locationInfoMap = await loadBasicLocationInfo(locationIds: locationIds)
                
                // 7. 更新成员的基本位置信息
                for index in members.indices {
                    if let locationId = members[index].member.location_id,
                       let locationInfo = locationInfoMap[Int64(locationId)] {
                        members[index].locationInfo = locationInfo
                    }
                }
                
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
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .task {
                            // 当行出现在视图中时，加载建筑物信息
                            await viewModel.loadStructureLocationInfo(locationId: Int64(locationId))
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
