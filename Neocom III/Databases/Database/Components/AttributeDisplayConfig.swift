import Foundation

// 属性显示规则配置
struct AttributeDisplayConfig {
    // 转换结果类型
    enum TransformResult {
        case number(Double, String?)  // 数值和可选单位
        case text(String)             // 纯文本
    }
    
    // 运算符类型
    enum Operation: String {
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"
        
        func calculate(_ a: Double, _ b: Double) -> Double {
            switch self {
            case .add: return a + b
            case .subtract: return a - b
            case .multiply: return a * b
            case .divide: return b == 0 ? 0 : a / b
            }
        }
    }
    
    // 属性值计算配置
    struct AttributeCalculation {
        let sourceAttribute1: Int  // 第一个源属性ID
        let sourceAttribute2: Int  // 第二个源属性ID
        let operation: Operation   // 运算符
    }
    
    // 默认配置
    private static let defaultGroupOrder: [Int: Int] = [:]  // [categoryId: order] 自定义展示分组的顺序
    private static let defaultHiddenGroups: Set<Int> = [9, 52]   // 要隐藏的属性分组id
    private static let defaultHiddenAttributes: Set<Int> = [
        3,15,104,600,715,716,861,866,868,1137,1336,1547,1785,1970,1973,2754
    ] // 要隐藏的属性id
    
    // 属性值计算规则
    private static let attributeCalculations: [Int: AttributeCalculation] = [
        // 示例：属性ID 1 的值 = 属性ID 2 的值 + 属性ID 3 的值
        // 1: AttributeCalculation(sourceAttribute1: 2, sourceAttribute2: 3, operation: .add)
        // 可以添加更多计算规则
        // operation: .add,.subtract,.multiply,.divide (+-*/)
        1281: AttributeCalculation(sourceAttribute1: 1281, sourceAttribute2: 70, operation: .add)
    ]
    
    // 值转换规则
    private static let valueTransformRules: [Int: (Double) -> TransformResult] = [
        37: { value in return .number(value, " m/s")},
        70: { value in return .number(value, " x")},
        76: { value in return .number(value/1000, " km")},
        188: { value in
            if value == 1 {
                return .text(NSLocalizedString("Main_Database_Item_info_Immune", comment: ""))
            } else {
                return .text(NSLocalizedString("Main_Database_Item_info_NonImmune", comment: ""))
            }
        },
        283: { value in return .number(value, " m3")},
        552: { value in return .number(value, " m")},
        564: { value in return .number(value, " mm")},
        908: { value in return .number(value, " m3")},
        912: { value in return .number(value, " m3")},
        1086: { value in return .number(value, " m3")},
        1271: { value in return .number(value, " Mbit/s")},
        1281: { value in return .number(value, " AU/s")},
        1379: { value in return .number(value, " m/s")},
        1549: { value in return .number(value, " m3")},
        1556: { value in return .number(value, " m3")},
        1557: { value in return .number(value, " m3")},
        1558: { value in return .number(value, " m3")},
        1559: { value in return .number(value, " m3")},
        1560: { value in return .number(value, " m3")},
        1561: { value in return .number(value, " m3")},
        1562: { value in return .number(value, " m3")},
        1563: { value in return .number(value, " m3")},
        1564: { value in return .number(value, " m3")},
        1573: { value in return .number(value, " m3")},
        1804: { value in return .number(value, " m3")},
        1971: { value in return .number(value * 100, "%")},
        2045: { value in return .number((1 - value) * 100, "%")},
        2055: { value in return .number(value, " m3")},
        2112: { value in return .number((1 - value) * 100, "%")},
        2113: { value in return .number((1 - value) * 100, "%")},
        2114: { value in return .number((1 - value) * 100, "%")},
        2115: { value in return .number((1 - value) * 100, "%")},
        2116: { value in return .number((1 - value) * 100, "%")},
        2135: { value in return .number((1 - value) * 100, "%")},
        2467: { value in return .number(value, " m3")},
        2571: { value in return .number(value, "%")},
        2572: { value in return .number(value, "%")},
        2574: { value in return .number(value, "%")},
        2657: { value in return .number(value, " m3")},
        2675: { value in return .number(value, " m3")},
        3136: { value in return .number(value, " m3")},
        3227: { value in return .number(value, " m3")},
        5325: { value in return .number(value, " m3")},
        5646: { value in return .number(value, " m3")},
        5693: { value in return .number(value, " m3")},
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
    
    // 计算属性值
    private static func calculateValue(for attributeID: Int, in allAttributes: [Int: Double]) -> Double {
        // 如果有计算规则
        if let calc = attributeCalculations[attributeID],
           let value1 = allAttributes[calc.sourceAttribute1],
           let value2 = allAttributes[calc.sourceAttribute2] {
            return calc.operation.calculate(value1, value2)
        }
        // 如果没有计算规则，返回原始值
        return allAttributes[attributeID] ?? 0
    }
    
    // 转换属性值
    static func transformValue(_ attributeID: Int, allAttributes: [Int: Double]) -> TransformResult {
        let value = calculateValue(for: attributeID, in: allAttributes)
        
        if let transform = valueTransformRules[attributeID] {
            return transform(value)
        }
        return .text(NumberFormatUtil.format(value))
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
    
    // 添加属性计算规则
    static func addCalculationRule(for attributeID: Int, source1: Int, source2: Int, operation: Operation) {
        var rules = attributeCalculations
        rules[attributeID] = AttributeCalculation(sourceAttribute1: source1, sourceAttribute2: source2, operation: operation)
    }
    
    // 移除属性计算规则
    static func removeCalculationRule(for attributeID: Int) {
        var rules = attributeCalculations
        rules.removeValue(forKey: attributeID)
    }
}
