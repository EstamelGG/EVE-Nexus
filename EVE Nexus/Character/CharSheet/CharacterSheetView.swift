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
    @State private var hasInitialized = false // 追踪是否已初始化

    // UserDefaults 键名常量
    private let lastShipTypeIdKey: String
    private let lastLocationKey: String

    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // 位置信息缓存结构体
    private struct LocationCache: Codable {
        let solarSystemId: Int
        let stationId: Int?
        let structureId: Int?
        let locationStatus: String
        let typeId: Int?
    }

    init(
        character: EVECharacterInfo, characterPortrait: UIImage?,
        databaseManager: DatabaseManager = DatabaseManager()
    ) {
        self.character = character
        self.characterPortrait = characterPortrait
        self.databaseManager = databaseManager
        _locationLoader = State(
            initialValue: LocationInfoLoader(
                databaseManager: databaseManager, characterId: Int64(character.CharacterID)
            ))
        // 为每个角色创建唯一的 UserDefaults 键
        lastShipTypeIdKey = "LastShipTypeId_\(character.CharacterID)"
        lastLocationKey = "LastLocation_\(character.CharacterID)"

        // 从 UserDefaults 加载上次的飞船信息
        if let lastShipTypeId = UserDefaults.standard.object(forKey: lastShipTypeIdKey) as? Int {
            let query = "SELECT name FROM types WHERE type_id = ?"
            if case let .success(rows) = databaseManager.executeQuery(
                query, parameters: [lastShipTypeId]
            ),
                let row = rows.first,
                let typeName = row["name"] as? String
            {
                // 使用上次的飞船类型创建一个临时的 CharacterShipInfo
                let lastShip = CharacterShipInfo(
                    ship_item_id: 0, ship_name: "", ship_type_id: lastShipTypeId
                )
                _currentShip = State(initialValue: lastShip)
                _shipTypeName = State(initialValue: typeName)
            }
        }
    }
    
    // 初始化数据加载，确保只加载一次
    private func loadInitialDataIfNeeded() {
        guard !hasInitialized else { return }
        
        hasInitialized = true
        
        Task {
            // 1. 首先加载本地数据库中的数据
            loadLocalData()

            // 2. 从缓存加载位置信息
            if let data = UserDefaults.standard.data(forKey: lastLocationKey),
                let locationCache = try? JSONDecoder().decode(LocationCache.self, from: data)
            {
                await loadLocationFromCache(locationCache)
            }

            // 3. 并行加载所有网络数据
            await withTaskGroup(of: Void.self) { group in
                // 加载在线状态
                group.addTask {
                    await loadOnlineStatus()
                }

                // 加载位置信息（强制刷新）
                group.addTask {
                    await loadLocationInfo(forceRefresh: true)
                }

                // 加载飞船信息
                group.addTask {
                    await loadShipInfo()
                }

                // 加载跳跃疲劳
                group.addTask {
                    await loadFatigueInfo()
                }

                // 加载军团和联盟信息
                group.addTask {
                    await loadCorporationAndAllianceInfo()
                }

                // 加载奖章信息
                group.addTask {
                    await loadMedalsInfo()
                }

                // 等待所有任务完成
                await group.waitForAll()
            }
        }
    }

    // 从缓存加载位置信息
    private func loadLocationFromCache(_ cache: LocationCache) async {
        if let structureId = cache.structureId {
            // 建筑物
            let _ = CharacterLocation(
                solar_system_id: cache.solarSystemId,
                structure_id: structureId,
                station_id: nil
            )
            if let info = await locationLoader?.loadLocationInfo(locationIds: [Int64(structureId)])
                .first?.value
            {
                await MainActor.run {
                    self.locationDetail = info
                    self.currentLocation = nil
                    self.locationStatus = CharacterLocation.LocationStatus(
                        rawValue: cache.locationStatus)
                    self.locationTypeId = cache.typeId
                }
            }
        } else if let stationId = cache.stationId {
            // 空间站
            let _ = CharacterLocation(
                solar_system_id: cache.solarSystemId,
                structure_id: nil,
                station_id: stationId
            )
            if let info = await locationLoader?.loadLocationInfo(locationIds: [Int64(stationId)])
                .first?.value
            {
                await MainActor.run {
                    self.locationDetail = info
                    self.currentLocation = nil
                    self.locationStatus = CharacterLocation.LocationStatus(
                        rawValue: cache.locationStatus)
                    self.locationTypeId = cache.typeId
                }
            }
        } else {
            // 星系
            if let info = await getSolarSystemInfo(
                solarSystemId: cache.solarSystemId, databaseManager: databaseManager
            ) {
                await MainActor.run {
                    self.locationDetail = nil
                    self.currentLocation = info
                    self.locationStatus = CharacterLocation.LocationStatus(
                        rawValue: cache.locationStatus)
                    self.locationTypeId = nil
                }
            }
        }
    }

    // 保存位置信息到缓存
    private func saveLocationToCache(location: CharacterLocation, typeId: Int? = nil) {
        let cache = LocationCache(
            solarSystemId: location.solar_system_id,
            stationId: location.station_id,
            structureId: location.structure_id,
            locationStatus: location.locationStatus.rawValue,
            typeId: typeId
        )

        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: lastLocationKey)
        }
    }

    // 比较位置是否相同
    private func isSameLocation(location: CharacterLocation, cache: LocationCache) -> Bool {
        // 检查基本信息是否相同
        guard location.solar_system_id == cache.solarSystemId,
            location.station_id == cache.stationId,
            location.structure_id == cache.structureId,
            location.locationStatus.rawValue == cache.locationStatus
        else {
            return false
        }
        return true
    }

    // 加载位置信息
    private func loadLocationInfo(forceRefresh: Bool = false) async {
        do {
            let location = try await CharacterLocationAPI.shared.fetchCharacterLocation(
                characterId: character.CharacterID,
                forceRefresh: forceRefresh
            )

            // 检查是否与缓存位置相同
            if let data = UserDefaults.standard.data(forKey: lastLocationKey),
                let locationCache = try? JSONDecoder().decode(LocationCache.self, from: data),
                isSameLocation(location: location, cache: locationCache)
            {
                // 位置相同，不需要更新UI
                return
            }

            // 位置不同，更新UI和缓存
            if let structureId = location.structure_id {
                let structureInfo = try? await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: Int64(structureId),
                    characterId: character.CharacterID
                )
                if let info = await locationLoader?.loadLocationInfo(locationIds: [
                    Int64(structureId)
                ]).first?.value {
                    await MainActor.run {
                        self.locationDetail = info
                        self.currentLocation = nil
                        self.locationStatus = location.locationStatus
                        self.locationTypeId = structureInfo?.type_id
                    }
                    saveLocationToCache(location: location, typeId: structureInfo?.type_id)
                }
            } else if let stationId = location.station_id {
                let query = "SELECT stationTypeID FROM stations WHERE stationID = ?"
                var typeId: Int?
                if case let .success(rows) = databaseManager.executeQuery(
                    query, parameters: [Int(stationId)]
                ),
                    let row = rows.first
                {
                    typeId = row["stationTypeID"] as? Int
                }

                if let info = await locationLoader?.loadLocationInfo(locationIds: [Int64(stationId)]
                ).first?.value {
                    await MainActor.run {
                        self.locationDetail = info
                        self.currentLocation = nil
                        self.locationStatus = location.locationStatus
                        self.locationTypeId = typeId
                    }
                    saveLocationToCache(location: location, typeId: typeId)
                }
            } else {
                if let info = await getSolarSystemInfo(
                    solarSystemId: location.solar_system_id, databaseManager: databaseManager
                ) {
                    await MainActor.run {
                        self.locationDetail = nil
                        self.currentLocation = info
                        self.locationStatus = location.locationStatus
                        self.locationTypeId = nil
                    }
                    saveLocationToCache(location: location)
                }
            }

            // 保存状态到数据库
            if let ship = currentShip {
                await saveCharacterState(location: location, ship: ship)
            }
        } catch {
            Logger.error("获取位置信息失败: \(error)")
        }
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
                            .overlay(
                                RoundedRectangle(cornerRadius: 8).stroke(
                                    Color.primary.opacity(0.2), lineWidth: 1
                                )
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05))
                            )
                            .shadow(color: Color.primary.opacity(0.1), radius: 4, x: 0, y: 2)
                            .padding(4)
                    } else {
                        Image(systemName: "person.crop.square")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 72, height: 72)
                            .foregroundColor(Color.primary.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8).stroke(
                                    Color.primary.opacity(0.2), lineWidth: 1
                                )
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05))
                            )
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
                                        isLoading: true,
                                        statusUnknown: false
                                    )
                                } else if let status = onlineStatus {
                                    OnlineStatusIndicator(
                                        isOnline: status.online,
                                        size: 8,
                                        isLoading: false,
                                        statusUnknown: false
                                    )
                                } else {
                                    OnlineStatusIndicator(
                                        isOnline: false,
                                        size: 8,
                                        isLoading: false,
                                        statusUnknown: true
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
                    .padding(.leading, 2)
                }

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
                            Text(String(format: "%.2f", security))
                                .font(.caption)
                                .foregroundColor(getSecurityStatusColor(security))
                        }
                    }
                }

                // 位置信息
                HStack {
                    // 位置图标
                    if locationDetail != nil {
                        if let typeId = locationTypeId,
                            let iconFileName = getStationIcon(
                                typeId: typeId, databaseManager: databaseManager
                            )
                        {
                            // 显示空间站或建筑物的图标
                            IconManager.shared.loadImage(for: iconFileName)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                        } else {
                            // 找不到图标时显示默认图标
                            Image("not_found")
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                        }
                    } else if currentLocation != nil {
                        // 在星系中时显示默认图标
                        if let location = currentLocation,
                            let iconFileName = getSystemIcon(
                                solarSystemId: location.systemId, databaseManager: databaseManager
                            )
                        {
                            IconManager.shared.loadImage(for: iconFileName)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                        } else {
                            Image("not_found")
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                        }
                    } else {
                        Image("not_found")
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
                                    Text(formatSystemSecurity(location.security))
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
                            Text("Unknown")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 当前飞船信息
                HStack {
                    // 飞船图标
                    if let ship = currentShip {
                        IconManager.shared.loadImage(for: getShipIcon(typeId: ship.ship_type_id))
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                    } else {
                        Image("not_found")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("Character_Current_Ship", comment: ""))
                            .font(.body)
                            .foregroundColor(.primary)
                        if currentShip != nil, let typeName = shipTypeName {
                            Text(typeName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Unknown")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("Common_info", comment: ""))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            // 跳跃疲劳信息 Section
            if let fatigue = fatigue,
                let jumpFatigueExpireDate = fatigue.jump_fatigue_expire_date,
                let lastJumpDate = fatigue.last_jump_date
            {
                Section {
                    HStack {
                        // 跳跃疲劳图标
                        Image("capitalnavigation")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(NSLocalizedString("Character_Jump_Fatigue", comment: ""))
                                    .font(.body)
                                    .foregroundColor(.primary)

                                if let expireDate = dateFormatter.date(from: jumpFatigueExpireDate)
                                {
                                    let remainingTime = expireDate.timeIntervalSince(Date())
                                    if remainingTime > 0 {
                                        Text(formatRemainingTime(remainingTime))
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    } else {
                                        Text(
                                            NSLocalizedString(
                                                "Character_No_Jump_Fatigue", comment: ""
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    }
                                }
                            }

                            if let jumpDate = dateFormatter.date(from: lastJumpDate) {
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Character_Last_Jump", comment: ""
                                        ),
                                        formatDate(jumpDate)
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Timer", comment: ""))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
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
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("Main_Character_Sheet", comment: ""))
        .onAppear {
            loadInitialDataIfNeeded()
        }
        .refreshable {
            // 用户下拉刷新时，强制从API获取最新数据
            await refreshAllData()
        }
    }

    // 加载在线状态
    private func loadOnlineStatus() async {
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

    // 加载飞船信息
    private func loadShipInfo() async {
        do {
            let shipInfo = try await CharacterLocationAPI.shared.fetchCharacterShip(
                characterId: character.CharacterID
            )

            let query = "SELECT name FROM types WHERE type_id = ?"
            if case let .success(rows) = databaseManager.executeQuery(
                query, parameters: [shipInfo.ship_type_id]
            ),
                let row = rows.first,
                let typeName = row["name"] as? String
            {
                await MainActor.run {
                    self.currentShip = shipInfo
                    self.shipTypeName = typeName
                    // 保存最新的飞船类型ID到 UserDefaults
                    UserDefaults.standard.set(shipInfo.ship_type_id, forKey: lastShipTypeIdKey)
                }
            }
        } catch {
            Logger.error("获取飞船信息失败: \(error)")
        }
    }

    // 加载跳跃疲劳信息
    private func loadFatigueInfo() async {
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

    // 加载军团和联盟信息
    private func loadCorporationAndAllianceInfo() async {
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
                async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(
                    allianceId: allianceId)
                async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: allianceId)

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
    }

    // 加载奖章信息
    private func loadMedalsInfo() async {
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

    // 加载本地数据（数据库中的数据）
    private func loadLocalData() {
        // 获取角色出生日期
        let birthdayQuery = "SELECT birthday FROM character_info WHERE character_id = ?"
        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            birthdayQuery, parameters: [character.CharacterID]
        ),
            let row = rows.first,
            let birthdayStr = row["birthday"] as? String
        {
            birthday = birthdayStr
        }

        // 获取安全等级
        let securityQuery = "SELECT security_status FROM character_info WHERE character_id = ?"
        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            securityQuery, parameters: [character.CharacterID]
        ),
            let row = rows.first,
            let security = row["security_status"] as? Double
        {
            securityStatus = security
        }
    }

    private func getStationIcon(typeId: Int, databaseManager: DatabaseManager) -> String? {
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeId]),
            let row = rows.first,
            let iconFile = row["icon_filename"] as? String
        {
            return iconFile.isEmpty ? DatabaseConfig.defaultItemIcon : iconFile
        }
        return DatabaseConfig.defaultItemIcon
    }

    private func getShipIcon(typeId: Int) -> String {
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeId]),
            let row = rows.first,
            let iconFile = row["icon_filename"] as? String
        {
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
            Int64(Date().timeIntervalSince1970),
        ]

        if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: parameters
        ) {
            Logger.error("保存角色状态失败: \(error)")
        }
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
            return String(
                format: NSLocalizedString("Time_Days_Hours_Minutes", comment: ""), days, hours,
                minutes
            )
        } else if hours > 0 {
            return String(
                format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes
            )
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
            let days = components.day
        {
            return String(
                format: NSLocalizedString("Character_Age", comment: ""), years, months, days
            )
        }
        return ""
    }

    // 下拉刷新时重新获取所有网络数据
    private func refreshAllData() async {
        Logger.info("开始刷新所有数据")

        // 并行执行所有网络请求
        async let locationTask = CharacterLocationAPI.shared.fetchCharacterLocation(
            characterId: character.CharacterID, forceRefresh: true
        )
        async let shipTask = CharacterLocationAPI.shared.fetchCharacterShip(
            characterId: character.CharacterID)
        async let fatigueTask = CharacterFatigueAPI.shared.fetchCharacterFatigue(
            characterId: character.CharacterID)
        async let onlineTask = CharacterLocationAPI.shared.fetchCharacterOnlineStatus(
            characterId: character.CharacterID, forceRefresh: true
        )
        async let publicInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(
            characterId: character.CharacterID, forceRefresh: true
        )
        async let medalsTask = CharacterMedalsAPI.shared.fetchCharacterMedals(
            characterId: character.CharacterID)

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
                if let info = await locationLoader?.loadLocationInfo(locationIds: [
                    Int64(structureId)
                ]).first?.value {
                    await MainActor.run {
                        self.locationDetail = info
                        self.locationStatus = location.locationStatus
                        self.locationTypeId = structureInfo?.type_id
                        Logger.info(
                            "更新建筑物信息 - 名称: \(info.stationName), 类型ID: \(String(describing: structureInfo?.type_id))"
                        )
                    }
                }
            } else if let stationId = location.station_id {
                // 空间站
                Logger.info("角色在空间站中 - 空间站ID: \(stationId)")
                let query = "SELECT stationTypeID FROM stations WHERE stationID = ?"
                if case let .success(rows) = databaseManager.executeQuery(
                    query, parameters: [stationId]
                ),
                    let row = rows.first,
                    let typeId = row["stationTypeID"] as? Int
                {
                    if let info = await locationLoader?.loadLocationInfo(locationIds: [
                        Int64(stationId)
                    ]).first?.value {
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
                if let info = await getSolarSystemInfo(
                    solarSystemId: location.solar_system_id, databaseManager: databaseManager
                ) {
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
            if case let .success(rows) = databaseManager.executeQuery(
                query, parameters: [shipInfo.ship_type_id]
            ),
                let row = rows.first,
                let typeName = row["name"] as? String
            {
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
                async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(
                    allianceId: allianceId)
                async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: allianceId)

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

        guard
            case let .success(rows) = databaseManager.executeQuery(
                query, parameters: [solarSystemId]
            ),
            let row = rows.first,
            let iconFileName = row["icon_filename"] as? String
        else {
            return nil
        }

        return iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
    }
}
