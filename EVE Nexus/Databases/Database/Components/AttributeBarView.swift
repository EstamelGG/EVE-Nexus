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
            color: Color(red: 74/255, green: 128/255, blue: 192/255)    // EM - 蓝色
        ),
        ResistanceType(
            id: 1,
            iconName: "anti_th",
            color: Color(red: 176/255, green: 53/255, blue: 50/255)    // Thermal - 红色
        ),
        ResistanceType(
            id: 2,
            iconName: "anti_ki",
            color: Color(red: 155/255, green: 155/255, blue: 155/255)   // Kinetic - 灰色
        ),
        ResistanceType(
            id: 3,
            iconName: "anti_ex",
            color: Color(red: 185/255, green: 138/255, blue: 62/255)    // Explosive - 橙色
        )
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
                                .saturation(1.2)     // 增加饱和度
                                .brightness(0.1)     // 增加亮度
                                .frame(width: geometry.size.width * CGFloat(resistances[type.id]) / 100)
                        }
                    }
                    .frame(height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            //.stroke(type.color, lineWidth: 1.5)
                            .stroke(type.color, lineWidth: 0)
                            .saturation(1.2)     // 增加饱和度
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
    let isSimplifiedMode: Bool
    
    // 检查是否是可跳转的属性
    private var isNavigable: Bool {
        attribute.unitID == 115 || attribute.unitID == 116 // 只有 groupID 和 typeID 可以跳转
    }
    
    // 获取目标视图
    private var navigationDestination: AnyView? {
        guard let value = allAttributes[attribute.id] else { return nil }
        let id = Int(value)
        
        if attribute.unitID == 115 { // groupID
            let groupName = databaseManager.getGroupName(for: id) ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
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
            return databaseManager.getGroupName(for: id) ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
        } else if attribute.unitID == 116 { // typeID
            return databaseManager.getTypeName(for: id) ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
        } else if attribute.unitID == 119 { // attributeID
            return databaseManager.getAttributeName(for: id) ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
        }
        return ""
    }
    
    // 获取格式化后的显示值
    private var formattedValue: String {
        let result = AttributeDisplayConfig.transformValue(attribute.id, allAttributes: allAttributes, unitID: attribute.unitID)
        switch result {
        case .number(let value, let unit):
            if attribute.unitID == 115 || attribute.unitID == 116 {
                return ""
            }
            return unit.map { "\(FormatUtil.format(value))\($0)" } ?? FormatUtil.format(value)
        case .text(let str):
            return str
        case .resistance:
            return ""
        }
    }
    
    var body: some View {
        if AttributeDisplayConfig.shouldShowAttribute(attribute.id, attribute: attribute, isSimplifiedMode: isSimplifiedMode) {
            let result = AttributeDisplayConfig.transformValue(attribute.id, allAttributes: allAttributes, unitID: attribute.unitID)
            
            switch result {
            case .resistance(let resistances):
                ResistanceBarView(resistances: resistances)
            default:
                defaultAttributeView
            }
        }
    }
    
    private var defaultAttributeView: some View {
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
                Text(formattedValue)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
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
    let isSimplifiedMode: Bool
    let damageAttributeIDs = [114, 118, 117, 116]
    private var filteredAttributes: [DogmaAttribute] {
        group.attributes
            .filter { attribute in
                // 始终隐藏武器伤害属性
                
                if damageAttributeIDs.contains(attribute.id) {
                    return false
                }
                
                return AttributeDisplayConfig.shouldShowAttribute(attribute.id, attribute: attribute, isSimplifiedMode: isSimplifiedMode)
            }
            .sorted { attr1, attr2 in
                let order1 = AttributeDisplayConfig.getAttributeOrder(attributeID: attr1.id, in: group.id)
                let order2 = AttributeDisplayConfig.getAttributeOrder(attributeID: attr2.id, in: group.id)
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
        if AttributeDisplayConfig.shouldShowGroup(group.id) && 
           (filteredAttributes.count > 0 || 
            AttributeDisplayConfig.getResistanceValues(groupID: group.id, from: allAttributes) != nil || 
            (hasMissileAttribute && getMissileInfo() != nil) ||
            (hasWeaponDamageAttributes && getWeaponInfo() != nil)) {
            Section {
                // 检查是否有抗性值需要显示
                if let resistances = AttributeDisplayConfig.getResistanceValues(groupID: group.id, from: allAttributes) {
                    ResistanceBarView(resistances: resistances)
                }
                
                // 显示所有属性（包括507，受过滤影响）
                ForEach(filteredAttributes) { attribute in
                    AttributeItemView(
                        attribute: attribute,
                        allAttributes: allAttributes,
                        databaseManager: databaseManager,
                        isSimplifiedMode: isSimplifiedMode
                    )
                }
                
                // 只在包含507属性的组中显示导弹伤害信息
                if hasMissileAttribute {
                    missileInfoView()
                }
                
                // 显示武器伤害信息
                if hasWeaponDamageAttributes {
                    weaponDamageView()
                }
                
            } header: {
                Text(group.name)
                    .font(.headline)
            }
        }
    }
}

// 所有属性组的显示组件
struct AttributesView: View {
    let attributeGroups: [AttributeGroup]
    let typeID: Int
    @ObservedObject var databaseManager: DatabaseManager
    let isSimplifiedMode: Bool
    
    private var allAttributes: [Int: Double] {
        var dict: [Int: Double] = [:]
        for group in attributeGroups {
            for attribute in group.attributes {
                dict[attribute.id] = attribute.value
            }
        }
        return dict
    }
    
    private var sortedGroups: [AttributeGroup] {
        attributeGroups.sorted { group1, group2 in
            AttributeDisplayConfig.getGroupOrder(group1.id) < AttributeDisplayConfig.getGroupOrder(group2.id)
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
                // 技能要求组
                let requirements = SkillTreeManager.shared.getDeduplicatedSkillRequirements(for: typeID, databaseManager: databaseManager)
                if !requirements.isEmpty {
                    let totalPoints = requirements.reduce(0) { total, skill in
                        guard let multiplier = skill.timeMultiplier,
                              skill.level > 0 && skill.level <= SkillTreeManager.levelBasePoints.count else {
                            return total
                        }
                        let points = Int(Double(SkillTreeManager.levelBasePoints[skill.level - 1]) * multiplier)
                        return total + points
                    }
                    Section(header: Text("\(group.name) (\(FormatUtil.format(Double(totalPoints))) SP)").font(.headline)) {
                        ForEach(requirements, id: \.skillID) { requirement in
                            SkillRequirementRow(
                                skillID: requirement.skillID,
                                level: requirement.level,
                                timeMultiplier: requirement.timeMultiplier,
                                databaseManager: databaseManager
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            } else {
                AttributeGroupView(
                    group: group,
                    allAttributes: allAttributes,
                    typeID: typeID,
                    databaseManager: databaseManager,
                    isSimplifiedMode: isSimplifiedMode
                )
            }
        }
        
        // 添加衍生矿石列表
        if hasDerivativeOre, let value = derivativeOreValue {
            let items = databaseManager.getItemsByAttributeValue(attributeID: 2711, value: value)
            if !items.isEmpty {
                Section(header: Text(NSLocalizedString("Main_Ore_Variations", comment: "")).font(.headline)) {
                    ForEach(items, id: \.typeID) { item in
                        NavigationLink(destination: ShowItemInfo(databaseManager: databaseManager, itemID: item.typeID)) {
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
