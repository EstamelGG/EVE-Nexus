import SwiftUI

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
        }
    }
    
    var body: some View {
        if AttributeDisplayConfig.shouldShowAttribute(attribute.id) {
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
