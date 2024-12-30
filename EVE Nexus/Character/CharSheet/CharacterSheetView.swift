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
            }
            
            // 位置信息 Section
            Section {
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
                        IconManager.shared.loadImage(for: "icon_9_64.png")
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
                        if let locationDetail = locationDetail {
                            // 空间站或建筑物信息
                            LocationInfoView(
                                stationName: locationDetail.stationName,
                                solarSystemName: locationDetail.solarSystemName,
                                security: locationDetail.security,
                                font: .body,
                                textColor: .primary
                            )
                        } else if let location = currentLocation {
                            // 星系信息（在太空中）
                            VStack(alignment: .leading, spacing: 2) {
                                LocationInfoView(
                                    stationName: nil,
                                    solarSystemName: location.systemName,
                                    security: location.security,
                                    font: .body,
                                    textColor: .primary
                                )
                                
                                if let status = locationStatus {
                                    Text(status.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            Text(NSLocalizedString("Location_Unknown", comment: ""))
                                .font(.body)
                                .foregroundColor(.gray)
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("Character_Location", comment: ""))
            }
            
            // 当前飞船信息 Section
            if let ship = currentShip {
                Section {
                    HStack {
                        // 飞船图标
                        IconManager.shared.loadImage(for: getShipIcon(typeId: ship.ship_type_id))
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ship.ship_name)
                                .font(.body)
                                .foregroundColor(.primary)
                            if let typeName = shipTypeName {
                                Text(typeName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Character_Current_Ship", comment: ""))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Character_Sheet", comment: ""))
        .task {
            await loadCharacterInfo()
        }
    }
    
    private func loadCharacterInfo() async {
        do {
            // 获取角色公开信息
            let publicInfo = try await CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: character.CharacterID
            )
            
            // 在单独的任务中获取在线状态
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
            
            // 获取位置信息
            Task {
                do {
                    let location = try await CharacterLocationAPI.shared.fetchCharacterLocation(
                        characterId: character.CharacterID
                    )
                    
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
                } catch {
                    Logger.error("获取角色位置信息失败: \(error)")
                }
            }
            
            // 获取军团信息
            async let corpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: publicInfo.corporation_id
            )
            async let corpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: publicInfo.corporation_id
            )
            
            do {
                let (info, logo) = try await (corpInfoTask, corpLogoTask)
                await MainActor.run {
                    self.corporationInfo = info
                    self.corporationLogo = logo
                }
            } catch {
                Logger.error("获取军团信息失败: \(error)")
            }
            
            // 获取联盟信息（如果有）
            if let allianceId = publicInfo.alliance_id {
                async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(allianceId: allianceId)
                async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                
                do {
                    let (info, logo) = try await (allianceInfoTask, allianceLogoTask)
                    await MainActor.run {
                        self.allianceInfo = info
                        self.allianceLogo = logo
                    }
                } catch {
                    Logger.error("获取联盟信息失败: \(error)")
                }
            }
            
            // 获取当前飞船信息
            Task {
                do {
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
                } catch {
                    Logger.error("获取角色飞船信息失败: \(error)")
                }
            }
            
        } catch {
            Logger.error("获取角色信息失败: \(error)")
            await MainActor.run {
                self.isLoadingOnlineStatus = false
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
    
    private func getShipIcon(typeId: Int) -> String {
        let query = "SELECT icon_filename FROM types WHERE type_id = ?"
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let iconFile = row["icon_filename"] as? String {
            return iconFile.isEmpty ? DatabaseConfig.defaultItemIcon : iconFile
        }
        return DatabaseConfig.defaultItemIcon
    }
} 
