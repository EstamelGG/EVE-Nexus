import SwiftUI

struct CharacterSheetView: View {
    let character: EVECharacterInfo
    let characterPortrait: UIImage?
    @ObservedObject var databaseManager: DatabaseManager
    @State private var corporationInfo: CorporationInfo?
    @State private var corporationLogo: UIImage?
    @State private var allianceInfo: AllianceInfo?
    @State private var allianceLogo: UIImage?
    @State private var onlineStatus: CharacterOnlineStatus?
    @State private var isLoadingOnlineStatus = true
    @State private var currentLocation: SolarSystemInfo?
    @State private var locationStatus: CharacterLocation.LocationStatus?
    @State private var locationDetail: LocationInfoDetail?
    @State private var locationLoader: LocationInfoLoader?
    @State private var locationTypeId: Int?
    @State private var currentShip: CharacterShipInfo?
    @State private var shipTypeName: String?
    @State private var securityStatus: Double?
    @State private var fatigue: CharacterFatigue?
    @State private var isLoadingFatigue = true
    @State private var birthday: String?
    @State private var medals: [CharacterMedal]?
    @State private var isLoadingMedals = true
    
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    init(character: EVECharacterInfo, characterPortrait: UIImage?, databaseManager: DatabaseManager = DatabaseManager()) {
        self.character = character
        self.characterPortrait = characterPortrait
        self.databaseManager = databaseManager
        self._locationLoader = State(initialValue: LocationInfoLoader(databaseManager: databaseManager, characterId: Int64(character.CharacterID)))
    }
    
    var body: some View {
        List {
            Section {
                // 基本信息单元格
                HStack {
                    // 角色头像
                    if let portrait = characterPortrait {
                        Image(uiImage: portrait)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                            .shadow(color: Color.primary.opacity(0.1), radius: 4, x: 0, y: 2)
                            .padding(4)
                    } else {
                        Image(systemName: "person.crop.square")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .foregroundColor(Color.primary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.2), lineWidth: 1))
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                            .shadow(color: Color.primary.opacity(0.1), radius: 4, x: 0, y: 2)
                            .padding(4)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // 角色名称和在线状态
                        HStack(spacing: 4) {
                            // 在线状态指示器容器，与下方图标宽度相同
                            HStack {
                                if isLoadingOnlineStatus {
                                    OnlineStatusIndicator(
                                        isOnline: true,
                                        size: 8,
                                        isLoading: true
                                    )
                                } else if let status = onlineStatus {
                                    OnlineStatusIndicator(
                                        isOnline: status.online,
                                        size: 8,
                                        isLoading: false
                                    )
                                }
                            }
                            .frame(width: 18, alignment: .center)
                            
                            Text(character.CharacterName)
                                .font(.headline)
                                .lineLimit(1)
                        }
                        
                        // 联盟信息
                        HStack(spacing: 4) {
                            if let alliance = allianceInfo, let logo = allianceLogo {
                                Image(uiImage: logo)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                Text("[\(alliance.ticker)] \(alliance.name)")
                                    .font(.caption)
                                    .lineLimit(1)
                            } else {
                                Image(systemName: "square.dashed")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(.gray)
                                Text("[-] \(NSLocalizedString("No Alliance", comment: ""))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                        
                        // 军团信息
                        HStack(spacing: 4) {
                            if let corporation = corporationInfo, let logo = corporationLogo {
                                Image(uiImage: logo)
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                Text("[\(corporation.ticker)] \(corporation.name)")
                                    .font(.caption)
                                    .lineLimit(1)
                            } else {
                                Image(systemName: "square.dashed")
                                    .resizable()
                                    .frame(width: 18, height: 18)
                                    .foregroundColor(.gray)
                                Text("[-] \(NSLocalizedString("No Corporation", comment: ""))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.leading, 4)
                }
                .frame(height: 72)
                
                // 出生日期信息
                if let birthday = birthday {
                    HStack {
                        // 出生日期图标
                        Image("channeloperator")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Character_Birthday", comment: ""))
                                .font(.body)
                                .foregroundColor(.primary)
                            if let date = dateFormatter.date(from: birthday) {
                                Text("\(formatBirthday(date)) (\(calculateAge(from: date)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(height: 36)
                }
                
                // 安全等级信息
                if let security = securityStatus {
                    HStack {
                        // 安全等级图标
                        Image("securitystatus")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Character_Security_Status", comment: ""))
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(formatSecurity(security))
                                .font(.caption)
                                .foregroundColor(getSecurityStatusColor(security))
                        }
                    }
                    .frame(height: 36)
                }
                
                // 位置信息
                HStack {
                    // 位置图标
                    if locationDetail != nil {
                        if let typeId = locationTypeId,
                           let iconFileName = getStationIcon(typeId: typeId, databaseManager: databaseManager) {
                            // 显示空间站或建筑物的图标
                            IconManager.shared.loadImage(for: iconFileName)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                        } else {
                            // 找不到图标时显示默认图标
                            IconManager.shared.loadImage(for: "icon_0_64.png")
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                        }
                    } else if currentLocation != nil {
                        // 在星系中时显示默认图标
                        if let location = currentLocation,
                           let iconFileName = getSystemIcon(solarSystemId: location.systemId, databaseManager: databaseManager) {
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
                    } else {
                        IconManager.shared.loadImage(for: "icon_0_64.png")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Character_Current_Location", comment: ""))
                        if let locationDetail = locationDetail {
                            // 空间站或建筑物信息
                            LocationInfoView(
                                stationName: locationDetail.stationName,
                                solarSystemName: locationDetail.solarSystemName,
                                security: locationDetail.security,
                                font: .caption,
                                textColor: .secondary
                            )
                        } else if let location = currentLocation {
                            // 星系信息（在太空中）
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(formatSecurity(location.security))
                                        .foregroundColor(getSecurityColor(location.security))
                                    Text("\(location.systemName) / \(location.regionName)")
                                    if let status = locationStatus {
                                        Text(status.description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        } else {
                            Text(NSLocalizedString("Location_Unknown", comment: ""))
                                .font(.body)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(height: 36)
                
                // 当前飞船信息
                if let ship = currentShip {
                    HStack {
                        // 飞船图标
                        IconManager.shared.loadImage(for: getShipIcon(typeId: ship.ship_type_id))
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Character_Current_Ship", comment: ""))
                                .font(.body)
                                .foregroundColor(.primary)
                            if let typeName = shipTypeName {
                                Text(typeName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(height: 36)
                }
            } header: {
                Text(NSLocalizedString("Common_info", comment: ""))
            }
            
            // 跳跃疲劳信息 Section
            if let fatigue = fatigue,
               let jumpFatigueExpireDate = fatigue.jump_fatigue_expire_date,
               let lastJumpDate = fatigue.last_jump_date {
                Section {
                    HStack {
                        // 跳跃疲劳图标
                        Image("capitalnavigation")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack{
                                Text(NSLocalizedString("Character_Jump_Fatigue", comment: ""))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                if let expireDate = dateFormatter.date(from: jumpFatigueExpireDate) {
                                    let remainingTime = expireDate.timeIntervalSince(Date())
                                    if remainingTime > 0 {
                                        Text(formatRemainingTime(remainingTime))
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    } else {
                                        Text(NSLocalizedString("Character_No_Jump_Fatigue", comment: ""))
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                            
                            if let jumpDate = dateFormatter.date(from: lastJumpDate) {
                                Text(String(format: NSLocalizedString("Character_Last_Jump", comment: ""), formatDate(jumpDate)))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(height: 36)
                }
            }
            
            // 奖章信息 Section
            if let medals = medals, !medals.isEmpty {
                Section {
                    ForEach(medals, id: \.title) { medal in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image("achievements")
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(6)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    if let date = dateFormatter.date(from: medal.date) {
                                        Text(formatMedalDate(date))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(medal.title)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Text(medal.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    if let reason = medal.reason {
                                        Text(reason)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(NSLocalizedString("Character_Medals", comment: ""))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Character_Sheet", comment: ""))
        .task {
            // 1. 首先加载本地数据库中的数据
            loadLocalData()
            
            // 2. 异步加载需要网络请求的数据
            await loadNetworkData()
            
            // 5. 获取奖章信息
            Task {
                if let medals = try? await CharacterMedalsAPI.shared.fetchCharacterMedals(
                    characterId: character.CharacterID
                ) {
                    await MainActor.run {
                        self.medals = medals
                        self.isLoadingMedals = false
                    }
                } else {
                    await MainActor.run {
                        self.isLoadingMedals = false
                    }
                }
            }
        }
        .refreshable {
            // 用户下拉刷新时，强制从API获取最新数据
            await refreshAllData()
        }
    }
    
    // 加载本地数据（数据库中的数据）
    private func loadLocalData() {
        // 获取角色出生日期
        let birthdayQuery = "SELECT birthday FROM character_info WHERE character_id = ?"
        if case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(birthdayQuery, parameters: [character.CharacterID]),
           let row = rows.first,
           let birthdayStr = row["birthday"] as? String {
            self.birthday = birthdayStr
        }
        
        // 获取安全等级
        let securityQuery = "SELECT security_status FROM character_info WHERE character_id = ?"
        if case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(securityQuery, parameters: [character.CharacterID]),
           let row = rows.first,
           let security = row["security_status"] as? Double {
            self.securityStatus = security
        }
    }
    
    // 加载需要网络请求的数据
    private func loadNetworkData() async {
        // 使用多个独立的Task，避免相互阻塞
        
        // 1. 获取在线状态
        Task {
            if let status = try? await CharacterLocationAPI.shared.fetchCharacterOnlineStatus(
                characterId: character.CharacterID
            ) {
                await MainActor.run {
                    self.onlineStatus = status
                    self.isLoadingOnlineStatus = false
                }
            } else {
                await MainActor.run {
                    self.isLoadingOnlineStatus = false
                }
            }
        }
        
        // 2. 获取跳跃疲劳信息
        Task {
            if let fatigue = try? await CharacterFatigueAPI.shared.fetchCharacterFatigue(
                characterId: character.CharacterID
            ) {
                await MainActor.run {
                    self.fatigue = fatigue
                    self.isLoadingFatigue = false
                }
            } else {
                await MainActor.run {
                    self.isLoadingFatigue = false
                }
            }
        }
        
        // 3. 获取位置和飞船信息
        Task {
            await loadCharacterInfo(forceRefresh: false)
        }
        
        // 4. 获取军团和联盟信息
        Task {
            if let publicInfo = try? await CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: character.CharacterID
            ) {
                // 获取军团信息
                async let corpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                    corporationId: publicInfo.corporation_id
                )
                async let corpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: publicInfo.corporation_id
                )
                
                if let (info, logo) = try? await (corpInfoTask, corpLogoTask) {
                    await MainActor.run {
                        self.corporationInfo = info
                        self.corporationLogo = logo
                    }
                }
                
                // 获取联盟信息（如果有）
                if let allianceId = publicInfo.alliance_id {
                    async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(allianceId: allianceId)
                    async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                    
                    if let (info, logo) = try? await (allianceInfoTask, allianceLogoTask) {
                        await MainActor.run {
                            self.allianceInfo = info
                            self.allianceLogo = logo
                        }
                    }
                }
                
                // 更新安全等级（如果数据库中没有）
                if self.securityStatus == nil {
                    await MainActor.run {
                        self.securityStatus = publicInfo.security_status
                    }
                }
            }
        }
    }
    
    private func loadCharacterInfo(forceRefresh: Bool = false) async {
        do {
            // 获取位置信息，使用CharacterLocationAPI的缓存机制
            Logger.info("开始获取位置信息")
            let location = try await CharacterLocationAPI.shared.fetchCharacterLocation(
                characterId: character.CharacterID,
                forceRefresh: forceRefresh
            )
            Logger.info("成功获取位置信息: \(location)")
            
            // 根据位置类型获取详细信息
            if let structureId = location.structure_id {
                // 建筑物
                let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: Int64(structureId),
                    characterId: character.CharacterID
                )
                if let info = await locationLoader?.loadLocationInfo(locationIds: [Int64(structureId)]).first?.value {
                    await MainActor.run {
                        self.locationDetail = info
                        self.locationStatus = location.locationStatus
                        self.locationTypeId = structureInfo?.type_id
                    }
                }
            } else if let stationId = location.station_id {
                // 空间站
                let query = "SELECT stationTypeID FROM stations WHERE stationID = ?"
                if case .success(let rows) = databaseManager.executeQuery(query, parameters: [stationId]),
                   let row = rows.first,
                   let typeId = row["stationTypeID"] as? Int {
                    if let info = await locationLoader?.loadLocationInfo(locationIds: [Int64(stationId)]).first?.value {
                        await MainActor.run {
                            self.locationDetail = info
                            self.locationStatus = location.locationStatus
                            self.locationTypeId = typeId
                        }
                    }
                }
            } else {
                // 太空中
                if let info = await getSolarSystemInfo(solarSystemId: location.solar_system_id, databaseManager: databaseManager) {
                    await MainActor.run {
                        self.currentLocation = info
                        self.locationStatus = location.locationStatus
                        self.locationTypeId = nil
                    }
                }
            }
            
            // 获取当前飞船信息
            let shipInfo = try await CharacterLocationAPI.shared.fetchCharacterShip(
                characterId: character.CharacterID
            )
            
            // 获取飞船类型名称
            let query = "SELECT name FROM types WHERE type_id = ?"
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [shipInfo.ship_type_id]),
               let row = rows.first,
               let typeName = row["name"] as? String {
                await MainActor.run {
                    self.currentShip = shipInfo
                    self.shipTypeName = typeName
                }
            }
            
            // 保存状态到数据库（作为备份）
            await saveCharacterState(location: location, ship: shipInfo)
            
        } catch {
            Logger.error("获取角色位置信息失败: \(error)")
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
    
    private func getShipIcon(typeId: Int) -> String {
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let iconFile = row["icon_filename"] as? String {
            return iconFile.isEmpty ? DatabaseConfig.defaultItemIcon : iconFile
        }
        return DatabaseConfig.defaultItemIcon
    }
    
    private func saveCharacterState(location: CharacterLocation, ship: CharacterShipInfo?) async {
        let query = """
            INSERT OR REPLACE INTO character_current_state (
                character_id, solar_system_id, station_id, structure_id,
                location_status, ship_item_id, ship_type_id, ship_name,
                last_update
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        let parameters: [Any] = [
            Int64(character.CharacterID),
            Int64(location.solar_system_id),
            location.station_id != nil ? Int64(location.station_id!) : NSNull(),
            location.structure_id != nil ? Int64(location.structure_id!) : NSNull(),
            location.locationStatus.rawValue,
            ship?.ship_item_id != nil ? Int64(ship!.ship_item_id) : NSNull(),
            ship?.ship_type_id != nil ? Int64(ship!.ship_type_id) : NSNull(),
            ship?.ship_name ?? NSNull(),
            Int64(Date().timeIntervalSince1970)
        ]
        
        if case .error(let error) = CharacterDatabaseManager.shared.executeQuery(query, parameters: parameters) {
            Logger.error("保存角色状态失败: \(error)")
        }
    }
    
    private func loadCharacterStateFromDatabase() -> Bool {
        let query = """
            SELECT * FROM character_current_state 
            WHERE character_id = ? AND last_update > ?
        """
        
        // 只加载1小时内的缓存数据
        let oneHourAgo = Int(Date().timeIntervalSince1970) - 3600
        
        let result = CharacterDatabaseManager.shared.executeQuery(
            query,
            parameters: [Int64(character.CharacterID), oneHourAgo]
        )
        
        if case .success(let rows) = result,
           let row = rows.first {
            // 加载位置信息
            if let solarSystemId = row["solar_system_id"] as? Int64 {
                Task {
                    // 检查是否在建筑物中
                    if let structureId = row["structure_id"] as? Int64 {
                        // 建筑物
                        let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                            structureId: structureId,
                            characterId: character.CharacterID
                        )
                        if let info = await locationLoader?.loadLocationInfo(locationIds: [structureId]).first?.value {
                            await MainActor.run {
                                self.locationDetail = info
                                self.locationStatus = CharacterLocation.LocationStatus(rawValue: row["location_status"] as? String ?? "")
                                self.locationTypeId = structureInfo?.type_id
                            }
                        }
                    }
                    // 检查是否在空间站中
                    else if let stationId = row["station_id"] as? Int64 {
                        // 空间站
                        let query = "SELECT stationTypeID FROM stations WHERE stationID = ?"
                        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [Int(stationId)]),
                           let row = rows.first,
                           let typeId = row["stationTypeID"] as? Int {
                            if let info = await locationLoader?.loadLocationInfo(locationIds: [stationId]).first?.value {
                                await MainActor.run {
                                    self.locationDetail = info
                                    self.locationStatus = CharacterLocation.LocationStatus(rawValue: row["location_status"] as? String ?? "")
                                    self.locationTypeId = typeId
                                }
                            }
                        }
                    }
                    // 在太空中
                    else {
                        if let info = await getSolarSystemInfo(solarSystemId: Int(solarSystemId), databaseManager: databaseManager) {
                            await MainActor.run {
                                self.currentLocation = info
                                self.locationStatus = CharacterLocation.LocationStatus(rawValue: row["location_status"] as? String ?? "")
                                self.locationTypeId = nil
                            }
                        }
                    }
                }
            }
            
            // 加载飞船信息
            if let shipTypeId = row["ship_type_id"] as? Int64,
               let shipItemId = row["ship_item_id"] as? Int64,
               let shipName = row["ship_name"] as? String {
                let shipInfo = CharacterShipInfo(
                    ship_item_id: shipItemId,
                    ship_name: shipName,
                    ship_type_id: Int(shipTypeId)
                )
                
                // 获取飞船类型名称（从主数据库获取）
                let typeQuery = "SELECT name FROM types WHERE type_id = ?"
                if case .success(let typeRows) = databaseManager.executeQuery(typeQuery, parameters: [Int(shipTypeId)]),
                   let typeRow = typeRows.first,
                   let typeName = typeRow["name"] as? String {
                    Task { @MainActor in
                        self.currentShip = shipInfo
                        self.shipTypeName = typeName
                    }
                }
            }
            
            // 获取角色出生日期
            let birthdayQuery = "SELECT birthday FROM character_info WHERE character_id = ?"
            if case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(birthdayQuery, parameters: [character.CharacterID]),
               let row = rows.first,
               let birthdayStr = row["birthday"] as? String {
                Task { @MainActor in
                    self.birthday = birthdayStr
                }
            }
            
            return true
        }
        
        return false
    }
    
    private func getSecurityStatusColor(_ security: Double) -> Color {
        if security <= 0 {
            return .red
        } else if security <= 4 {
            return .green
        } else {
            return .blue
        }
    }
    
    private func formatRemainingTime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = (Int(seconds) % 86400) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if days > 0 {
            return String(format: NSLocalizedString("Time_Days_Hours_Minutes", comment: ""), days, hours, minutes)
        } else if hours > 0 {
            return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes)
        } else {
            return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    private func formatBirthday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    private func calculateAge(from birthday: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: birthday, to: now)
        
        if let years = components.year,
           let months = components.month,
           let days = components.day {
            return String(format: NSLocalizedString("Character_Age", comment: ""), years, months, days)
        }
        return ""
    }
    
    // 下拉刷新时重新获取所有网络数据
    private func refreshAllData() async {
        Logger.info("开始刷新所有数据")
        
        // 并行执行所有网络请求
        async let locationTask = CharacterLocationAPI.shared.fetchCharacterLocation(characterId: character.CharacterID, forceRefresh: true)
        async let shipTask = CharacterLocationAPI.shared.fetchCharacterShip(characterId: character.CharacterID)
        async let fatigueTask = CharacterFatigueAPI.shared.fetchCharacterFatigue(characterId: character.CharacterID)
        async let onlineTask = CharacterLocationAPI.shared.fetchCharacterOnlineStatus(characterId: character.CharacterID, forceRefresh: true)
        async let publicInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(characterId: character.CharacterID, forceRefresh: true)
        async let medalsTask = CharacterMedalsAPI.shared.fetchCharacterMedals(characterId: character.CharacterID)
        
        do {
            // 等待位置和飞船信息
            let (location, shipInfo) = try await (locationTask, shipTask)
            Logger.info("成功获取位置信息: \(location)")
            
            // 先清除旧的位置信息
            await MainActor.run {
                self.locationDetail = nil
                self.currentLocation = nil
                self.locationStatus = nil
                self.locationTypeId = nil
            }
            
            // 处理位置信息
            if let structureId = location.structure_id {
                // 建筑物
                Logger.info("角色在建筑物中 - 建筑物ID: \(structureId)")
                let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: Int64(structureId),
                    characterId: character.CharacterID
                )
                if let info = await locationLoader?.loadLocationInfo(locationIds: [Int64(structureId)]).first?.value {
                    await MainActor.run {
                        self.locationDetail = info
                        self.locationStatus = location.locationStatus
                        self.locationTypeId = structureInfo?.type_id
                        Logger.info("更新建筑物信息 - 名称: \(info.stationName), 类型ID: \(String(describing: structureInfo?.type_id))")
                    }
                }
            } else if let stationId = location.station_id {
                // 空间站
                Logger.info("角色在空间站中 - 空间站ID: \(stationId)")
                let query = "SELECT stationTypeID FROM stations WHERE stationID = ?"
                if case .success(let rows) = databaseManager.executeQuery(query, parameters: [stationId]),
                   let row = rows.first,
                   let typeId = row["stationTypeID"] as? Int {
                    if let info = await locationLoader?.loadLocationInfo(locationIds: [Int64(stationId)]).first?.value {
                        await MainActor.run {
                            self.locationDetail = info
                            self.locationStatus = location.locationStatus
                            self.locationTypeId = typeId
                            Logger.info("更新空间站信息 - 名称: \(info.stationName), 类型ID: \(typeId)")
                        }
                    }
                }
            } else {
                // 太空中
                Logger.info("角色在太空中 - 星系ID: \(location.solar_system_id)")
                if let info = await getSolarSystemInfo(solarSystemId: location.solar_system_id, databaseManager: databaseManager) {
                    await MainActor.run {
                        self.currentLocation = info
                        self.locationStatus = location.locationStatus
                        self.locationTypeId = nil
                        Logger.info("更新星系信息 - 名称: \(info.systemName)")
                    }
                }
            }
            
            // 处理飞船信息
            let query = "SELECT name FROM types WHERE type_id = ?"
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [shipInfo.ship_type_id]),
               let row = rows.first,
               let typeName = row["name"] as? String {
                await MainActor.run {
                    self.currentShip = shipInfo
                    self.shipTypeName = typeName
                }
            }
            
            // 保存状态到数据库
            await saveCharacterState(location: location, ship: shipInfo)
        } catch {
            Logger.error("刷新位置和飞船信息失败: \(error)")
        }
        
        // 处理其他并行请求的结果
        if let fatigue = try? await fatigueTask {
            await MainActor.run {
                self.fatigue = fatigue
                self.isLoadingFatigue = false
            }
        }
        
        if let status = try? await onlineTask {
            await MainActor.run {
                self.onlineStatus = status
                self.isLoadingOnlineStatus = false
            }
        }
        
        if let publicInfo = try? await publicInfoTask {
            // 获取军团信息
            async let corpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: publicInfo.corporation_id
            )
            async let corpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: publicInfo.corporation_id
            )
            
            if let (info, logo) = try? await (corpInfoTask, corpLogoTask) {
                await MainActor.run {
                    self.corporationInfo = info
                    self.corporationLogo = logo
                }
            }
            
            // 获取联盟信息（如果有）
            if let allianceId = publicInfo.alliance_id {
                async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(allianceId: allianceId)
                async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                
                if let (info, logo) = try? await (allianceInfoTask, allianceLogoTask) {
                    await MainActor.run {
                        self.allianceInfo = info
                        self.allianceLogo = logo
                    }
                }
            }
            
            // 更新安全等级
            await MainActor.run {
                self.securityStatus = publicInfo.security_status
            }
        }
        
        // 处理奖章信息
        if let medals = try? await medalsTask {
            await MainActor.run {
                self.medals = medals
                self.isLoadingMedals = false
            }
        }
        
        Logger.info("所有数据刷新完成")
    }
    
    private func formatMedalDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    private func getSystemIcon(solarSystemId: Int, databaseManager: DatabaseManager) -> String? {
        // 使用 JOIN 联合查询 universe 和 types 表
        let query = """
            SELECT t.icon_filename 
            FROM universe u 
            JOIN types t ON u.system_type = t.type_id 
            WHERE u.solarsystem_id = ?
        """
        
        guard case .success(let rows) = databaseManager.executeQuery(query, parameters: [solarSystemId]),
              let row = rows.first,
              let iconFileName = row["icon_filename"] as? String else {
            return nil
        }
        
        return iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
    }
}
