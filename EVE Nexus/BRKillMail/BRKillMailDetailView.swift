import SwiftUI

struct BRKillMailDetailView: View {
    let killmail: [String: Any]  // 这个现在只用来获取ID
    let kbAPI = KbEvetoolAPI.shared
    @State private var victimCharacterIcon: UIImage?
    @State private var victimCorporationIcon: UIImage?
    @State private var victimAllianceIcon: UIImage?
    @State private var shipIcon: UIImage?
    @State private var detailData: [String: Any]?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var shipValue: Double = 0
    @State private var destroyedValue: Double = 0
    @State private var droppedValue: Double = 0
    @State private var totalValue: Double = 0
    @State private var itemInfoCache: [Int: (name: String, iconFileName: String, categoryID: Int)] =
        [:]
    @State private var solarSystemInfo: SolarSystemInfo?

    var body: some View {
        List {
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let detail = detailData {
                // 装配图
                if killmail["_id"] is Int {
                    GeometryReader { geometry in
                        let availableWidth = geometry.size.width
                        BRKillMailFittingView(killMailData: detail)
                            .frame(width: availableWidth, height: availableWidth)
                            .cornerRadius(8)
                    }
                    .aspectRatio(1, contentMode: .fit)  // 强制保持1:1的比例
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }

                // 受害者信息行
                HStack(spacing: 12) {
                    // 角色头像
                    if let characterIcon = victimCharacterIcon {
                        Image(uiImage: characterIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 66, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ProgressView()
                            .frame(width: 66, height: 66)
                    }

                    // 军团和联盟图标
                    VStack(spacing: 2) {
                        if let corpIcon = victimCorporationIcon {
                            Image(uiImage: corpIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if let allyIcon = victimAllianceIcon,
                            let victInfo = detail["vict"] as? [String: Any],
                            let allyId = victInfo["ally"] as? Int,
                            allyId > 0
                        {
                            Image(uiImage: allyIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    // 名称信息
                    VStack(alignment: .leading, spacing: 2) {
                        // 角色名称
                        if let victInfo = detail["vict"] as? [String: Any],
                            let charId = victInfo["char"] as? Int,
                            let names = detail["names"] as? [String: [String: String]],
                            let chars = names["chars"],
                            let charName = chars[String(charId)]
                        {
                            Text(charName)
                                .font(.headline)
                        }

                        // 军团名称
                        if let victInfo = detail["vict"] as? [String: Any],
                            let corpId = victInfo["corp"] as? Int,
                            let names = detail["names"] as? [String: [String: String]],
                            let corps = names["corps"],
                            let corpName = corps[String(corpId)]
                        {
                            Text(corpName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        // 联盟名称
                        if let victInfo = detail["vict"] as? [String: Any],
                            let allyId = victInfo["ally"] as? Int,
                            allyId > 0,
                            let names = detail["names"] as? [String: [String: String]],
                            let allys = names["allys"],
                            let allyName = allys[String(allyId)]
                        {
                            Text(allyName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // Ship
                if let victInfo = detail["vict"] as? [String: Any],
                    let shipId = victInfo["ship"] as? Int
                {
                    HStack {
                        Text(NSLocalizedString("Main_KM_Ship", comment: ""))
                            .frame(width: 110, alignment: .leading)
                        HStack {
                            if let shipIcon = shipIcon {
                                Image(uiImage: shipIcon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            VStack(alignment: .leading) {
                                let shipInfo = getShipName(shipId)
                                Text(shipInfo.name)
                                Text(shipInfo.groupName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }

                // System
                if let sysInfo = detail["sys"] as? [String: Any] {
                    HStack {
                        Text(NSLocalizedString("Main_KM_System", comment: ""))
                            .frame(width: 110, alignment: .leading)
                            .frame(maxHeight: .infinity, alignment: .center)
                        VStack(alignment: .leading) {
                            HStack {
                                if let ssString = sysInfo["ss"] as? String,
                                    let ssValue = Double(ssString)
                                {
                                    Text(formatSecurityStatus(ssValue))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(getSecurityColor(ssValue))
                                }
                                if let solarSystemInfo = solarSystemInfo {
                                    Text(solarSystemInfo.systemName)
                                        .fontWeight(.bold)
                                } else {
                                    Text(sysInfo["name"] as? String ?? "")
                                        .fontWeight(.bold)
                                }
                            }
                            if let solarSystemInfo = solarSystemInfo {
                                Text(solarSystemInfo.regionName)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            } else {
                                Text(sysInfo["region"] as? String ?? "")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }

                // Local Time
                HStack {
                    Text(NSLocalizedString("Main_KM_Local_Time", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    if let time = detail["time"] as? Int {
                        Text(formatLocalTime(time))
                            .foregroundColor(.secondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // Damage
                HStack {
                    Text(NSLocalizedString("Main_KM_Damage", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    if let victInfo = detail["vict"] as? [String: Any] {
                        let damage = victInfo["dmg"] as? Int ?? 0
                        Text(formatNumber(damage))
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // Destroyed
                HStack {
                    Text(NSLocalizedString("Main_KM_Destroyed_Value", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    Text(FormatUtil.formatISK(destroyedValue))
                        .foregroundColor(.red)
                        .font(.system(.body, design: .monospaced))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // Dropped
                HStack {
                    Text(NSLocalizedString("Main_KM_Dropped_Value", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    Text(FormatUtil.formatISK(droppedValue))
                        .foregroundColor(.green)
                        .font(.system(.body, design: .monospaced))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // Total
                HStack {
                    Text(NSLocalizedString("Main_KM_Total", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    Text(FormatUtil.formatISK(totalValue))
                        .font(.system(.body, design: .monospaced))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // 装配信息
                if let victInfo = detail["vict"] as? [String: Any],
                    let items = victInfo["itms"] as? [[Int]]
                {
                    // 高槽
                    let highSlotItems = items.filter { item in
                        (27...34).contains(item[0]) && item.count >= 4
                    }.sorted { $0[0] < $1[0] }  // 按槽位顺序排序

                    if !highSlotItems.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_KM_High_Slots", comment: ""))
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        ) {
                            ForEach(highSlotItems, id: \.self) { item in
                                let typeId = item[1]
                                if item[2] > 0 {  // 掉落数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[2], isDropped: true,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                                if item[3] > 0 {  // 摧毁数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[3], isDropped: false,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                            }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 中槽
                    let mediumSlotItems = items.filter { item in
                        (19...26).contains(item[0]) && item.count >= 4
                    }.sorted { $0[0] < $1[0] }  // 按槽位顺序排序

                    if !mediumSlotItems.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_KM_Medium_Slots", comment: ""))
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        ) {
                            ForEach(mediumSlotItems, id: \.self) { item in
                                let typeId = item[1]
                                if item[2] > 0 {  // 掉落数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[2], isDropped: true,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                                if item[3] > 0 {  // 摧毁数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[3], isDropped: false,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                            }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 低槽
                    let lowSlotItems = items.filter { item in
                        (11...18).contains(item[0]) && item.count >= 4
                    }.sorted { $0[0] < $1[0] }  // 按槽位顺序排序

                    if !lowSlotItems.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_KM_Low_Slots", comment: ""))
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        ) {
                            ForEach(lowSlotItems, id: \.self) { item in
                                let typeId = item[1]
                                if item[2] > 0 {  // 掉落数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[2], isDropped: true,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                                if item[3] > 0 {  // 摧毁数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[3], isDropped: false,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                            }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 改装槽
                    let rigSlotItems = items.filter { item in
                        (92...94).contains(item[0]) && item.count >= 4
                    }.sorted { $0[0] < $1[0] }  // 按槽位顺序排序

                    if !rigSlotItems.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_KM_Rig_Slots", comment: ""))
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        ) {
                            ForEach(rigSlotItems, id: \.self) { item in
                                let typeId = item[1]
                                if item[2] > 0 {  // 掉落数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[2], isDropped: true,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                                if item[3] > 0 {  // 摧毁数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[3], isDropped: false,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                            }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 子系统槽
                    let subsystemSlotItems = items.filter { item in
                        (125...128).contains(item[0]) && item.count >= 4
                    }.sorted { $0[0] < $1[0] }  // 按槽位顺序排序

                    if !subsystemSlotItems.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_KM_Subsystem_Slots", comment: ""))
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        ) {
                            ForEach(subsystemSlotItems, id: \.self) { item in
                                let typeId = item[1]
                                if item[2] > 0 {  // 掉落数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[2], isDropped: true,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                                if item[3] > 0 {  // 摧毁数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[3], isDropped: false,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                            }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 战斗机发射管
                    let fighterTubeItems = items.filter { item in
                        (159...163).contains(item[0]) && item.count >= 4
                    }.sorted { $0[0] < $1[0] }  // 按槽位顺序排序

                    if !fighterTubeItems.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_KM_Fighter_Tubes", comment: ""))
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)
                        ) {
                            ForEach(fighterTubeItems, id: \.self) { item in
                                let typeId = item[1]
                                if item[2] > 0 {  // 掉落数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[2], isDropped: true,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                                if item[3] > 0 {  // 摧毁数量
                                    ItemRow(
                                        typeId: typeId, quantity: item[3], isDropped: false,
                                        itemInfoCache: itemInfoCache,
                                        prices: detail["prices"] as? [String: Double] ?? [:]
                                    )
                                }
                            }
                        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 获取所有非装配槽位的物品，按flag分组
                    let nonFittingItems = items.filter { item in
                        // 排除装配槽位的物品
                        !(11...18).contains(item[0])  // 低槽
                            && !(19...26).contains(item[0])  // 中槽
                            && !(27...34).contains(item[0])  // 高槽
                            && !(92...94).contains(item[0])  // 改装槽
                            && !(125...128).contains(item[0])  // 子系统槽
                            && !(159...163).contains(item[0])  // 战斗机发射管
                    }

                    // 获取所有可能的flag
                    let allFlags = Set(nonFittingItems.map { $0[0] })  // 从items中获取flags
                        .union(
                            Set(
                                (victInfo["cnts"] as? [[String: Any]])?.compactMap {
                                    $0["flag"] as? Int
                                } ?? [])
                        )  // 从containers中获取flags
                        .sorted()

                    // 对每个flag创建一个Section
                    ForEach(allFlags, id: \.self) { flag in
                        let flagItems = nonFittingItems.filter { $0[0] == flag }
                        let flagContainers =
                            (victInfo["cnts"] as? [[String: Any]])?.filter {
                                ($0["flag"] as? Int) == flag
                            } ?? []

                        if !flagItems.isEmpty || !flagContainers.isEmpty {
                            Section(
                                header: Text(getFlagName(flag))
                                    .fontWeight(.bold)
                                    .font(.system(size: 18))
                                    .foregroundColor(.primary)
                                    .textCase(.none)
                            ) {
                                // 显示直接在该舱室的物品
                                ForEach(flagItems, id: \.self) { item in
                                    let typeId = item[1]
                                    if item[2] > 0 {  // 掉落数量
                                        ItemRow(
                                            typeId: typeId, quantity: item[2], isDropped: true,
                                            itemInfoCache: itemInfoCache,
                                            prices: detail["prices"] as? [String: Double] ?? [:]
                                        )
                                    }
                                    if item[3] > 0 {  // 摧毁数量
                                        ItemRow(
                                            typeId: typeId, quantity: item[3], isDropped: false,
                                            itemInfoCache: itemInfoCache,
                                            prices: detail["prices"] as? [String: Double] ?? [:]
                                        )
                                    }
                                }

                                // 显示该舱室中的容器及其内容
                                ForEach(flagContainers.indices, id: \.self) { index in
                                    let container = flagContainers[index]
                                    if let typeId = container["type"] as? Int {
                                        // 显示容器本身
                                        if let drop = container["drop"] as? Int, drop == 1 {
                                            ItemRow(
                                                typeId: typeId, quantity: 1, isDropped: true,
                                                itemInfoCache: itemInfoCache,
                                                prices: detail["prices"] as? [String: Double] ?? [:]
                                            )
                                        }
                                        if let dstr = container["dstr"] as? Int, dstr == 1 {
                                            ItemRow(
                                                typeId: typeId, quantity: 1, isDropped: false,
                                                itemInfoCache: itemInfoCache,
                                                prices: detail["prices"] as? [String: Double] ?? [:]
                                            )
                                        }

                                        // 显示容器内的物品
                                        if let items = container["items"] as? [[Int]] {
                                            ForEach(items, id: \.self) { item in
                                                if item.count >= 4 {
                                                    let typeId = item[1]
                                                    if item[2] > 0 {  // 掉落数量
                                                        ItemRow(
                                                            typeId: typeId, quantity: item[2],
                                                            isDropped: true,
                                                            itemInfoCache: itemInfoCache,
                                                            prices: detail["prices"]
                                                                as? [String: Double] ?? [:]
                                                        )
                                                        .padding(.leading, 20)
                                                    }
                                                    if item[3] > 0 {  // 摧毁数量
                                                        ItemRow(
                                                            typeId: typeId, quantity: item[3],
                                                            isDropped: false,
                                                            itemInfoCache: itemInfoCache,
                                                            prices: detail["prices"]
                                                                as? [String: Double] ?? [:]
                                                        )
                                                        .padding(.leading, 20)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }.listRowInsets(
                                EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if let killId = killmail["_id"] as? Int {
                    Button {
                        openZKillboard(killId: killId)
                    } label: {
                        Text("zkillboard")
                        Image(systemName: "safari")
                    }
                }
            }
        }
        .refreshable {
            await loadBRKillMailDetail()
        }
        .task {
            if detailData == nil {
                await loadBRKillMailDetail()
            }
        }
    }

    private func loadBRKillMailDetail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let killId = killmail["_id"] as? Int {
                Logger.debug("装配图: 开始加载战报ID \(killId) 的详细信息")
                let detail = try await kbAPI.fetchKillMailDetail(killMailId: killId)

                // 一次性加载所有物品信息
                loadAllItemInfo(from: detail)

                // 获取到详细数据后加载图标
                await loadIcons(from: detail)

                // 获取星系信息
                if let sysInfo = detail["sys"] as? [String: Any],
                    let systemId = sysInfo["id"] as? Int
                {
                    solarSystemInfo = await getSolarSystemInfo(
                        solarSystemId: systemId,
                        databaseManager: DatabaseManager.shared
                    )
                }

                // 计算所有价值
                if let victInfo = detail["vict"] as? [String: Any],
                    let prices = detail["prices"] as? [String: Double]
                {
                    // 计算船只价值
                    if let shipId = victInfo["ship"] as? Int {
                        shipValue = getItemPrice(typeId: shipId, prices: prices)
                        destroyedValue = shipValue
                    }

                    // 计算其他价值
                    calculateValues(victInfo: victInfo, prices: prices)
                }

                // 所有数据都准备好后再更新UI
                await MainActor.run {
                    self.detailData = detail
                }
            } else {
                Logger.error("无法获取战报ID")
                errorMessage = "无法获取战报ID"
            }
        } catch {
            Logger.error("加载战斗日志详情失败: \(error)")
            errorMessage = "加载失败: \(error.localizedDescription)"
        }
    }

    private func loadIcons(from detail: [String: Any]) async {
        // 加载受害者角色头像
        if let victInfo = detail["vict"] as? [String: Any],
            let charId = victInfo["char"] as? Int
        {
            do {
                victimCharacterIcon = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: charId,
                    size: 128
                )
            } catch {
                Logger.error("加载角色头像失败: \(error)")
            }
        }

        // 加载军团图标
        if let victInfo = detail["vict"] as? [String: Any],
            let corpId = victInfo["corp"] as? Int
        {
            do {
                victimCorporationIcon = try await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: corpId,
                    size: 64
                )
            } catch {
                Logger.error("加载军团图标失败: \(error)")
            }
        }

        // 加载联盟图标
        if let victInfo = detail["vict"] as? [String: Any],
            let allyId = victInfo["ally"] as? Int,
            allyId > 0
        {
            do {
                victimAllianceIcon = try await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: allyId,
                    size: 64
                )
            } catch {
                Logger.error("加载联盟图标失败: \(error)")
            }
        }

        // 加载舰船图标
        if let victInfo = detail["vict"] as? [String: Any],
            let shipId = victInfo["ship"] as? Int
        {
            Task {
                do {
                    let image = try await ItemRenderAPI.shared.fetchItemRender(
                        typeId: shipId, size: 64)
                    await MainActor.run {
                        shipIcon = image
                    }
                } catch {
                    Logger.error("击毁详情: 加载舰船图标失败 - \(error)")
                }
            }
        }
    }

    private func getShipName(_ shipId: Int) -> (name: String, groupName: String) {
        let query = """
                SELECT name, group_name
                FROM types t 
                WHERE type_id = ?
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query, parameters: [shipId]
        ),
            let row = rows.first,
            let name = row["name"] as? String,
            let groupName = row["group_name"] as? String
        {
            return (name, groupName)
        }
        return ("Unknown Ship", "Unknown Group")
    }

    private func formatSecurityStatus(_ value: Double) -> String {
        return String(format: "%.1f", value)
    }

    private func formatLocalTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    private func getItemPrice(typeId: Int, prices: [String: Double]) -> Double {
        return prices[String(typeId)] ?? 0.0
    }

    private func calculateValues(victInfo: [String: Any], prices: [String: Double]) {
        // 获取舰船价值
        if let shipId = victInfo["ship"] as? Int {
            shipValue = getItemPrice(typeId: shipId, prices: prices)
            destroyedValue = shipValue
        }

        // 计算装备价值
        if let items = victInfo["itms"] as? [[Int]] {
            for item in items {
                guard item.count >= 4 else { continue }
                let typeId = item[1]
                let dropped = item[2]
                let destroyed = item[3]

                let price = getItemPrice(typeId: typeId, prices: prices)
                droppedValue += price * Double(dropped)
                destroyedValue += price * Double(destroyed)
            }
        }

        // 计算容器中物品的价值
        if let containers = victInfo["cnts"] as? [[String: Any]] {
            for container in containers {
                if let typeId = container["type"] as? Int {
                    let price = getItemPrice(typeId: typeId, prices: prices)

                    if let drop = container["drop"] as? Int, drop == 1 {
                        droppedValue += price
                    }
                    if let dstr = container["dstr"] as? Int, dstr == 1 {
                        destroyedValue += price
                    }
                }

                if let items = container["items"] as? [[Int]] {
                    for item in items {
                        guard item.count >= 4 else { continue }
                        let typeId = item[1]
                        let dropped = item[2]
                        let destroyed = item[3]

                        let price = getItemPrice(typeId: typeId, prices: prices)
                        droppedValue += price * Double(dropped)
                        destroyedValue += price * Double(destroyed)
                    }
                }
            }
        }

        totalValue = droppedValue + destroyedValue
    }

    private func openZKillboard(killId: Int) {
        if let url = URL(string: "https://zkillboard.com/kill/\(killId)/") {
            UIApplication.shared.open(url)
        }
    }

    private func getFlagName(_ flag: Int) -> String {
        let query = """
                SELECT flagName
                FROM invFlags
                WHERE flagID = ?
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [flag]),
            let row = rows.first,
            let flagName = row["flagName"] as? String
        {
            return NSLocalizedString(flagName, comment: "")
        }
        return NSLocalizedString("Unknown Flag", comment: "")
    }

    private func loadAllItemInfo(from detail: [String: Any]) {
        var typeIds = Set<Int>()

        // 收集所有物品ID
        if let victInfo = detail["vict"] as? [String: Any] {
            // 添加舰船ID
            if let shipId = victInfo["ship"] as? Int {
                typeIds.insert(shipId)
            }

            // 添加装配物品ID
            if let items = victInfo["itms"] as? [[Int]] {
                for item in items where item.count >= 4 {
                    typeIds.insert(item[1])
                }
            }

            // 添加容器及其内容物品ID
            if let containers = victInfo["cnts"] as? [[String: Any]] {
                for container in containers {
                    if let typeId = container["type"] as? Int {
                        typeIds.insert(typeId)
                    }
                    if let items = container["items"] as? [[Int]] {
                        for item in items where item.count >= 4 {
                            typeIds.insert(item[1])
                        }
                    }
                }
            }
        }

        // 一次性查询所有物品信息
        let placeholders = String(repeating: "?,", count: typeIds.count).dropLast()
        let query = """
                SELECT type_id, name, icon_filename, categoryID
                FROM types
                WHERE type_id IN (\(placeholders))
            """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query, parameters: Array(typeIds)
        ) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String,
                    let categoryID = row["categoryID"] as? Int
                {
                    itemInfoCache[typeId] = (name, iconFileName, categoryID)
                }
            }
        }
    }
}

// 修改 ItemRow 视图
struct ItemRow: View {
    let typeId: Int
    let quantity: Int
    let isDropped: Bool  // 是否为掉落物品
    let itemInfoCache: [Int: (name: String, iconFileName: String, categoryID: Int)]
    let prices: [String: Double]

    var body: some View {
        if let itemInfo = itemInfoCache[typeId] {
            NavigationLink(destination: {
                ItemInfoMap.getItemInfoView(
                    itemID: typeId,
                    databaseManager: DatabaseManager.shared
                )
            }) {
                HStack {
                    Image(uiImage: IconManager.shared.loadUIImage(for: itemInfo.iconFileName))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(itemInfo.name)
                        Text(FormatUtil.formatISK(getItemPrice() * Double(quantity)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                    if quantity > 1 {
                        Text("×\(quantity)")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(
                isDropped ? Color.green.opacity(0.2) : nil
            )
        } else {
            HStack {
                Image("not_found")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        String(
                            format: NSLocalizedString("KillMail_Unknown_Item", comment: ""), typeId
                        )
                    )
                    Text(FormatUtil.formatISK(getItemPrice() * Double(quantity)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if quantity > 1 {
                    Text("×\(quantity)")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func getItemPrice() -> Double {
        return prices[String(typeId)] ?? 0.0
    }
}
