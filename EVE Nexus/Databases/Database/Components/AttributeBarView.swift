import SwiftUI

// 抗性条显示组件
struct ResistanceBarView: View {
    let resistances: [Double]

    // 定义抗性类型
    private struct ResistanceType: Identifiable {
        let id: Int
        let iconName: String
        let color: Color
    }

    // 定义抗性类型数据
    private let resistanceTypes = [
        ResistanceType(
            id: 0,
            iconName: "anti_em",
            color: Color(red: 74 / 255, green: 128 / 255, blue: 192 / 255) // EM - 蓝色
        ),
        ResistanceType(
            id: 1,
            iconName: "anti_th",
            color: Color(red: 176 / 255, green: 53 / 255, blue: 50 / 255) // Thermal - 红色
        ),
        ResistanceType(
            id: 2,
            iconName: "anti_ki",
            color: Color(red: 155 / 255, green: 155 / 255, blue: 155 / 255) // Kinetic - 灰色
        ),
        ResistanceType(
            id: 3,
            iconName: "anti_ex",
            color: Color(red: 185 / 255, green: 138 / 255, blue: 62 / 255) // Explosive - 橙色
        ),
    ]

    // 获取格式化后的百分比值
    private func roundedPercentage(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return formatted.replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }

    var body: some View {
        VStack(spacing: 2) {
            // 图标和数值行
            HStack(spacing: 8) {
                ForEach(resistanceTypes) { type in
                    GeometryReader { geometry in
                        HStack(spacing: 2) {
                            // 图标
                            Image(type.iconName)
                                .resizable()
                                .frame(width: 20, height: 20)

                            // 数值
                            Text("\(roundedPercentage(resistances[type.id]))%")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()
                        }
                        .frame(width: geometry.size.width)
                    }
                }
            }
            .frame(height: 24)

            // 进度条行
            HStack(spacing: 8) {
                ForEach(resistanceTypes) { type in
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // 背景条 - 使用更深的相同色调
                            Rectangle()
                                .fill(type.color.opacity(0.8))
                                .overlay(Color.black.opacity(0.5))
                                .frame(width: geometry.size.width)

                            // 进度条 - 增加亮度和饱和度
                            Rectangle()
                                .fill(type.color)
                                .saturation(1.2) // 增加饱和度
                                .brightness(0.1) // 增加亮度
                                .frame(
                                    width: geometry.size.width * CGFloat(resistances[type.id]) / 100
                                )
                        }
                    }
                    .frame(height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            // .stroke(type.color, lineWidth: 1.5)
                            .stroke(type.color, lineWidth: 0)
                            .saturation(1.2) // 增加饱和度
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// 单个属性的显示组件
struct AttributeItemView: View {
    let attribute: DogmaAttribute
    let allAttributes: [Int: Double]
    @ObservedObject var databaseManager: DatabaseManager

    // 检查是否是可跳转的属性
    private var isNavigable: Bool {
        attribute.unitID == 115 || attribute.unitID == 116 // 只有 groupID 和 typeID 可以跳转
    }

    // 获取目标视图
    private var navigationDestination: AnyView? {
        guard let value = allAttributes[attribute.id] else { return nil }
        let id = Int(value)

        if attribute.unitID == 115 { // groupID
            let groupName =
                databaseManager.getGroupName(for: id)
                    ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
            return AnyView(
                DatabaseBrowserView(
                    databaseManager: databaseManager,
                    level: .items(groupID: id, groupName: groupName)
                )
            )
        } else if attribute.unitID == 116 { // typeID
            return AnyView(
                ShowItemInfo(
                    databaseManager: databaseManager,
                    itemID: id
                )
            )
        }
        return nil
    }

    // 获取显示名称
    private var displayName: String {
        guard let value = allAttributes[attribute.id] else { return "" }
        let id = Int(value)

        if attribute.unitID == 115 { // groupID
            return databaseManager.getGroupName(for: id)
                ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
        } else if attribute.unitID == 116 { // typeID
            return databaseManager.getTypeName(for: id)
                ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
        } else if attribute.unitID == 119 { // attributeID
            return databaseManager.getAttributeName(for: id)
                ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
        }
        return ""
    }

    // 获取格式化后的显示值
    private var formattedValue: String {
        let result = AttributeDisplayConfig.transformValue(
            attribute.id, allAttributes: allAttributes, unitID: attribute.unitID
        )
        switch result {
        case let .number(value, unit):
            if attribute.unitID == 115 || attribute.unitID == 116 {
                return ""
            }
            return unit.map { "\(FormatUtil.format(value))\($0)" } ?? FormatUtil.format(value)
        case let .text(str):
            return str
        case .resistance:
            return ""
        }
    }

    // 获取修改后的格式化显示值
    private var formattedModifiedValue: String? {
        guard let modifiedValue = attribute.modifiedValue else { return nil }

        // 创建临时字典用于格式化修改后的值
        var tempAttributes = allAttributes
        tempAttributes[attribute.id] = modifiedValue

        let result = AttributeDisplayConfig.transformValue(
            attribute.id, allAttributes: tempAttributes, unitID: attribute.unitID
        )
        switch result {
        case let .number(value, unit):
            if attribute.unitID == 115 || attribute.unitID == 116 {
                return ""
            }
            return unit.map { "\(FormatUtil.format(value))\($0)" } ?? FormatUtil.format(value)
        case let .text(str):
            return str
        case .resistance:
            return nil
        }
    }

    // 判断修改后的值是否更好
    private var isModifiedValueBetter: Bool? {
        guard let modifiedValue = attribute.modifiedValue else { return nil }
        let originalValue = attribute.value
        if originalValue == modifiedValue {
            return nil
        }
        if attribute.highIsGood {
            return modifiedValue > originalValue
        } else {
            return modifiedValue < originalValue
        }
    }

    // 获取修改后值的颜色
    private var modifiedValueColor: Color {
        guard let isBetter = isModifiedValueBetter else { return .secondary }
        return isBetter ? .green : .red
    }

    var body: some View {
        if AttributeDisplayConfig.shouldShowAttribute(attribute.id, attribute: attribute) {
            let result = AttributeDisplayConfig.transformValue(
                attribute.id, allAttributes: allAttributes, unitID: attribute.unitID
            )

            switch result {
            case let .resistance(resistances):
                ResistanceBarView(resistances: resistances)
            default:
                defaultAttributeView
            }
        }
    }

    private var defaultAttributeView: some View { // 最普通的属性展示
        HStack {
            if attribute.iconID != 0 {
                IconManager.shared.loadImage(for: attribute.iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
            }

            Text(attribute.displayTitle)
                .font(.body)

            Spacer()

            if attribute.unitID == 119 {
                Text(displayName)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)

            } else if isNavigable, let destination = navigationDestination {
                NavigationLink(destination: destination) {
                    HStack {
                        Spacer()
                        Text(displayName)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(minWidth: 100)
                }
                .buttonStyle(.plain)
            } else {
                // 如果有修改后的值，显示修改后的值，否则显示原始值
                if let modifiedFormattedValue = formattedModifiedValue {
                    Text(modifiedFormattedValue)
                        .font(.body)
                        .foregroundColor(modifiedValueColor)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(formattedValue)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

// 属性组的显示组件
struct AttributeGroupView: View {
    let group: AttributeGroup
    let allAttributes: [Int: Double]
    let typeID: Int
    @ObservedObject var databaseManager: DatabaseManager
    let damageAttributeIDs = [114, 118, 117, 116]
    private var filteredAttributes: [DogmaAttribute] {
        group.attributes
            .filter { attribute in
                // 始终隐藏武器伤害属性

                if damageAttributeIDs.contains(attribute.id) {
                    return false
                }

                return AttributeDisplayConfig.shouldShowAttribute(
                    attribute.id, attribute: attribute
                )
            }
            .sorted { attr1, attr2 in
                let order1 = AttributeDisplayConfig.getAttributeOrder(
                    attributeID: attr1.id, in: group.id
                )
                let order2 = AttributeDisplayConfig.getAttributeOrder(
                    attributeID: attr2.id, in: group.id
                )
                if order1 == order2 {
                    return attr1.id < attr2.id
                }
                return order1 < order2
            }
    }

    // 检查当前组是否包含507属性
    private var hasMissileAttribute: Bool {
        group.attributes.contains { $0.id == 507 }
    }

    // 检查当前组是否包含武器伤害属性
    private var hasWeaponDamageAttributes: Bool {
        return group.attributes.contains { damageAttributeIDs.contains($0.id) }
    }

    var body: some View {
        if AttributeDisplayConfig.shouldShowGroup(group.id)
            && (filteredAttributes.count > 0
                || AttributeDisplayConfig.getResistanceValues(
                    groupID: group.id, from: allAttributes
                ) != nil
                || (hasMissileAttribute && getMissileInfo() != nil)
                || (hasWeaponDamageAttributes && getWeaponInfo() != nil))
        {
            Section {
                // 检查是否有抗性值需要显示
                if let resistances = AttributeDisplayConfig.getResistanceValues(
                    groupID: group.id, from: allAttributes
                ) {
                    ResistanceBarView(resistances: resistances)
                }

                // 显示所有属性（包括507，受过滤影响）
                ForEach(filteredAttributes) { attribute in
                    AttributeItemView(
                        attribute: attribute,
                        allAttributes: allAttributes,
                        databaseManager: databaseManager
                    )
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // 只在包含507属性的组中显示导弹伤害信息
                if hasMissileAttribute {
                    missileInfoView().listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                    // 导弹DPH显示
                    if let dph = getMissileDPH() {
                        missileDPHView(dph: dph).listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 导弹DPS显示
                    if let dps = getMissileDPS() {
                        missileDPSView(dps: dps).listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 导弹射程显示
                    if let range = getMissileRange() {
                        missileRangeView(range: range).listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }

                // 显示武器伤害信息
                if hasWeaponDamageAttributes {
                    weaponDamageView().listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                    // 武器DPH显示
                    if let dph = getWeaponDPH() {
                        weaponDPHView(dph: dph).listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 武器DPS显示
                    if let dps = getWeaponDPS() {
                        weaponDPSView(dps: dps).listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }

            } header: {
                Text(group.name)
                    .font(.headline)
            }
        }
    }

    // 计算导弹DPH（每次命中伤害）
    private func getMissileDPH() -> Double? {
        // 获取导弹伤害信息
        guard let missileInfo = getMissileInfo() else { return nil }
        let totalDamage =
            missileInfo.actualDamages.em + missileInfo.actualDamages.therm
                + missileInfo.actualDamages.kin + missileInfo.actualDamages.exp

        return totalDamage > 0 ? totalDamage : nil
    }

    // 计算武器DPH（每次命中伤害）
    private func getWeaponDPH() -> Double? {
        // 获取武器伤害信息
        guard let weaponInfo = getWeaponInfo() else { return nil }
        let totalDamage =
            weaponInfo.actualDamages.em + weaponInfo.actualDamages.therm
                + weaponInfo.actualDamages.kin + weaponInfo.actualDamages.exp

        return totalDamage > 0 ? totalDamage : nil
    }

    // 计算导弹DPS
    private func getMissileDPS() -> Double? {
        guard let rateOfFire = allAttributes[506] else { return nil }
        if rateOfFire <= 0 { return nil }

        // 获取导弹伤害信息
        guard let missileInfo = getMissileInfo() else { return nil }
        let totalDamage =
            missileInfo.actualDamages.em + missileInfo.actualDamages.therm
                + missileInfo.actualDamages.kin + missileInfo.actualDamages.exp
        // actualDamages已经包含了属性64的倍增，不需要再乘一次

        return totalDamage / (rateOfFire / 1000.0) // 转换为秒
    }

    // 计算武器DPS
    private func getWeaponDPS() -> Double? {
        guard let rateOfFire = allAttributes[51] else { return nil }
        if rateOfFire <= 0 { return nil }

        // 获取武器伤害信息
        guard let weaponInfo = getWeaponInfo() else { return nil }
        let totalDamage =
            weaponInfo.actualDamages.em + weaponInfo.actualDamages.therm
                + weaponInfo.actualDamages.kin + weaponInfo.actualDamages.exp
        // actualDamages已经包含了属性64的倍增，不需要再乘一次

        return totalDamage / (rateOfFire / 1000.0) // 转换为秒
    }

    // 计算导弹射程
    // 如果飞行时间(281)或飞行速度(37)查不到，返回nil，射程将不显示
    private func getMissileRange() -> Double? {
        // 获取导弹信息
        guard let missileInfo = getMissileInfo() else { return nil }

        // 获取导弹基础属性
        // 如果飞行时间或飞行速度任何一个查不到，无法计算射程，返回nil
        guard let baseFlightTime = missileInfo.flightTime,
              let baseFlightSpeed = missileInfo.flightSpeed
        else {
            return nil
        }

        // 获取物品属性加成（645是速度加成，646是飞行时间加成）
        // 如果加成属性不存在，默认使用1.0（无加成）
        let speedMultiplier = allAttributes[645] ?? 1.0
        let timeMultiplier = allAttributes[646] ?? 1.0

        // 计算实际飞行速度和飞行时间
        let actualFlightSpeed = baseFlightSpeed * speedMultiplier // 米/秒
        let actualFlightTime = baseFlightTime * timeMultiplier // 毫秒

        // 计算射程：速度 × 时间（需要将毫秒转换为秒）
        let range = actualFlightSpeed * (actualFlightTime / 1000.0) // 米

        return range > 0 ? range : nil
    }

    // 导弹DPH显示视图
    @ViewBuilder
    private func missileDPHView(dph: Double) -> some View {
        HStack {
            Image("dps")
                .resizable()
                .frame(width: 32, height: 32)

            Text("DPH")
                .font(.body)

            Spacer()

            Text("\(FormatUtil.format(dph)) HP")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    // 武器DPH显示视图
    @ViewBuilder
    private func weaponDPHView(dph: Double) -> some View {
        HStack {
            Image("dps")
                .resizable()
                .frame(width: 32, height: 32)

            Text("DPH")
                .font(.body)

            Spacer()

            Text("\(FormatUtil.format(dph)) HP")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }

    // 导弹DPS显示视图
    @ViewBuilder
    private func missileDPSView(dps: Double) -> some View {
        HStack {
            Image("dps")
                .resizable()
                .frame(width: 32, height: 32)

            Text("DPS")
                .font(.body)

            Spacer()

            Text("\(FormatUtil.format(dps)) HP/s")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // 武器DPS显示视图
    @ViewBuilder
    private func weaponDPSView(dps: Double) -> some View {
        HStack {
            Image("dps")
                .resizable()
                .frame(width: 32, height: 32)

            Text("DPS")
                .font(.body)

            Spacer()

            Text("\(FormatUtil.format(dps)) HP/s")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // 导弹射程显示视图
    @ViewBuilder
    private func missileRangeView(range: Double) -> some View {
        HStack {
            Image("target_range")
                .resizable()
                .frame(width: 32, height: 32)

            Text(NSLocalizedString("Fitting_range", comment: "射程"))
                .font(.body)

            Spacer()

            Text("\(FormatUtil.format(range)) m")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

// 所有属性组的显示组件
struct AttributesView: View {
    let attributeGroups: [AttributeGroup]
    let typeID: Int
    @ObservedObject var databaseManager: DatabaseManager

    private var allAttributes: [Int: Double] {
        var dict: [Int: Double] = [:]
        for group in attributeGroups {
            for attribute in group.attributes {
                // 优先使用修改后的值，如果没有则使用原始值
                dict[attribute.id] = attribute.modifiedValue ?? attribute.value
            }
        }
        return dict
    }

    private var sortedGroups: [AttributeGroup] {
        attributeGroups.sorted { group1, group2 in
            AttributeDisplayConfig.getGroupOrder(group1.id)
                < AttributeDisplayConfig.getGroupOrder(group2.id)
        }
    }

    // 检查是否有衍生矿石属性
    private var hasDerivativeOre: Bool {
        for group in attributeGroups {
            for attribute in group.attributes {
                if attribute.id == 2711 {
                    return true
                }
            }
        }
        return false
    }

    // 获取衍生矿石属性值
    private var derivativeOreValue: Double? {
        for group in attributeGroups {
            for attribute in group.attributes {
                if attribute.id == 2711 {
                    return attribute.value
                }
            }
        }
        return nil
    }

    var body: some View {
        ForEach(sortedGroups) { group in
            if group.id == 8 {
                SkillRequirementsView(
                    typeID: typeID, groupName: group.name, databaseManager: databaseManager
                )
            } else {
                AttributeGroupView(
                    group: group,
                    allAttributes: allAttributes,
                    typeID: typeID,
                    databaseManager: databaseManager
                )
            }
        }

        // 添加衍生矿石列表
        if hasDerivativeOre, let value = derivativeOreValue {
            let items = databaseManager.getItemsByAttributeValue(attributeID: 2711, value: value)
            if !items.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_Ore_Variations", comment: "")).font(
                        .headline)
                ) {
                    ForEach(items, id: \.typeID) { item in
                        NavigationLink(
                            destination: ShowItemInfo(
                                databaseManager: databaseManager, itemID: item.typeID
                            )
                        ) {
                            HStack {
                                IconManager.shared.loadImage(for: item.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                Text(item.name)
                                    .foregroundColor(.primary)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
    }
}
