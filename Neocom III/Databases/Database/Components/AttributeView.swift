import SwiftUI

// 单个属性的显示组件
struct AttributeItemView: View {
    let attribute: DogmaAttribute
    
    // 格式化数值的函数
    private func formatValue(_ value: Double) -> String {
        let roundedValue = (value * 100).rounded() / 100  // 保留两位小数
        if roundedValue.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", roundedValue)  // 整数
        } else {
            return String(format: "%g", roundedValue)    // 去除末尾的0
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
                
                // 属性值 - 使用新的格式化函数
                Text(formatValue(attribute.value))
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
    
    private var filteredAttributes: [DogmaAttribute] {
        group.attributes.filter { AttributeDisplayConfig.shouldShowAttribute($0.id) }
    }
    
    var body: some View {
        if AttributeDisplayConfig.shouldShowGroup(group.name) && !filteredAttributes.isEmpty {
            Section {
                ForEach(filteredAttributes) { attribute in
                    AttributeItemView(attribute: attribute)
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
    
    private var sortedGroups: [AttributeGroup] {
        attributeGroups.sorted { group1, group2 in
            AttributeDisplayConfig.getGroupOrder(group1.name) < AttributeDisplayConfig.getGroupOrder(group2.name)
        }
    }
    
    var body: some View {
        ForEach(sortedGroups) { group in
            AttributeGroupView(group: group)
        }
    }
} 