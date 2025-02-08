import SwiftUI
import Kingfisher

// MARK: - Data Models
struct MemberDetailInfo: Identifiable {
    let member: MemberTrackingInfo
    var characterName: String
    var shipInfo: (name: String, iconFilename: String)?
    
    // 延迟加载的信息
    var characterInfo: CharacterPublicInfo?
    var portrait: UIImage?
    
    var id: Int { member.character_id }
}

// MARK: - Location Types
enum LocationType {
    case solarSystem    // 30000000...39999999
    case station       // 60000000...69999999
    case structure     // >= 100000000
    case unknown
    
    static func from(id: Int64) -> LocationType {
        switch id {
        case 30000000...39999999:
            return .solarSystem
        case 60000000...69999999:
            return .station
        case 100000000...:
            return .structure
        default:
            return .unknown
        }
    }
}

// MARK: - Location Cache Info
struct LocationCacheInfo {
    let systemName: String
    let security: Double
    let stationName: String?
    
    static let unknown = LocationCacheInfo(
        systemName: "Unknown",
        security: 0.0,
        stationName: nil
    )
}

// MARK: - View Model
class CorpMemberListViewModel: ObservableObject {
    @Published var members: [MemberDetailInfo] = []
    @Published var isLoading = true
    @Published var error: Error?
    
    private let characterId: Int
    private let databaseManager: DatabaseManager
    private var loadingTask: Task<Void, Never>?
    
    // 位置信息缓存
    private var locationCache: [Int64: LocationCacheInfo] = [:]
    
    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }
    
    // MARK: - Location Methods
    /// 获取位置信息，优先从缓存获取
    @MainActor
    func getLocationInfo(locationId: Int64) async -> LocationCacheInfo {
        // 1. 检查缓存
        if let cached = locationCache[locationId] {
            return cached
        }
        
        // 2. 根据ID类型处理
        switch LocationType.from(id: locationId) {
        case .structure:
            // 对于建筑物，需要通过API获取
            return await loadStructureLocationInfo(locationId: locationId)
        default:
            // 其他类型如果缓存中没有，说明是未知位置
            return LocationCacheInfo.unknown
        }
    }
    
    /// 初始化基础位置信息（星系和空间站）
    @MainActor
    private func initializeBasicLocationInfo(locationIds: Set<Int64>) async {
        // 按类型分组
        let groupedIds = Dictionary(grouping: locationIds) { LocationType.from(id: $0) }
        
        // 加载星系信息
        if let solarSystemIds = groupedIds[.solarSystem] {
            let query = """
                SELECT u.solarsystem_id, u.system_security,
                       s.solarSystemName
                FROM universe u
                JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                WHERE u.solarsystem_id IN (\(solarSystemIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    if let systemId = row["solarsystem_id"] as? Int64,
                       let security = row["system_security"] as? Double,
                       let systemName = row["solarSystemName"] as? String {
                        locationCache[systemId] = LocationCacheInfo(
                            systemName: systemName,
                            security: security,
                            stationName: nil
                        )
                    }
                }
            }
        }
        
        // 加载空间站信息
        if let stationIds = groupedIds[.station] {
            let query = """
                SELECT s.stationID, s.stationName,
                       ss.solarSystemName, u.system_security
                FROM stations s
                JOIN solarsystems ss ON s.solarSystemID = ss.solarSystemID
                JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                WHERE s.stationID IN (\(stationIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    if let stationId = row["stationID"] as? Int64,
                       let stationName = row["stationName"] as? String,
                       let systemName = row["solarSystemName"] as? String,
                       let security = row["system_security"] as? Double {
                        locationCache[stationId] = LocationCacheInfo(
                            systemName: systemName,
                            security: security,
                            stationName: stationName
                        )
                    }
                }
            }
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
            
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [structureInfo.solar_system_id]),
               let row = rows.first,
               let systemName = row["solarSystemName"] as? String,
               let security = row["system_security"] as? Double {
                
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
    func loadMembers() {
        cancelLoading()
        
        loadingTask = Task { @MainActor in
            isLoading = true
            error = nil
            locationCache.removeAll()
            
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
                
                // 6. 初始化基础位置信息
                let locationIds = Set(memberList.compactMap { member in
                    if let locationId = member.location_id {
                        return Int64(locationId)
                    }
                    return nil
                })
                await initializeBasicLocationInfo(locationIds: locationIds)
                
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
    
    func cancelLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
    
    deinit {
        cancelLoading()
    }
}

// MARK: - Views
struct LocationView: View {
    let locationId: Int64
    @ObservedObject var viewModel: CorpMemberListViewModel
    @State private var locationInfo: LocationCacheInfo?
    
    var body: some View {
        if let info = locationInfo {
            HStack {
                Text(String(format: "%.1f", info.security))
                    .font(.caption)
                    .foregroundColor(securityColor(info.security))
                Text(info.systemName)
                    .font(.caption)
                if let stationName = info.stationName {
                    Text("(\(stationName))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        } else {
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.gray)
                .task {
                    locationInfo = await viewModel.getLocationInfo(locationId: locationId)
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
                
                // 飞船信息
                if let shipInfo = member.shipInfo {
                    Text(shipInfo.name)
                        .font(.caption)
                }
                
                // 位置信息
                if let locationId = member.member.location_id {
                    LocationView(locationId: Int64(locationId), viewModel: viewModel)
                }
            }
        }
        .padding(.vertical, 4)
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
