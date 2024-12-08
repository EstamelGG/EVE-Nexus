import Foundation

// 属性显示规则配置
struct AttributeDisplayConfig {
    // 转换结果类型
    enum TransformResult {
        case number(Double, String?)  // 数值和可选单位
        case text(String)             // 纯文本
    }
    
    // 默认配置
    private static let defaultGroupOrder: [Int: Int] = [:]  // [categoryId: order] 自定义展示分组的顺序
    private static let defaultHiddenGroups: Set<Int> = [9, 52]   // 要隐藏的属性分组id
    private static let defaultHiddenAttributes: Set<Int> = [
        3,15,104,600,715,716,861,866,868,1137,1336,1547,1785,1970,1973,2754
    ] // 要隐藏的属性id
    
    // 值转换规则
    private static let valueTransformRules: [Int: (Double) -> TransformResult] = [
        188: { value in
            if value == 1 {
                return .text(NSLocalizedString("Main_Database_Item_info_Immune", comment: ""))
            } else {
                return .text(NSLocalizedString("Main_Database_Item_info_NonImmune", comment: ""))
            }
        },
        908: { value in
            return .number(value, " m3")
        },
        1560: { value in
            return .number(value, " m3")
        },
        912: { value in
            return .number(value, " m3")
        },
        1086: { value in
            return .number(value, " m3")
        },
        1549: { value in
            return .number(value, " m3")
        },
        2045: { value in
            return .number((1 - value) * 100, "%")
        },
        2112: { value in
            return .number((1 - value) * 100, "%")
        },
        2113: { value in
            return .number((1 - value) * 100, "%")
        },
        2114: { value in
            return .number((1 - value) * 100, "%")
        },
        2115: { value in
            return .number((1 - value) * 100, "%")
        },
        2116: { value in
            return .number((1 - value) * 100, "%")
        },
        2135: { value in
            return .number((1 - value) * 100, "%")
        },
        2571: { value in
            return .number(value, "%")
        },
        2572: { value in
            return .number(value, "%")
        },
        2574: { value in
            return .number(value, "%")
        }
        // 可以添加更多属性的转换规则
    ]
    
    // 自定义配置 - 可以根据需要设置，不设置则使用默认值
    static var customGroupOrder: [Int: Int]?
    static var customHiddenGroups: Set<Int>?
    static var customHiddenAttributes: Set<Int>?
    
    // 获取实际使用的配置
    static var activeGroupOrder: [Int: Int] {
        customGroupOrder ?? defaultGroupOrder
    }
    
    static var activeHiddenGroups: Set<Int> {
        customHiddenGroups ?? defaultHiddenGroups
    }
    
    static var activeHiddenAttributes: Set<Int> {
        customHiddenAttributes ?? defaultHiddenAttributes
    }
    
    // 判断属性组是否应该显示
    static func shouldShowGroup(_ groupId: Int) -> Bool {
        !activeHiddenGroups.contains(groupId)
    }
    
    // 判断具体属性是否应该显示
    static func shouldShowAttribute(_ attributeID: Int) -> Bool {
        !activeHiddenAttributes.contains(attributeID)
    }
    
    // 获取属性组的排序权重
    static func getGroupOrder(_ groupId: Int) -> Int {
        activeGroupOrder[groupId] ?? 999 // 未定义顺序的组放到最后
    }
    
    // 转换属性值
    static func transformValue(_ value: Double, for attributeID: Int) -> TransformResult {
        if let transform = valueTransformRules[attributeID] {
            return transform(value)
        }
        return .number(value, nil)  // 如果没有转换规则，返回原值
    }
    
    // 重置所有配置到默认值
    static func resetToDefaults() {
        customGroupOrder = nil
        customHiddenGroups = nil
        customHiddenAttributes = nil
    }
    
    // 设置自定义配置的便捷方法
    static func setCustomGroupOrder(_ order: [Int: Int]) {
        customGroupOrder = order
    }
    
    static func setHiddenGroups(_ groups: Set<Int>) {
        customHiddenGroups = groups
    }
    
    static func setHiddenAttributes(_ attributes: Set<Int>) {
        customHiddenAttributes = attributes
    }
    
    // 添加单个配置项的便捷方法
    static func hideGroup(_ groupId: Int) {
        var groups = customHiddenGroups ?? defaultHiddenGroups
        groups.insert(groupId)
        customHiddenGroups = groups
    }
    
    static func showGroup(_ groupId: Int) {
        var groups = customHiddenGroups ?? defaultHiddenGroups
        groups.remove(groupId)
        customHiddenGroups = groups
    }
    
    static func hideAttribute(_ attributeID: Int) {
        var attributes = customHiddenAttributes ?? defaultHiddenAttributes
        attributes.insert(attributeID)
        customHiddenAttributes = attributes
    }
    
    static func showAttribute(_ attributeID: Int) {
        var attributes = customHiddenAttributes ?? defaultHiddenAttributes
        attributes.remove(attributeID)
        customHiddenAttributes = attributes
    }
}
