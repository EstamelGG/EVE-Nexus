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
    
    // 属性单位
    private static var attributeUnits: [Int: String] = [:]
    
    // 属性值计算规则
    private static var attributeCalculations: [Int: AttributeCalculation] = [
        // 示例：属性ID 1 的值 = 属性ID 2 的值 + 属性ID 3 的值
        // operation: .add,.subtract,.multiply,.divide (+-*/)
        1281: AttributeCalculation(sourceAttribute1: 1281, sourceAttribute2: 70, operation: .add)
    ]
    
    // 值转换规则（特殊处理的属性）
    private static let valueTransformRules: [Int: (Double) -> Double] = [
        76: { value in value/1000 },  // km转换
        898: { value in value * 100 }, // 百分比转换
        1971: { value in value * 100 }, // 百分比转换
        2045: { value in (1 - value) * 100 }, // 反向百分比转换
        2112: { value in (1 - value) * 100 }, // 反向百分比转换
        2113: { value in (1 - value) * 100 }, // 反向百分比转换
        2114: { value in (1 - value) * 100 }, // 反向百分比转换
        2115: { value in (1 - value) * 100 }, // 反向百分比转换
        2116: { value in (1 - value) * 100 }, // 反向百分比转换
        2135: { value in (1 - value) * 100 }  // 反向百分比转换
    ]
    
    // 布尔值转换规则
    private static let booleanTransformRules: Set<Int> = [
        188, // immune
        861  // true/false
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
    
    // 初始化属性单位
    static func initializeUnits(with units: [Int: String]) {
        attributeUnits = units
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
        
        // 处理布尔值
        if booleanTransformRules.contains(attributeID) {
            if attributeID == 188 {
                return value == 1 ? 
                    .text(NSLocalizedString("Main_Database_Item_info_Immune", comment: "")) :
                    .text(NSLocalizedString("Main_Database_Item_info_NonImmune", comment: ""))
            } else if attributeID == 861 {
                return value == 1 ? 
                    .text(NSLocalizedString("Misc_true", comment: "")) :
                    .text(NSLocalizedString("Misc_false", comment: ""))
            }
        }
        
        // 应用数值转换规则
        let transformedValue = valueTransformRules[attributeID]?(value) ?? value
        
        // 获取单位（如果有）
        let unit = attributeUnits[attributeID].map { " " + $0 }
        
        return .number(transformedValue, unit)
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
        attributeCalculations[attributeID] = AttributeCalculation(
            sourceAttribute1: source1,
            sourceAttribute2: source2,
            operation: operation
        )
    }
    
    // 移除属性计算规则
    static func removeCalculationRule(for attributeID: Int) {
        attributeCalculations.removeValue(forKey: attributeID)
    }
}
