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
    
    // 位置信息缓存
    var locationInfoMap: [Int64: LocationInfoDetail] = [:]
    // 待加载的建筑物ID
    private var pendingStructureIds: Set<Int64> = []
    
    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }
    
    func cancelLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
    
    /// 从数据库加载基本位置信息（星系和空间站）
    @MainActor
    func loadLocationInfo(locationId: Int64) async {
        // 如果已经有缓存，直接返回
        if locationInfoMap[locationId] != nil {
            return
        }
        
        Logger.debug("开始加载位置信息 - ID: \(locationId)")
        
        // 1. 尝试作为星系ID查询
        if locationId >= 30000000 && locationId < 40000000 {
            let universeQuery = """
                SELECT u.solarsystem_id, u.system_security,
                       s.solarSystemName
                FROM universe u
                JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                WHERE u.solarsystem_id = ?
            """
            
            if case .success(let rows) = databaseManager.executeQuery(universeQuery, parameters: [locationId]),
               let row = rows.first,
               let security = row["system_security"] as? Double,
               let systemName = row["solarSystemName"] as? String {
                locationInfoMap[locationId] = LocationInfoDetail(
                    stationName: "",
                    solarSystemName: systemName,
                    security: security
                )
                Logger.debug("加载星系信息 - ID: \(locationId), 名称: \(systemName)")
                return
            }
        }
        
        // 2. 尝试作为空间站ID查询
        if locationId >= 60000000 && locationId < 70000000 {
            let stationQuery = """
                SELECT s.stationID, s.stationName, ss.solarSystemName, u.system_security
                FROM stations s
                JOIN solarSystems ss ON s.solarSystemID = ss.solarSystemID
                JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                WHERE s.stationID = ?
            """
            
            if case .success(let rows) = databaseManager.executeQuery(stationQuery, parameters: [locationId]),
               let row = rows.first,
               let stationName = row["stationName"] as? String,
               let systemName = row["solarSystemName"] as? String,
               let security = row["system_security"] as? Double {
                locationInfoMap[locationId] = LocationInfoDetail(
                    stationName: stationName,
                    solarSystemName: systemName,
                    security: security
                )
                Logger.debug("加载空间站信息 - ID: \(locationId), 名称: \(stationName)")
                return
            }
        }
        
        // 3. 如果是建筑物ID，从API获取
        if locationId >= 100000000 {
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
                    
                    locationInfoMap[locationId] = LocationInfoDetail(
                        stationName: structureInfo.name,
                        solarSystemName: systemName,
                        security: security
                    )
                    Logger.debug("成功获取建筑物信息 - ID: \(locationId), 名称: \(structureInfo.name)")
                }
            } catch {
                Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
            }
        }
    }
    
    /// 批量预加载星系和空间站的位置信息
    @MainActor
    private func preloadBasicLocationInfo(locationIds: Set<Int64>) async {
        // 按ID范围分组
        let solarSystemIds = locationIds.filter { $0 >= 30000000 && $0 < 40000000 }
        let stationIds = locationIds.filter { $0 >= 60000000 && $0 < 70000000 }
        
        Logger.debug("""
            预加载位置信息:
            - 星系IDs: \(solarSystemIds)
            - 空间站IDs: \(stationIds)
            """)
        
        // 1. 批量加载星系信息
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
                        locationInfoMap[systemId] = LocationInfoDetail(
                            stationName: "",
                            solarSystemName: systemName,
                            security: security
                        )
                        Logger.debug("预加载星系信息 - ID: \(systemId), 名称: \(systemName)")
                    }
                }
            }
        }
        
        // 2. 批量加载空间站信息
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
                        locationInfoMap[stationId] = LocationInfoDetail(
                            stationName: stationName,
                            solarSystemName: systemName,
                            security: security
                        )
                        Logger.debug("预加载空间站信息 - ID: \(stationId), 名称: \(stationName)")
                    }
                }
            }
        }
    }
    
    @MainActor
    func loadMembers() {
        cancelLoading()
        
        loadingTask = Task { @MainActor in
            isLoading = true
            error = nil
            locationInfoMap.removeAll()  // 清除位置信息缓存
            
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
                
                // 6. 预加载星系和空间站信息
                let locationIds = Set(memberList.compactMap { member in
                    if let locationId = member.location_id {
                        return Int64(locationId)
                    }
                    return nil
                })
                await preloadBasicLocationInfo(locationIds: locationIds)
                
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
                }
                
                if let locationId = member.member.location_id {
                    LocationLoadingView(locationId: Int64(locationId), viewModel: viewModel)
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
        if let cachedInfo = viewModel.locationInfoMap[locationId] {
            HStack {
                Text(String(format: "%.1f", cachedInfo.security))
                    .font(.caption)
                    .foregroundColor(securityColor(cachedInfo.security))
                Text(cachedInfo.solarSystemName)
                    .font(.caption)
            }
        } else {
            Text("Loading... \(locationId)")
                .font(.caption)
                .foregroundColor(.gray)
                .task {
                    if !isLoading {
                        isLoading = true
                        await viewModel.loadLocationInfo(locationId: locationId)
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
