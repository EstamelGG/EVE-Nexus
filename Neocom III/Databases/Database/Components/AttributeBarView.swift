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
            iconName: "items_22_32_20.png",
            color: Color(red: 74/255, green: 128/255, blue: 192/255)    // EM - 蓝色
        ),
        ResistanceType(
            id: 1,
            iconName: "items_22_32_18.png",
            color: Color(red: 176/255, green: 53/255, blue: 50/255)    // Thermal - 红色
        ),
        ResistanceType(
            id: 2,
            iconName: "items_22_32_17.png",
            color: Color(red: 155/255, green: 155/255, blue: 155/255)   // Kinetic - 灰色
        ),
        ResistanceType(
            id: 3,
            iconName: "items_22_32_19.png",
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
                            IconManager.shared.loadImage(for: type.iconName)
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
    let allAttributes: [Int: Double]  // 添加所有属性的字典
    @ObservedObject var databaseManager: DatabaseManager // 添加数据库管理器
    
    // 获取格式化后的显示值
    private var formattedValue: String {
        let result = AttributeDisplayConfig.transformValue(attribute.id, allAttributes: allAttributes, unitID: attribute.unitID)
        switch result {
        case .number(let value, let unit):
            if attribute.unitID == 115 || attribute.unitID == 116 {
                // 对于 groupID 和 typeID，我们会显示名称，所以这里返回空
                return ""
            }
            return unit.map { "\(NumberFormatUtil.format(value))\($0)" } ?? NumberFormatUtil.format(value)
        case .text(let str):
            return str
        case .resistance:
            return "" // 抗性值使用专门的视图显示
        }
    }
    
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
    
    var body: some View {
        if AttributeDisplayConfig.shouldShowAttribute(attribute.id) {
            let result = AttributeDisplayConfig.transformValue(attribute.id, allAttributes: allAttributes, unitID: attribute.unitID)
            
            switch result {
            case .resistance(let resistances):
                ResistanceBarView(resistances: resistances)
            default:
                HStack {
                    // 属性图标
                    if attribute.iconID != 0 {
                        IconManager.shared.loadImage(for: attribute.iconFileName)
                            .resizable()
                            .frame(width: 32, height: 32)
                    }
                    
                    // 属性名称
                    Text(attribute.displayTitle)
                        .font(.body)
                    
                    Spacer()
                    
                    // 属性值 - 使用转换后的值
                    if attribute.unitID == 119 {
                        // 对于 attributeID，直接显示名称，不使用跳转链接
                        Text(displayName)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    } else if isNavigable, let destination = navigationDestination {
                        NavigationLink(destination: destination) {
                            HStack {
                                Spacer()  // 将文本推到右边
                                Text(displayName)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.trailing)  // 确保多行文本也是右对齐
                            }
                            .frame(minWidth: 100)  // 给予足够的空间显示文本
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
    }
}

// 属性组的显示组件
struct AttributeGroupView: View {
    let group: AttributeGroup
    let allAttributes: [Int: Double]
    let typeID: Int  // 添加typeID参数
    @ObservedObject var databaseManager: DatabaseManager
    
    private var filteredAttributes: [DogmaAttribute] {
        group.attributes
            .filter { AttributeDisplayConfig.shouldShowAttribute($0.id) }
            .sorted { attr1, attr2 in
                let order1 = AttributeDisplayConfig.getAttributeOrder(attributeID: attr1.id, in: group.id)
                let order2 = AttributeDisplayConfig.getAttributeOrder(attributeID: attr2.id, in: group.id)
                if order1 == order2 {
                    // 如果顺序相同，按属性ID排序
                    return attr1.id < attr2.id
                }
                return order1 < order2
            }
    }
    
    var body: some View {
        if AttributeDisplayConfig.shouldShowGroup(group.id) {
            Section {
                // 检查是否有抗性值需要显示
                if let resistances = AttributeDisplayConfig.getResistanceValues(groupID: group.id, from: allAttributes) {
                    ResistanceBarView(resistances: resistances)
                }
                
                // 只显示非抗性属性
                ForEach(filteredAttributes) { attribute in
                    AttributeItemView(attribute: attribute, allAttributes: allAttributes, databaseManager: databaseManager)
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
    
    // 构建所有属性的字典
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
    
    var body: some View {
        ForEach(sortedGroups) { group in
            if group.id == 8 {
                // 技能要求组
                let directRequirements = databaseManager.getDirectSkillRequirements(for: typeID)
                if !directRequirements.isEmpty {
                    Section(header: Text(group.name).font(.headline)) {
                        ForEach(directRequirements, id: \.skillID) { requirement in
                            // 获取该技能的所有前置技能
                            let allRequirements = SkillTreeManager.shared.getAllRequirements(for: requirement.skillID)
                            
                            // 显示直接技能要求
                            SkillRequirementRow(
                                skillID: requirement.skillID,
                                level: requirement.level,
                                indentLevel: 0,
                                databaseManager: databaseManager
                            )
                            
                            // 显示前置技能要求
                            ForEach(allRequirements, id: \.self) { prereq in
                                SkillRequirementRow(
                                    skillID: prereq.skillID,
                                    level: prereq.level,
                                    indentLevel: 1,
                                    databaseManager: databaseManager
                                )
                            }
                        }
                    }
                }
            } else {
                AttributeGroupView(
                    group: group,
                    allAttributes: allAttributes,
                    typeID: typeID,
                    databaseManager: databaseManager
                )
            }
        }
    }
} 
