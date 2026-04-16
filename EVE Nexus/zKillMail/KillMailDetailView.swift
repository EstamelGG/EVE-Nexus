import SwiftUI

struct BRKillMailDetailView: View {
    let listEntity: KillMailListEntity
    let character: EVECharacterInfo?
    @ObservedObject private var killMailFavorites = KillMailFavoritesStore.shared
    @State private var victimCharacterIcon: UIImage?
    @State private var victimCorporationIcon: UIImage?
    @State private var victimAllianceIcon: UIImage?
    @State private var shipIcon: UIImage?
    @State private var detailData: KillMailDetailData?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var destroyedValue: Double = 0
    @State private var droppedValue: Double = 0
    @State private var totalValue: Double = 0
    @State private var fittedValue: Double = 0
    @State private var itemInfoCache: [Int: (name: String, iconFileName: String, categoryID: Int)] =
        [:]
    @State private var solarSystemInfo: SolarSystemInfo?
    @State private var zkbInfoFromAPI: ZKBInfo? // 存储从 API 获取的 zkb 信息
    /// 详情列表中各 type 的单价（EIV average）；未写入前 `ItemRow` 显示加载指示器
    @State private var kmMarketUnitPriceByType: [Int: Double] = [:]
    /// 每次开始加载详情时递增，用于丢弃上一轮未完成的价格写入
    @State private var kmMarketPriceSession: Int = 0

    // 监听屏幕方向变化
    @State private var orientation = UIDevice.current.orientation

    // 布局状态标识符（用于判断是否需要重新渲染视图）
    @State private var layoutMode: LayoutMode = DeviceUtils.currentLayoutMode

    // 判断是否应该使用紧凑布局（横屏或iPad）
    private var shouldUseCompactLayout: Bool {
        DeviceUtils.shouldUseCompactLayout
    }

    // 导航辅助方法
    @ViewBuilder
    private func navigationDestination(for id: Int, type: String) -> some View {
        if let character = character {
            switch type {
            case "character":
                CharacterDetailView(characterId: id, character: character)
            case "corporation":
                CorporationDetailView(corporationId: id, character: character)
            case "alliance":
                AllianceDetailView(allianceId: id, character: character)
            default:
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    var body: some View {
        List {
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let detail = detailData {
                if shouldUseCompactLayout {
                    compactLayout(detail: detail)
                        .contextMenu {
                            if let charId = detail.esi.victim.character_id {
                                NavigationLink {
                                    navigationDestination(for: charId, type: "character")
                                } label: {
                                    Label(NSLocalizedString("View Character", comment: ""), systemImage: "info.circle")
                                }
                            }
                            if detail.esi.victim.corporation_id > 0 {
                                NavigationLink {
                                    navigationDestination(for: detail.esi.victim.corporation_id, type: "corporation")
                                } label: {
                                    Label(NSLocalizedString("View Corporation", comment: ""), systemImage: "info.circle")
                                }
                            }
                            if let allyId = detail.esi.victim.alliance_id, allyId > 0 {
                                NavigationLink {
                                    navigationDestination(for: allyId, type: "alliance")
                                } label: {
                                    Label(NSLocalizedString("View Alliance", comment: ""), systemImage: "info.circle")
                                }
                            }
                            Divider()
                            let systemName = solarSystemInfo?.systemName ?? detail.system?.systemName ?? ""
                            if !systemName.isEmpty {
                                Button {
                                    UIPasteboard.general.string = systemName
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy_Location", comment: ""), systemImage: "location")
                                }
                            }
                        }
                } else {
                    // 默认竖屏布局
                    defaultLayout(detail: detail)
                }

                // 装配信息部分保持不变
                fittingInfoSections(detail: detail)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    killMailFavorites.toggle(
                        killmailId: listEntity.killmailId,
                        hash: listEntity.zkb.hash
                    )
                } label: {
                    Image(
                        systemName: killMailFavorites.isFavorite(killmailId: listEntity.killmailId)
                            ? "star.fill" : "star"
                    )
                    .foregroundColor(.yellow)
                }
                .accessibilityLabel(
                    killMailFavorites.isFavorite(killmailId: listEntity.killmailId)
                        ? NSLocalizedString("KillMail_Favorites_Remove_A11y", comment: "")
                        : NSLocalizedString("KillMail_Favorites_Add_A11y", comment: "")
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    openZKillboard(killId: listEntity.killmailId)
                } label: {
                    Text("zkillboard")
                    Image(systemName: "safari")
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
        .onAppear {
            setupOrientationNotification()
        }
        .onDisappear {
            removeOrientationNotification()
        }
        .id(layoutMode)
    }

    // MARK: - 布局视图函数

    // 紧凑布局（横屏或iPad）
    @ViewBuilder
    private func compactLayout(detail: KillMailDetailData) -> some View {
        // 第一行：左侧装配视图 + 右侧基本信息
        Section {
            GeometryReader { geometry in
                let availableWidth = geometry.size.width
                let fittingWidth = availableWidth * 0.5

                HStack(alignment: .top, spacing: 16) {
                    BRKillMailFittingView(detailData: detail)
                        .frame(width: fittingWidth, height: fittingWidth)
                        .cornerRadius(8)

                    VStack(spacing: 0) {
                        basicInfoList(detailData: detail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .aspectRatio(2, contentMode: .fit) // 2:1的比例
            .padding(.vertical, 8)
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }

        // 第二行：伤害和价值信息列表
        Section {
            KmValueList()
        }
    }

    @ViewBuilder
    private func defaultLayout(detail: KillMailDetailData) -> some View {
        GeometryReader { geometry in
            BRKillMailFittingView(detailData: detail)
                .frame(width: geometry.size.width, height: geometry.size.width)
                .cornerRadius(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        victimInfoSection(detailData: detail)
        basicInfoRows(detailData: detail)
    }

    @ViewBuilder
    private func basicInfoList(detailData: KillMailDetailData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            victimInfoCompact(detailData: detailData)
            Divider()
            shipInfoRow(shipId: detailData.esi.victim.ship_type_id)
            Divider()
            if let sys = detailData.system {
                systemInfoRowCompact(systemName: sys.systemName, regionName: sys.regionName, security: sys.security)
            }
            Divider()
            if let time = detailData.timestamp {
                localTimeRow(time: time)
                Divider()
            }
            DamageRow(dmg: detailData.esi.victim.damage_taken)
            Divider()
            if totalValue >= 0 {
                TotalRow(total: totalValue)
                Divider()
            }
            NavigationLink {
                KillMailAttackersView(detailData: detailData, character: character)
            } label: {
                HStack {
                    Text(NSLocalizedString("Main_KM_Attackers", comment: ""))
                    Spacer()
                    Text("\(detailData.attackers.count)")
                        .foregroundColor(.secondary)
                }
            }
            Divider()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func victimInfoCompact(detailData: KillMailDetailData) -> some View {
        let v = detailData.esi.victim
        HStack(spacing: 12) {
            if let characterIcon = victimCharacterIcon {
                Image(uiImage: characterIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image("default_char")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(spacing: 2) {
                if let corpIcon = victimCorporationIcon {
                    Image(uiImage: corpIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if let allyId = v.alliance_id, allyId > 0, let allyIcon = victimAllianceIcon {
                    Image(uiImage: allyIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let charId = v.character_id {
                    Text(detailData.characterName(for: charId))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(detailData.corporationName(for: v.corporation_id))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let allyId = v.alliance_id, allyId > 0 {
                    Text(detailData.allianceName(for: allyId))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .contextMenu {
                if let charId = v.character_id {
                    NavigationLink {
                        navigationDestination(for: charId, type: "character")
                    } label: {
                        Label(NSLocalizedString("View Character", comment: ""), systemImage: "info.circle")
                    }
                }
                if v.corporation_id > 0 {
                    NavigationLink {
                        navigationDestination(for: v.corporation_id, type: "corporation")
                    } label: {
                        Label(NSLocalizedString("View Corporation", comment: ""), systemImage: "info.circle")
                    }
                }
                if let allyId = v.alliance_id, allyId > 0 {
                    NavigationLink {
                        navigationDestination(for: allyId, type: "alliance")
                    } label: {
                        Label(NSLocalizedString("View Alliance", comment: ""), systemImage: "info.circle")
                    }
                }
            }

            Spacer()
        }
    }

    // 舰船信息行
    @ViewBuilder
    private func shipInfoRow(shipId: Int) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_Ship", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)

            HStack(spacing: 8) {
                if let shipIcon = shipIcon {
                    Image(uiImage: shipIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                VStack(alignment: .leading, spacing: 1) {
                    let shipInfo = getShipName(shipId)
                    Text(shipInfo.name)
                        .font(.caption)
                    Text(shipInfo.groupName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func systemInfoRowCompact(systemName: String, regionName: String, security: Double) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_System", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(formatSecurityStatus(security))
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundColor(getSecurityColor(security))
                    Text(solarSystemInfo?.systemName ?? systemName)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                Text(solarSystemInfo?.regionName ?? regionName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // 本地时间行
    @ViewBuilder
    private func localTimeRow(time: Int) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_Local_Time", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(formatLocalTime(time))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // 伤害量行
    @ViewBuilder
    private func DamageRow(dmg: Int) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_Damage", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(formatNumber(dmg))
                .font(.caption)
                .fontDesign(.monospaced)
                .fontWeight(.semibold)
            Spacer()
        }
    }

    // 总价值行
    @ViewBuilder
    private func TotalRow(total: Double) -> some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Main_KM_Total", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(FormatUtil.formatISK(total))
                .font(.caption)
                .fontDesign(.monospaced)
                .fontWeight(.semibold)
            Spacer()
        }
    }

    // 伤害和价值信息列表
    @ViewBuilder
    private func KmValueList() -> some View {
        // 摧毁价值
        HStack {
            Text(NSLocalizedString("Main_KM_Destroyed_Value", comment: ""))
                .font(.subheadline)
            Spacer()
            Text(FormatUtil.formatISK(destroyedValue))
                .font(.subheadline)
                .fontDesign(.monospaced)
                .foregroundColor(.red)
        }

        // 掉落价值
        HStack {
            Text(NSLocalizedString("Main_KM_Dropped_Value", comment: ""))
                .font(.subheadline)
            Spacer()
            Text(FormatUtil.formatISK(droppedValue))
                .font(.subheadline)
                .fontDesign(.monospaced)
                .foregroundColor(.green)
        }

        // 总价值
        HStack {
            Text(NSLocalizedString("Main_KM_Total", comment: ""))
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text(FormatUtil.formatISK(totalValue))
                .font(.subheadline)
                .fontDesign(.monospaced)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func victimInfoSection(detailData: KillMailDetailData) -> some View {
        let v = detailData.esi.victim
        HStack(spacing: 12) {
            if let characterIcon = victimCharacterIcon {
                Image(uiImage: characterIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image("default_char")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 66, height: 66)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(spacing: 2) {
                if let corpIcon = victimCorporationIcon {
                    Image(uiImage: corpIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if let allyId = v.alliance_id, allyId > 0, let allyIcon = victimAllianceIcon {
                    Image(uiImage: allyIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if let charId = v.character_id {
                    Text(detailData.characterName(for: charId))
                        .font(.headline)
                }
                Text(detailData.corporationName(for: v.corporation_id))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let allyId = v.alliance_id, allyId > 0 {
                    Text(detailData.allianceName(for: allyId))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .contextMenu {
                if let charId = v.character_id {
                    NavigationLink {
                        navigationDestination(for: charId, type: "character")
                    } label: {
                        Label(NSLocalizedString("View Character", comment: ""), systemImage: "info.circle")
                    }
                }
                if v.corporation_id > 0 {
                    NavigationLink {
                        navigationDestination(for: v.corporation_id, type: "corporation")
                    } label: {
                        Label(NSLocalizedString("View Corporation", comment: ""), systemImage: "info.circle")
                    }
                }
                if let allyId = v.alliance_id, allyId > 0 {
                    NavigationLink {
                        navigationDestination(for: allyId, type: "alliance")
                    } label: {
                        Label(NSLocalizedString("View Alliance", comment: ""), systemImage: "info.circle")
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    @ViewBuilder
    private func basicInfoRows(detailData: KillMailDetailData) -> some View {
        let shipId = detailData.esi.victim.ship_type_id
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

        if let sys = detailData.system {
            HStack {
                Text(NSLocalizedString("Main_KM_System", comment: ""))
                    .frame(width: 110, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .center)
                VStack(alignment: .leading) {
                    HStack {
                        Text(formatSecurityStatus(sys.security))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(getSecurityColor(sys.security))
                        Text(solarSystemInfo?.systemName ?? sys.systemName)
                            .fontWeight(.semibold)
                    }
                    Text(solarSystemInfo?.regionName ?? sys.regionName)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .contextMenu {
                let systemName = solarSystemInfo?.systemName ?? sys.systemName
                if !systemName.isEmpty {
                    Button {
                        UIPasteboard.general.string = systemName
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy_Location", comment: ""),
                            systemImage: "location"
                        )
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }

        // Local Time
        HStack {
            Text(NSLocalizedString("Main_KM_Local_Time", comment: ""))
                .frame(width: 110, alignment: .leading)
            if let time = detailData.timestamp {
                Text(formatLocalTime(time))
                    .foregroundColor(.secondary)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

        // Damage
        HStack {
            Text(NSLocalizedString("Main_KM_Damage", comment: ""))
                .frame(width: 110, alignment: .leading)
            Text(formatNumber(detailData.esi.victim.damage_taken))
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
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

        // 参与者（attackers）
        NavigationLink {
            KillMailAttackersView(detailData: detailData, character: character)
        } label: {
            HStack {
                Text(NSLocalizedString("Main_KM_Attackers", comment: ""))
                    .frame(width: 110, alignment: .leading)
                Spacer()
                Text("\(detailData.attackers.count)")
                    .foregroundColor(.secondary)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    /// 装配列表：先按 flag（槽位）升序，同一 flag 内先列装备（category≠8），再列弹药（8）；未知类型视为非弹药
    private func sortFittingItemsBySlotThenNonAmmoFirst(_ rows: [[Int]]) -> [[Int]] {
        rows.sorted { a, b in
            if a[0] != b[0] { return a[0] < b[0] }
            let aAmmo = itemInfoCache[a[1]]?.categoryID == 8
            let bAmmo = itemInfoCache[b[1]]?.categoryID == 8
            if aAmmo != bAmmo { return !aAmmo }
            return a[1] < b[1]
        }
    }

    @ViewBuilder
    private func fittingInfoSections(detail: KillMailDetailData) -> some View {
        let items = detail.convertedItemsForFitting
        if !items.isEmpty {
            // 获取所有植入体
            let implantItems = sortFittingItemsBySlotThenNonAmmoFirst(
                items.filter { $0[0] == 89 && $0.count >= 4 })
            if !implantItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_KM_Implants", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(implantItems, id: \.self) { item in
                        let typeId = item[1]
                        if item[2] > 0 { // 掉落数量
                            ItemRow(
                                typeId: typeId, quantity: item[2], isDropped: true,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                        if item[3] > 0 { // 摧毁数量
                            ItemRow(
                                typeId: typeId, quantity: item[3], isDropped: false,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 高槽
            let highSlotItems = sortFittingItemsBySlotThenNonAmmoFirst(items.filter { item in
                (27 ... 34).contains(item[0]) && item.count >= 4
            })

            if !highSlotItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_KM_High_Slots", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(highSlotItems, id: \.self) { item in
                        let typeId = item[1]
                        if item[2] > 0 { // 掉落数量
                            ItemRow(
                                typeId: typeId, quantity: item[2], isDropped: true,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                        if item[3] > 0 { // 摧毁数量
                            ItemRow(
                                typeId: typeId, quantity: item[3], isDropped: false,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 中槽
            let mediumSlotItems = sortFittingItemsBySlotThenNonAmmoFirst(items.filter { item in
                (19 ... 26).contains(item[0]) && item.count >= 4
            })

            if !mediumSlotItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_KM_Medium_Slots", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(mediumSlotItems, id: \.self) { item in
                        let typeId = item[1]
                        if item[2] > 0 { // 掉落数量
                            ItemRow(
                                typeId: typeId, quantity: item[2], isDropped: true,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                        if item[3] > 0 { // 摧毁数量
                            ItemRow(
                                typeId: typeId, quantity: item[3], isDropped: false,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 低槽
            let lowSlotItems = sortFittingItemsBySlotThenNonAmmoFirst(items.filter { item in
                (11 ... 18).contains(item[0]) && item.count >= 4
            })

            if !lowSlotItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_KM_Low_Slots", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(lowSlotItems, id: \.self) { item in
                        let typeId = item[1]
                        if item[2] > 0 { // 掉落数量
                            ItemRow(
                                typeId: typeId, quantity: item[2], isDropped: true,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                        if item[3] > 0 { // 摧毁数量
                            ItemRow(
                                typeId: typeId, quantity: item[3], isDropped: false,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 改装槽
            let rigSlotItems = items.filter { item in
                (92 ... 94).contains(item[0]) && item.count >= 4
            }.sorted { $0[0] < $1[0] } // 按槽位顺序排序

            if !rigSlotItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_KM_Rig_Slots", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(rigSlotItems, id: \.self) { item in
                        let typeId = item[1]
                        if item[2] > 0 { // 掉落数量
                            ItemRow(
                                typeId: typeId, quantity: item[2], isDropped: true,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                        if item[3] > 0 { // 摧毁数量
                            ItemRow(
                                typeId: typeId, quantity: item[3], isDropped: false,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 子系统槽
            let subsystemSlotItems = items.filter { item in
                (125 ... 128).contains(item[0]) && item.count >= 4
            }.sorted { $0[0] < $1[0] } // 按槽位顺序排序

            if !subsystemSlotItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_KM_Subsystem_Slots", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(subsystemSlotItems, id: \.self) { item in
                        let typeId = item[1]
                        if item[2] > 0 { // 掉落数量
                            ItemRow(
                                typeId: typeId, quantity: item[2], isDropped: true,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                        if item[3] > 0 { // 摧毁数量
                            ItemRow(
                                typeId: typeId, quantity: item[3], isDropped: false,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 战斗机发射管
            let fighterTubeItems = items.filter { item in
                (159 ... 163).contains(item[0]) && item.count >= 4
            }.sorted { $0[0] < $1[0] } // 按槽位顺序排序

            if !fighterTubeItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_KM_Fighter_Tubes", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(fighterTubeItems, id: \.self) { item in
                        let typeId = item[1]
                        if item[2] > 0 { // 掉落数量
                            ItemRow(
                                typeId: typeId, quantity: item[2], isDropped: true,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                        if item[3] > 0 { // 摧毁数量
                            ItemRow(
                                typeId: typeId, quantity: item[3], isDropped: false,
                                itemInfoCache: itemInfoCache,
                                resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                            )
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 获取所有非装配槽位的物品，按flag分组
            let nonFittingItems = items.filter { item in
                // 排除装配槽位的物品
                !(11 ... 18).contains(item[0]) // 低槽
                    && !(19 ... 26).contains(item[0]) // 中槽
                    && !(27 ... 34).contains(item[0]) // 高槽
                    && !(92 ... 94).contains(item[0]) // 改装槽
                    && !(125 ... 128).contains(item[0]) // 子系统槽
                    && !(159 ... 163).contains(item[0]) // 战斗机发射管
                    && item[0] != 89 // 植入体
            }

            // 获取所有可能的 flag（ESI 格式无 cnts，仅从 items 获取）
            let allFlags = Set(nonFittingItems.map { $0[0] }).sorted()

            ForEach(allFlags, id: \.self) { flag in
                let flagItems = nonFittingItems.filter { $0[0] == flag }

                if !flagItems.isEmpty {
                    Section(
                        header: Text(getFlagName(flag))
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        // 显示直接在该舱室的物品
                        ForEach(flagItems, id: \.self) { item in
                            let typeId = item[1]
                            if item[2] > 0 { // 掉落数量
                                ItemRow(
                                    typeId: typeId, quantity: item[2], isDropped: true,
                                    itemInfoCache: itemInfoCache,
                                    resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                                )
                            }
                            if item[3] > 0 { // 摧毁数量
                                ItemRow(
                                    typeId: typeId, quantity: item[3], isDropped: false,
                                    itemInfoCache: itemInfoCache,
                                    resolvedUnitPrice: kmMarketUnitPriceByType[typeId]
                                )
                            }
                        }
                    }.listRowInsets(
                        EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
    }

    // MARK: - 方向变化通知处理

    // 设置方向变化通知
    private func setupOrientationNotification() {
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.orientation = UIDevice.current.orientation

            // 只有当布局模式真正发生变化时才更新layoutMode
            let newLayoutMode = DeviceUtils.currentLayoutMode
            if DeviceUtils.shouldUpdateLayout(from: self.layoutMode, to: newLayoutMode) {
                Logger.debug("布局模式变化: \(self.layoutMode.rawValue) -> \(newLayoutMode.rawValue)")
                self.layoutMode = newLayoutMode
            }
        }
    }

    // 移除方向变化通知
    private func removeOrientationNotification() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    // MARK: - 原有的辅助函数

    @MainActor
    private func loadBRKillMailDetail() async {
        isLoading = true
        kmMarketPriceSession += 1
        let priceSession = kmMarketPriceSession
        kmMarketUnitPriceByType = [:]
        defer { isLoading = false }

        do {
            let killId = listEntity.killmailId
            let hash = listEntity.zkb.hash
            Logger.debug("开始加载战报ID \(killId) 的详细信息")

            let detail = try await KillMailDataConverter.shared.fetchKillMailDetail(
                killmailId: killId,
                hash: hash,
                zkb: listEntity.zkb
            )

            if let zkb = detail.zkb { zkbInfoFromAPI = zkb }

            loadAllItemInfo(from: detail)
            await loadIcons(from: detail)

            solarSystemInfo = await getSolarSystemInfo(
                solarSystemId: detail.esi.solar_system_id,
                databaseManager: DatabaseManager.shared
            )

            let zkb = zkbInfoFromAPI ?? listEntity.zkb
            fittedValue = zkb.fittedValueValue
            droppedValue = zkb.droppedValueValue
            destroyedValue = zkb.destroyedValueValue
            totalValue = zkb.totalValueValue
            detailData = detail

            let priceTypeIds = collectKillMailPriceTypeIds(detail)
            Task {
                await applyKillMailMarketPrices(typeIds: priceTypeIds, session: priceSession)
            }
        } catch {
            Logger.error("加载战斗日志详情失败: \(error)")
            errorMessage = "加载失败: \(error.localizedDescription)"
        }
    }

    private func collectKillMailPriceTypeIds(_ detail: KillMailDetailData) -> [Int] {
        var typeIds = Set<Int>()
        typeIds.insert(detail.esi.victim.ship_type_id)
        for item in detail.convertedItemsForFitting where item.count >= 2 {
            typeIds.insert(item[1])
        }
        return Array(typeIds)
    }

    private func applyKillMailMarketPrices(typeIds: [Int], session: Int) async {
        guard !typeIds.isEmpty else { return }
        let marketPrices = await MarketPriceUtil.getMarketPrices(typeIds: typeIds)
        Logger.debug("战报详情: 市场价格批量获取完成，写入 \(marketPrices.count)/\(typeIds.count) 条")
        for typeId in typeIds.sorted() {
            let unit = marketPrices[typeId]?.averagePrice ?? 0
            await MainActor.run {
                guard session == kmMarketPriceSession else { return }
                kmMarketUnitPriceByType[typeId] = unit
            }
            await Task.yield()
        }
    }

    @MainActor
    private func loadIcons(from detail: KillMailDetailData) async {
        if let charId = detail.esi.victim.character_id {
            do {
                victimCharacterIcon = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: charId,
                    size: 128
                )
            } catch {
                Logger.error("加载角色头像失败: \(error)")
            }
        }

        let corpId = detail.esi.victim.corporation_id
        do {
            victimCorporationIcon = try await CorporationAPI.shared.fetchCorporationLogo(
                corporationId: corpId,
                size: 64
            )
        } catch {
            Logger.error("加载军团图标失败: \(error)")
        }

        if let allyId = detail.esi.victim.alliance_id, allyId > 0 {
            do {
                victimAllianceIcon = try await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: allyId,
                    size: 64
                )
            } catch {
                Logger.error("加载联盟图标失败: \(error)")
            }
        }

        let shipId = detail.esi.victim.ship_type_id
        Task {
            do {
                let image = try await ItemRenderAPI.shared.fetchItemRender(
                    typeId: shipId, size: 64
                )
                await MainActor.run {
                    shipIcon = image
                }
            } catch {
                Logger.error("击毁详情: 加载舰船图标失败 - \(error)")
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

    private func openZKillboard(killId: Int) {
        if let url = URL(string: "https://zkillboard.com/kill/\(killId)/") {
            UIApplication.shared.open(url)
        }
    }

    private func getFlagName(_ flag: Int) -> String {
        return FlagMapping.getFlagName(for: flag)
    }

    private func loadAllItemInfo(from detail: KillMailDetailData) {
        var typeIds = Set<Int>()
        typeIds.insert(detail.esi.victim.ship_type_id)
        for item in detail.convertedItemsForFitting where item.count >= 4 {
            typeIds.insert(item[1])
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
    let isDropped: Bool // 是否为掉落物品
    let itemInfoCache: [Int: (name: String, iconFileName: String, categoryID: Int)]
    /// 已解析的单价；`nil` 表示价格仍在加载，显示占位指示器
    let resolvedUnitPrice: Double?

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
                        priceCaptionLine
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
                    priceCaptionLine
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

    @ViewBuilder
    private var priceCaptionLine: some View {
        if let unit = resolvedUnitPrice {
            Text(FormatUtil.formatISK(unit * Double(quantity)))
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.85)
                .frame(height: 14)
        }
    }
}

// MARK: - 仅 kill ID 时的加载器（用于 killreport 链接等场景）

struct KillMailDetailLoaderView: View {
    let killmailId: Int
    let character: EVECharacterInfo?
    @State private var listEntity: KillMailListEntity?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let entity = listEntity {
                BRKillMailDetailView(listEntity: entity, character: character)
            } else if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .task {
            await loadEntity()
        }
    }

    private func loadEntity() async {
        do {
            let zkbEntry = try await zKbToolAPI.shared.fetchZKBKillMailByID(killmailId: killmailId)
            let detail = try await KillMailDataConverter.shared.fetchKillMailDetail(
                killmailId: killmailId,
                hash: zkbEntry.zkb.hash,
                zkb: zkbEntry.zkb
            )
            let timestamp = detail.timestamp ?? 0
            let entity = KillMailListEntity(
                killmailId: killmailId,
                timestamp: timestamp,
                zkb: zkbEntry.zkb,
                victim: detail.esi.victim,
                names: detail.names,
                system: detail.system
            )
            await MainActor.run {
                listEntity = entity
            }
        } catch {
            Logger.error("加载战斗日志失败 - killmail_id: \(killmailId), error: \(error)")
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 参与者（attackers）页面

/// 用于 ForEach 的稳定 id，避免搜索过滤时视图复用导致头像/图标错位
private struct AttackerRowItem: Identifiable {
    let attacker: ESIAttacker
    let id: String // section 前缀 + 原始索引，确保跨 section 唯一
    init(attacker: ESIAttacker, stableId: Int, section: String) {
        self.attacker = attacker
        id = "\(section)_\(stableId)"
    }
}

struct KillMailAttackersView: View {
    let detailData: KillMailDetailData
    let character: EVECharacterInfo?
    @State private var searchText = ""
    /// 参与者页按需加载的实体名称（与 `detailData.names` 合并后展示；受害者名称以详情中为准）
    @State private var supplementalAttackerNames: [Int: String] = [:]

    /// 搜索关键词（至少2字符才生效）
    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        searchQuery.count >= 2
    }

    /// 详情中已解析名称 + 参与者页补充名称（同 id 以详情为准）
    private var mergedEntityNames: [Int: String] {
        supplementalAttackerNames.merging(detailData.names) { _, fromDetail in fromDetail }
    }

    /// 参与者是否匹配搜索（人物名、军团名、联盟名）
    private func attackerMatchesSearch(_ atk: ESIAttacker) -> Bool {
        guard isSearchActive else { return true }
        let q = searchQuery.lowercased()
        let m = mergedEntityNames
        let charName = atk.character_id.map { m[$0] ?? "Character \($0)" } ?? ""
        let corpName = atk.corporation_id.map { m[$0] ?? "Corporation \($0)" } ?? ""
        let allyName = (atk.alliance_id ?? 0) > 0 ? (m[atk.alliance_id!] ?? "Alliance \(atk.alliance_id!)") : ""
        return charName.localizedCaseInsensitiveContains(q)
            || corpName.localizedCaseInsensitiveContains(q)
            || allyName.localizedCaseInsensitiveContains(q)
    }

    /// 最后一击：final_blow == true
    private var finalBlowAttackers: [ESIAttacker] {
        detailData.attackers.filter { $0.final_blow }
    }

    /// 最多伤害：damage_done 最高者，同值按 character_id 排序
    private var mostDamageAttackers: [ESIAttacker] {
        let attackers = detailData.attackers
        guard let maxDmg = attackers.map(\.damage_done).max(), maxDmg > 0 else { return [] }
        return attackers
            .filter { $0.damage_done == maxDmg }
            .sorted { sortKey($0) < sortKey($1) }
    }

    /// 我的击杀：当前登录角色参与的参与者
    private var myAttackers: [ESIAttacker] {
        guard let myCharId = character?.CharacterID else { return [] }
        return detailData.attackers
            .filter { $0.character_id == myCharId }
            .sorted { a, b in
                if a.damage_done != b.damage_done { return a.damage_done > b.damage_done }
                return sortKey(a) < sortKey(b)
            }
    }

    /// 所有人：按 damage_done 降序，次按 character_id
    private var allAttackers: [ESIAttacker] {
        detailData.attackers.sorted { a, b in
            if a.damage_done != b.damage_done { return a.damage_done > b.damage_done }
            return sortKey(a) < sortKey(b)
        }
    }

    /// 应用搜索过滤后的列表
    private var filteredMyAttackers: [ESIAttacker] { myAttackers.filter(attackerMatchesSearch) }
    private var filteredFinalBlowAttackers: [ESIAttacker] { finalBlowAttackers.filter(attackerMatchesSearch) }
    private var filteredMostDamageAttackers: [ESIAttacker] { mostDamageAttackers.filter(attackerMatchesSearch) }
    private var filteredAllAttackers: [ESIAttacker] { allAttackers.filter(attackerMatchesSearch) }

    private var totalDamageDone: Int {
        detailData.attackers.reduce(0) { $0 + $1.damage_done }
    }

    private func sortKey(_ a: ESIAttacker) -> Int {
        a.character_id ?? a.corporation_id ?? a.alliance_id ?? 0
    }

    /// 获取 attacker 在原始列表中的索引，作为 ForEach 的稳定 id，避免过滤时视图复用导致头像错位
    private func attackerStableId(_ atk: ESIAttacker) -> Int {
        detailData.attackers.firstIndex { a in
            a.character_id == atk.character_id
                && a.corporation_id == atk.corporation_id
                && a.alliance_id == atk.alliance_id
                && a.ship_type_id == atk.ship_type_id
                && a.weapon_type_id == atk.weapon_type_id
                && a.damage_done == atk.damage_done
                && a.final_blow == atk.final_blow
        } ?? -1
    }

    var body: some View {
        let total = totalDamageDone
        let nameMap = mergedEntityNames
        List {
            if !filteredMyAttackers.isEmpty {
                Section(NSLocalizedString("Main_KM_Attackers_My_Kills", comment: "")) {
                    ForEach(filteredMyAttackers.map { AttackerRowItem(attacker: $0, stableId: attackerStableId($0), section: "my") }) { item in
                        AttackerRowView(
                            attacker: item.attacker, entityNameMap: nameMap,
                            totalDamageDone: total, character: character
                        )
                    }
                }
            }
            if !filteredFinalBlowAttackers.isEmpty {
                Section(NSLocalizedString("Main_KM_Attackers_Final_Blow", comment: "")) {
                    ForEach(filteredFinalBlowAttackers.map { AttackerRowItem(attacker: $0, stableId: attackerStableId($0), section: "final") }) { item in
                        AttackerRowView(
                            attacker: item.attacker, entityNameMap: nameMap,
                            totalDamageDone: total, character: character
                        )
                    }
                }
            }
            if !filteredMostDamageAttackers.isEmpty {
                Section(NSLocalizedString("Main_KM_Attackers_Most_Damage", comment: "")) {
                    ForEach(filteredMostDamageAttackers.map { AttackerRowItem(attacker: $0, stableId: attackerStableId($0), section: "damage") }) { item in
                        AttackerRowView(
                            attacker: item.attacker, entityNameMap: nameMap,
                            totalDamageDone: total, character: character
                        )
                    }
                }
            }
            Section(String(format: NSLocalizedString("Main_KM_Attackers_All_With_Count", comment: ""), filteredAllAttackers.count)) {
                if filteredAllAttackers.isEmpty && isSearchActive {
                    Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(filteredAllAttackers.map { AttackerRowItem(attacker: $0, stableId: attackerStableId($0), section: "all") }) { item in
                        AttackerRowView(
                            attacker: item.attacker, entityNameMap: nameMap,
                            totalDamageDone: total, character: character
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: NSLocalizedString("Main_KM_Attackers_Search_Placeholder", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("")
        .task {
            await loadAttackerEntityNamesIfNeeded()
        }
    }

    /// 仅查询参与者相关且详情中尚未有的实体名称（触发 `universe_names` 等）
    private func loadAttackerEntityNamesIfNeeded() async {
        var ids = Set<Int>()
        for atk in detailData.attackers {
            if let c = atk.character_id { ids.insert(c) }
            if let c = atk.corporation_id { ids.insert(c) }
            if let a = atk.alliance_id, a > 0 { ids.insert(a) }
        }
        let missing = ids.filter { detailData.names[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            let fetched = try await UniverseAPI.shared.getNamesWithFallback(ids: Array(missing))
            await MainActor.run {
                var merged = supplementalAttackerNames
                for (id, pair) in fetched {
                    merged[id] = pair.name
                }
                supplementalAttackerNames = merged
            }
        } catch {
            Logger.error("战报参与者: 批量解析名称失败 - \(error)")
        }
    }
}

// MARK: - 参与者行视图

private struct AttackerRowView: View {
    let attacker: ESIAttacker
    /// 角色/军团/联盟 id → 名称（含详情预取 + 参与者页补充）
    let entityNameMap: [Int: String]
    let totalDamageDone: Int
    let character: EVECharacterInfo?
    @State private var characterPortrait: UIImage?
    @State private var resolvedShipName: String? // 未知参与者时，从数据库查询 ship_type_id 的 name

    private var damagePercentage: String {
        guard totalDamageDone > 0 else { return "0%" }
        let pct = Double(attacker.damage_done) / Double(totalDamageDone) * 100
        return String(format: "%.1f%%", pct)
    }

    private func formatDamage(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// 是否为“未知”参与者（无 character/alliance/corporation 信息）
    private var isUnknownParticipant: Bool {
        attacker.character_id == nil
            && (attacker.alliance_id == nil || attacker.alliance_id == 0)
            && attacker.corporation_id == nil
    }

    private var displayName: String {
        if let id = attacker.character_id { return entityNameMap[id] ?? "Character \(id)" }
        if let id = attacker.alliance_id, id > 0 { return entityNameMap[id] ?? "Alliance \(id)" }
        if let id = attacker.corporation_id { return entityNameMap[id] ?? "Corporation \(id)" }
        return NSLocalizedString("Unknown", comment: "")
    }

    /// 最终显示名称：未知参与者时优先显示 ship_type_id 的 name
    private var displayNameText: String {
        if isUnknownParticipant, let name = resolvedShipName, !name.isEmpty {
            return name
        }
        return displayName
    }

    private var corporationName: String {
        guard let id = attacker.corporation_id else { return "-" }
        return entityNameMap[id] ?? "Corporation \(id)"
    }

    private var allianceName: String {
        guard let id = attacker.alliance_id, id > 0 else { return "-" }
        return entityNameMap[id] ?? "Alliance \(id)"
    }

    /// 上方图标：优先 ship_type_id，缺失时用 weapon_type_id 替代
    private var shipIconName: String {
        let typeId = attacker.ship_type_id ?? attacker.weapon_type_id
        guard let id = typeId else { return "not_found" }
        return DatabaseManager.shared.getItemIconFileName(for: id) ?? "not_found"
    }

    /// 下方图标：优先 weapon_type_id，缺失时用 ship_type_id 替代
    private var weaponIconName: String {
        let typeId = attacker.weapon_type_id ?? attacker.ship_type_id
        guard let id = typeId else { return "not_found" }
        return DatabaseManager.shared.getItemIconFileName(for: id) ?? "not_found"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            // 左侧头像 64x64
            (characterPortrait.map { Image(uiImage: $0) } ?? Image("default_char"))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // 头像右侧：上下两个 32x32 图标
            VStack(spacing: 2) {
                Image(uiImage: IconManager.shared.loadUIImage(for: shipIconName))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Image(uiImage: IconManager.shared.loadUIImage(for: weaponIconName))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // 中间三行文字
            VStack(alignment: .leading, spacing: 4) {
                Text(displayNameText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(corporationName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(allianceName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧：damage_done 及占比
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDamage(attacker.damage_done))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .font(.system(.body, design: .monospaced))
                Text(damagePercentage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .contextMenu {
            if let charId = attacker.character_id, character != nil {
                NavigationLink {
                    CharacterDetailView(characterId: charId, character: character!)
                } label: {
                    Label(NSLocalizedString("View Character", comment: ""), systemImage: "info.circle")
                }
            }
            if let corpId = attacker.corporation_id, character != nil {
                NavigationLink {
                    CorporationDetailView(corporationId: corpId, character: character!)
                } label: {
                    Label(NSLocalizedString("View Corporation", comment: ""), systemImage: "info.circle")
                }
            }
            if let allyId = attacker.alliance_id, allyId > 0, character != nil {
                NavigationLink {
                    AllianceDetailView(allianceId: allyId, character: character!)
                } label: {
                    Label(NSLocalizedString("View Alliance", comment: ""), systemImage: "info.circle")
                }
            }
            if let shipTypeId = attacker.ship_type_id ?? attacker.weapon_type_id {
                NavigationLink {
                    ItemInfoMap.getItemInfoView(itemID: shipTypeId, databaseManager: DatabaseManager.shared)
                } label: {
                    Label(NSLocalizedString("View Ship", comment: ""), systemImage: "info.circle")
                }
            }
        }
        .task {
            if let charId = attacker.character_id {
                do {
                    let img = try await CharacterAPI.shared.fetchCharacterPortrait(characterId: charId, size: 128)
                    await MainActor.run { characterPortrait = img }
                } catch {
                    Logger.error("加载参与者头像失败 - character_id: \(charId), error: \(error)")
                }
            }
        }
        .task(id: "\(attacker.ship_type_id ?? 0)_\(attacker.weapon_type_id ?? 0)") {
            guard isUnknownParticipant else { return }
            guard let typeId = attacker.ship_type_id ?? attacker.weapon_type_id else { return }
            let name = Self.queryTypeName(typeId: typeId)
            await MainActor.run { resolvedShipName = name }
        }
    }

    /// 从数据库查询 type_id 对应的 name
    private static func queryTypeName(typeId: Int) -> String? {
        let query = "SELECT name FROM types WHERE type_id = ?"
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let name = row["name"] as? String,
           !name.isEmpty
        {
            return name
        }
        return nil
    }
}
