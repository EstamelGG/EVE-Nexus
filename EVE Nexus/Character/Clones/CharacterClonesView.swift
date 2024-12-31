import SwiftUI

// 合并的克隆体信息
private struct MergedCloneLocation: Identifiable {
    let id: Int
    let locationType: String
    let locationId: Int
    let clones: [JumpClone]
    
    var cloneCount: Int { clones.count }
}

struct CharacterClonesView: View {
    let character: EVECharacterInfo
    @ObservedObject var databaseManager: DatabaseManager
    @State private var cloneInfo: CharacterCloneInfo?
    @State private var implants: [Int]?
    @State private var isLoading = true
    @State private var homeLocationDetail: LocationInfoDetail?
    @State private var locationLoader: LocationInfoLoader?
    @State private var locationTypeId: Int?
    @State private var implantDetails: [(Int, String, String)] = [] // (type_id, name, icon)
    @State private var mergedCloneLocations: [MergedCloneLocation] = []
    
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    init(character: EVECharacterInfo, databaseManager: DatabaseManager = DatabaseManager()) {
        self.character = character
        self.databaseManager = databaseManager
        self._locationLoader = State(initialValue: LocationInfoLoader(databaseManager: databaseManager, characterId: Int64(character.CharacterID)))
    }
    
    var body: some View {
        List {
            // 基地空间站信息
            Section(NSLocalizedString("Character_Home_Station", comment: "")) {
                if let cloneInfo = cloneInfo {
                    // 基地位置信息
                    if let locationDetail = homeLocationDetail {
                        HStack {
                            if let typeId = locationTypeId,
                               let iconFileName = getStationIcon(typeId: typeId, databaseManager: databaseManager) {
                                IconManager.shared.loadImage(for: iconFileName)
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(6)
                            } else {
                                IconManager.shared.loadImage(for: "icon_0_64.png")
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(6)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Character_Home_Location", comment: ""))
                                LocationInfoView(
                                    stationName: locationDetail.stationName,
                                    solarSystemName: locationDetail.solarSystemName,
                                    security: locationDetail.security,
                                    font: .caption,
                                    textColor: .secondary
                                )
                            }
                        }
                        .frame(height: 36)
                    }
                    
                    // 最后跳跃时间
                    if let lastJumpDate = cloneInfo.last_clone_jump_date,
                       let date = dateFormatter.date(from: lastJumpDate) {
                        HStack {
                            Image("jumpclones")
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Character_Last_Clone_Jump", comment: ""))
                                Text(formatDate(date))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(height: 36)
                    }
                    
                    // 最后空间站变更时间
                    if let lastStationDate = cloneInfo.last_station_change_date,
                       let date = dateFormatter.date(from: lastStationDate) {
                        HStack {
                            Image("station")
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Character_Last_Station_Change", comment: ""))
                                Text(formatDate(date))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(height: 36)
                    }
                }
            }
            
            // 当前植入体信息
            Section(NSLocalizedString("Character_Current_Implants", comment: "")) {
                ForEach(implantDetails, id: \.0) { implant in
                    HStack {
                        IconManager.shared.loadImage(for: implant.2)
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                        
                        Text(implant.1)
                            .font(.body)
                    }
                    .frame(height: 36)
                }
            }
            
            // 克隆体列表
            Section(NSLocalizedString("Character_Jump_Clones", comment: "")) {
                if cloneInfo != nil {
                    ForEach(mergedCloneLocations) { location in
                        NavigationLink {
                            CloneLocationDetailView(
                                clones: location.clones,
                                databaseManager: databaseManager
                            )
                        } label: {
                            CloneLocationRow(
                                locationId: location.locationId,
                                locationType: location.locationType,
                                databaseManager: databaseManager,
                                locationLoader: locationLoader,
                                characterId: character.CharacterID,
                                cloneCount: location.cloneCount
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Jump_Clones", comment: ""))
        .task {
            await loadCloneData()
        }
        .refreshable {
            await loadCloneData(forceRefresh: true)
        }
    }
    
    private func loadCloneData(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 获取克隆体信息
            let cloneInfo = try await CharacterClonesAPI.shared.fetchCharacterClones(
                characterId: character.CharacterID,
                forceRefresh: forceRefresh
            )
            
            // 合并相同位置的克隆体
            let groupedClones = Dictionary(grouping: cloneInfo.jump_clones) { clone in
                "\(clone.location_type)_\(clone.location_id)"
            }
            
            let mergedLocations = groupedClones.map { key, clones in
                let firstClone = clones[0]
                return MergedCloneLocation(
                    id: firstClone.location_id,
                    locationType: firstClone.location_type,
                    locationId: firstClone.location_id,
                    clones: clones
                )
            }.sorted { $0.locationId < $1.locationId }
            
            // 获取植入体信息
            let implants = try await CharacterImplantsAPI.shared.fetchCharacterImplants(
                characterId: character.CharacterID,
                forceRefresh: forceRefresh
            )
            
            // 获取基地位置详细信息
            let homeLocationId = Int64(cloneInfo.home_location.location_id)
            if let info = await locationLoader?.loadLocationInfo(locationIds: Set([homeLocationId])).first?.value {
                // 获取位置类型ID
                if cloneInfo.home_location.location_type == "structure" {
                    let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                        structureId: homeLocationId,
                        characterId: character.CharacterID
                    )
                    await MainActor.run {
                        self.locationTypeId = structureInfo?.type_id
                    }
                } else if cloneInfo.home_location.location_type == "station" {
                    let query = "SELECT stationTypeID FROM stations WHERE stationID = ?"
                    if case .success(let rows) = databaseManager.executeQuery(query, parameters: [Int(homeLocationId)]),
                       let row = rows.first,
                       let typeId = row["stationTypeID"] as? Int {
                        await MainActor.run {
                            self.locationTypeId = typeId
                        }
                    }
                }
                
                await MainActor.run {
                    self.homeLocationDetail = info
                }
            }
            
            // 获取植入体详细信息
            var implantDetails: [(Int, String, String)] = []
            let query = "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(implants.map { String($0) }.joined(separator: ",")))"
            if case .success(let rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let name = row["name"] as? String,
                       let iconFile = row["icon_filename"] as? String {
                        implantDetails.append((typeId, name, iconFile.isEmpty ? DatabaseConfig.defaultItemIcon : iconFile))
                    }
                }
            }
            
            // 更新UI
            await MainActor.run {
                self.cloneInfo = cloneInfo
                self.implants = implants
                self.implantDetails = implantDetails.sorted(by: { $0.0 < $1.0 })
                self.mergedCloneLocations = mergedLocations
            }
            
        } catch {
            Logger.error("加载克隆体数据失败: \(error)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    private func getStationIcon(typeId: Int, databaseManager: DatabaseManager) -> String? {
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let iconFile = row["icon_filename"] as? String {
            return iconFile.isEmpty ? DatabaseConfig.defaultItemIcon : iconFile
        }
        return DatabaseConfig.defaultItemIcon
    }
}

// 克隆体位置行视图
struct CloneLocationRow: View {
    let locationId: Int
    let locationType: String
    let databaseManager: DatabaseManager
    let locationLoader: LocationInfoLoader?
    let characterId: Int
    let cloneCount: Int
    @State private var locationDetail: LocationInfoDetail?
    @State private var locationTypeId: Int?
    
    init(locationId: Int, locationType: String, databaseManager: DatabaseManager, locationLoader: LocationInfoLoader?, characterId: Int, cloneCount: Int = 1) {
        self.locationId = locationId
        self.locationType = locationType
        self.databaseManager = databaseManager
        self.locationLoader = locationLoader
        self.characterId = characterId
        self.cloneCount = cloneCount
    }
    
    var body: some View {
        HStack {
            if let locationDetail = locationDetail {
                if let typeId = locationTypeId,
                   let iconFileName = getStationIcon(typeId: typeId, databaseManager: databaseManager) {
                    IconManager.shared.loadImage(for: iconFileName)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                } else {
                    IconManager.shared.loadImage(for: "icon_0_64.png")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    LocationInfoView(
                        stationName: locationDetail.stationName,
                        solarSystemName: locationDetail.solarSystemName,
                        security: locationDetail.security,
                        font: .body,
                        textColor: .primary
                    )
                    
                    Text(String(format: NSLocalizedString("Character_Clone_Count", comment: ""), cloneCount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ProgressView()
            }
        }
        .frame(height: 44) // 增加高度以适应新的文本行
        .task {
            await loadLocationInfo()
        }
    }
    
    private func loadLocationInfo() async {
        let locationIdInt64 = Int64(locationId)
        if let info = await locationLoader?.loadLocationInfo(locationIds: Set([locationIdInt64])).first?.value {
            // 获取位置类型ID
            if locationType == "structure" {
                let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: locationIdInt64,
                    characterId: characterId
                )
                await MainActor.run {
                    self.locationTypeId = structureInfo?.type_id
                }
            } else if locationType == "station" {
                let query = "SELECT stationTypeID FROM stations WHERE stationID = ?"
                if case .success(let rows) = databaseManager.executeQuery(query, parameters: [locationId]),
                   let row = rows.first,
                   let typeId = row["stationTypeID"] as? Int {
                    await MainActor.run {
                        self.locationTypeId = typeId
                    }
                }
            }
            
            await MainActor.run {
                self.locationDetail = info
            }
        }
    }
    
    private func getStationIcon(typeId: Int, databaseManager: DatabaseManager) -> String? {
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let iconFile = row["icon_filename"] as? String {
            return iconFile.isEmpty ? DatabaseConfig.defaultItemIcon : iconFile
        }
        return DatabaseConfig.defaultItemIcon
    }
}

// 克隆体位置详情视图
struct CloneLocationDetailView: View {
    let clones: [JumpClone]
    let databaseManager: DatabaseManager
    
    var body: some View {
        List {
            ForEach(clones, id: \.jump_clone_id) { clone in
                Section {
                    if let name = clone.name {
                        HStack {
                            Image(systemName: "tag")
                                .foregroundColor(.secondary)
                            Text(name)
                        }
                    }
                    
                    NavigationLink {
                        CloneImplantsView(
                            clone: clone,
                            databaseManager: databaseManager
                        )
                    } label: {
                        HStack {
                            Image(systemName: "brain")
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("Character_View_Implants", comment: ""))
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Character_Clone_Details", comment: ""))
    }
}

// 克隆体植入体详情视图
struct CloneImplantsView: View {
    let clone: JumpClone
    let databaseManager: DatabaseManager
    @State private var implantDetails: [(Int, String, String)] = [] // (type_id, name, icon)
    
    var body: some View {
        List {
            if !implantDetails.isEmpty {
                Section(NSLocalizedString("Character_Clone_Implants", comment: "")) {
                    ForEach(implantDetails, id: \.0) { implant in
                        HStack {
                            IconManager.shared.loadImage(for: implant.2)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                            
                            Text(implant.1)
                                .font(.body)
                        }
                        .frame(height: 36)
                    }
                }
            } else {
                Section {
                    Text(NSLocalizedString("Character_No_Implants", comment: ""))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Character_Clone_Details", comment: ""))
        .task {
            await loadImplantDetails()
        }
    }
    
    private func loadImplantDetails() async {
        if !clone.implants.isEmpty {
            let query = "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(clone.implants.map { String($0) }.joined(separator: ",")))"
            if case .success(let rows) = databaseManager.executeQuery(query) {
                var details: [(Int, String, String)] = []
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let name = row["name"] as? String,
                       let iconFile = row["icon_filename"] as? String {
                        details.append((typeId, name, iconFile.isEmpty ? DatabaseConfig.defaultItemIcon : iconFile))
                    }
                }
                await MainActor.run {
                    self.implantDetails = details.sorted(by: { $0.0 < $1.0 })
                }
            }
        }
    }
} 
