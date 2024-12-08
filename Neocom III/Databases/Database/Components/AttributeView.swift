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
            iconName: "items_22_32_8.png",
            color: Color(red: 74/255, green: 128/255, blue: 192/255)    // EM - 蓝色
        ),
        ResistanceType(
            id: 1,
            iconName: "items_22_32_10.png",
            color: Color(red: 176/255, green: 53/255, blue: 50/255)    // Thermal - 红色
        ),
        ResistanceType(
            id: 2,
            iconName: "items_22_32_9.png",
            color: Color(red: 155/255, green: 155/255, blue: 155/255)   // Kinetic - 灰色
        ),
        ResistanceType(
            id: 3,
            iconName: "items_22_32_11.png",
            color: Color(red: 185/255, green: 138/255, blue: 62/255)    // Explosive - 橙色
        )
    ]
    
    // 获取四舍五入后的百分比值
    private func roundedPercentage(_ value: Double) -> Int {
        return Int(round(value))
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // 图标和数值行
            HStack(spacing: 8) {
                ForEach(resistanceTypes) { type in
                    HStack(spacing: 4) {
                        // 图标
                        IconManager.shared.loadImage(for: type.iconName)
                            .resizable()
                            .frame(width: 18, height: 18)
                        
                        // 数值
                        Text("\(roundedPercentage(resistances[type.id]))%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            
                        Spacer()
                    }
                }
            }
            
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
                                .brightness(0.1)     // 增加亮度
                                .saturation(1.1)     // 增加饱和度
                                .frame(width: geometry.size.width * CGFloat(resistances[type.id]) / 100)
                        }
                    }
                    .frame(height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(type.color, lineWidth: 1.1)
                            .brightness(0.1)     // 增加亮度
                            .saturation(1.1)     // 增加饱和度
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
    
    // 获取格式化后的显示值
    private var formattedValue: String {
        let result = AttributeDisplayConfig.transformValue(attribute.id, allAttributes: allAttributes)
        switch result {
        case .number(let value, let unit):
            return unit.map { NumberFormatUtil.formatWithUnit(value, unit: $0) } ?? NumberFormatUtil.format(value)
        case .text(let str):
            return str
        case .resistance:
            return "" // 抗性值使用专门的视图显示
        }
    }
    
    var body: some View {
        if AttributeDisplayConfig.shouldShowAttribute(attribute.id) {
            let result = AttributeDisplayConfig.transformValue(attribute.id, allAttributes: allAttributes)
            
            switch result {
            case .resistance(let resistances):
                ResistanceBarView(resistances: resistances)
            default:
                HStack {
                    // 属性图标
                    if attribute.iconID != 0 {
                        IconManager.shared.loadImage(for: attribute.iconFileName)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                    
                    // 属性名称
                    Text(attribute.displayTitle)
                        .font(.body)
                    
                    Spacer()
                    
                    // 属性值 - 使用转换后的值
                    Text(formattedValue)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// 属性组的显示组件
struct AttributeGroupView: View {
    let group: AttributeGroup
    let allAttributes: [Int: Double]  // 添加所有属性的字典
    
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
        if AttributeDisplayConfig.shouldShowGroup(group.id) && !filteredAttributes.isEmpty {
            Section {
                ForEach(filteredAttributes) { attribute in
                    AttributeItemView(attribute: attribute, allAttributes: allAttributes)
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
            AttributeGroupView(group: group, allAttributes: allAttributes)
        }
    }
} 
