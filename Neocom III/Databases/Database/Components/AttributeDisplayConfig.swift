import Foundation

// 属性显示规则配置
struct AttributeDisplayConfig {
    // 转换结果类型
    enum TransformResult {
        case number(Double, String?)  // 数值和可选单位
        case text(String)             // 纯文本
        case resistance([Double])     // 抗性显示（EM, Thermal, Kinetic, Explosive）
    }
    
    // 特殊值映射类型
    private enum SpecialValueType {
        case boolean           // 布尔值 (True/False)
        case size             // 尺寸 (Small/Medium/Large)
        case gender           // 性别 (Male/Unisex/Female)
        
        func transform(_ value: Double) -> String {
            switch self {
            case .boolean:
                return value == 1 ? "True" : "False"
            case .size:
                switch Int(value) {
                case 1: return "Small"
                case 2: return "Medium"
                case 3: return "Large"
                case 4: return "X-large"
                default: return "Unknown"
                }
            case .gender:
                switch Int(value) {
                case 1: return "Male"
                case 2: return "Unisex"
                case 3: return "Female"
                default: return "Unknown"
                }
            }
        }
    }
    
    // 特殊值映射配置
    private static let specialValueMappings: [Int: SpecialValueType] = [
        // 尺寸映射
        128: .size,
        1031: .size,
        1547: .size,
        
        // 性别映射
        1773: .gender,
        
        // 布尔值映射
        786: .boolean,
        854: .boolean,
        861: .boolean,
        1014: .boolean,
        1074: .boolean,
        1158: .boolean,
        1167: .boolean,
        1245: .boolean,
        1252: .boolean,
        1785: .boolean,
        1798: .boolean,
        1806: .boolean,
        1854: .boolean,
        1890: .boolean,
        1916: .boolean,
        1920: .boolean,
        1927: .boolean,
        1945: .boolean,
        1958: .boolean,
        1970: .boolean,
        2343: .boolean,
        2354: .boolean,
        2395: .boolean,
        2453: .boolean,
        2454: .boolean,
        2791: .boolean,
        2826: .boolean,
        2827: .boolean,
        3117: .boolean,
        3123: .boolean,
        5206: .boolean,
        5425: .boolean,
        5426: .boolean,
        5561: .boolean,
        5700: .boolean
    ]
    
    // 抗性属性组定义
    struct ResistanceGroup {
        let groupID: Int
        let emID: Int
        let thermalID: Int
        let kineticID: Int
        let explosiveID: Int
    }
    
    // 定义抗性属性组
    private static let resistanceGroups: [ResistanceGroup] = [
        ResistanceGroup(groupID: 2, emID: 271, thermalID: 274, kineticID: 273, explosiveID: 272),      // 护盾抗性
        ResistanceGroup(groupID: 3, emID: 267, thermalID: 270, kineticID: 269, explosiveID: 268),      // 装甲抗性
        ResistanceGroup(groupID: 4, emID: 113, thermalID: 110, kineticID: 109, explosiveID: 111)       // 结构抗性
    ]
    
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
        let operation: Operation   // 算符
    }
    
    // 默认配置
    private static let defaultGroupOrder: [Int: Int] = [:]  // [categoryId: order] 自定义展示分组的顺序
    private static let defaultHiddenGroups: Set<Int> = [9, 52]   // 要隐藏的属性分组id
    private static let defaultHiddenAttributes: Set<Int> = [
        3,15,104,252,600,715,716,866,868,1137,1336,1547,1785,1970,1973,2754
    ] // 要隐藏的属性id
    
    // 属性组内属性的默认排序配置 [groupId: [attributeId: order]]
    private static let defaultAttributeOrder: [Int: [Int: Int]] = [:]
    //[
        // 装备属性组
//        1: [
//            141: 1,  // 数量
//            120: 2,  // 点数
//            283: 3   // 体积
//        ],
    //]
    
    // 属性单位
    private static var attributeUnits: [Int: String] = [:]
    
    // 属性组内属性的自定义排序配置
    private static var customAttributeOrder: [Int: [Int: Int]]?
    
    // 获取实际使用的属性排序配置
    private static var activeAttributeOrder: [Int: [Int: Int]] {
        customAttributeOrder ?? defaultAttributeOrder
    }
    
    // 属性值计算规则
    private static var attributeCalculations: [Int: AttributeCalculation] = [
        // 示例：属性ID 1 的值 = 属性ID 2 的值 + 属性ID 3 的值
        // operation: .add,.subtract,.multiply,.divide (+-*/)
        1281: AttributeCalculation(sourceAttribute1: 1281, sourceAttribute2: 600, operation: .multiply)
    ]
    
    // 基于 Attribute_id 的值转换规则
    private static let valueTransformRules: [Int: (Double) -> Double] = [:]
    
    // 基于 unitID 的值转换规则
    private static let unitTransformRules: [Int: (Double) -> Double] = [
        108: { value in (1 - value) * 100 }, // 百分比转换
        127: { value in (value) * 100 }, // 百分比转换
        101: { value in (value) / 1000 } // 毫秒转秒
    ]
    
    // 基于 unitID 的值格式化规则
    private static let unitFormatRules: [Int: (Double, String?) -> String] = [
        109: { value, unit in
            let diff = value - 1
            return diff > 0 ? "+\(NumberFormatUtil.format(diff * 100))%" : "\(NumberFormatUtil.format(diff * 100))%"
        }
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
        // 如果是抗性属性但不是第一个，则隐藏
        if isResistanceAttribute(attributeID) && !isFirstResistanceAttribute(attributeID) {
            return false
        }
        return !activeHiddenAttributes.contains(attributeID)
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
    
    // 检查是否是抗性属性组
    private static func findResistanceGroup(for groupID: Int) -> ResistanceGroup? {
        return resistanceGroups.first { $0.groupID == groupID }
    }
    
    // 获取抗性值数组
    private static func getResistanceValues(groupID: Int, from allAttributes: [Int: Double]) -> [Double]? {
        guard let group = findResistanceGroup(for: groupID) else { return nil }
        
        // 检查是否至少有一个抗性值存在
        let hasEmValue = allAttributes[group.emID] != nil
        let hasThermalValue = allAttributes[group.thermalID] != nil
        let hasKineticValue = allAttributes[group.kineticID] != nil
        let hasExplosiveValue = allAttributes[group.explosiveID] != nil
        
        // 如果没有任何抗性值，返回 nil
        if !hasEmValue && !hasThermalValue && !hasKineticValue && !hasExplosiveValue {
            return nil
        }
        
        // 获取抗性值，如果不存在则使用默认值 1.0
        let emValue = allAttributes[group.emID] ?? 1.0
        let thermalValue = allAttributes[group.thermalID] ?? 1.0
        let kineticValue = allAttributes[group.kineticID] ?? 1.0
        let explosiveValue = allAttributes[group.explosiveID] ?? 1.0
        // 转换为显示值 (1 - value) * 100，保持原始精度
        return [
            (1 - emValue) * 100,
            (1 - thermalValue) * 100,
            (1 - kineticValue) * 100,
            (1 - explosiveValue) * 100
        ]
    }
    
    // 检查是否是抗性属性组的第一个属性
    private static func isFirstResistanceAttribute(_ attributeID: Int) -> Bool {
        for group in resistanceGroups {
            // 检查是否是任意一个抗性属性
            if [group.emID, group.thermalID, group.kineticID, group.explosiveID].contains(attributeID) {
                return true
            }
        }
        return false
    }
    
    // 检查是否是抗性属性
    private static func isResistanceAttribute(_ attributeID: Int) -> Bool {
        for group in resistanceGroups {
            if [group.emID, group.thermalID, group.kineticID, group.explosiveID].contains(attributeID) {
                return true
            }
        }
        return false
    }
    
    // 转换属性值
    static func transformValue(_ attributeID: Int, allAttributes: [Int: Double], unitID: Int?) -> TransformResult {
        let value = calculateValue(for: attributeID, in: allAttributes)
        
        // 检查是否有特殊值映射
        if let specialType = specialValueMappings[attributeID] {
            return .text(specialType.transform(value))
        }
        
        // 检查是否属于抗性组
        if isResistanceAttribute(attributeID) {
            // 如果是抗性属性，检查是否应该显示抗性组
            if isFirstResistanceAttribute(attributeID) {
                for group in resistanceGroups {
                    // 如果是任意一个抗性属性，并且有抗性值可以显示
                    if [group.emID, group.thermalID, group.kineticID, group.explosiveID].contains(attributeID),
                       let resistances = getResistanceValues(groupID: group.groupID, from: allAttributes) {
                        return .resistance(resistances)
                    }
                }
            }
            // 其他抗性属性不显示
            return .text("")
        }
        
        // 处理布尔值
        if booleanTransformRules.contains(attributeID) {
            if attributeID == 188 {
                return value == 1 ? 
                    .text(NSLocalizedString("Main_Database_Item_info_Immune", comment: "")) :
                    .text(NSLocalizedString("Main_Database_Item_info_NonImmune", comment: ""))
            }
        }
        
        var transformedValue = value
        
        // 1. 首先应用基于 attribute_id 的转换规则
        if let transformRule = valueTransformRules[attributeID] {
            transformedValue = transformRule(transformedValue)
        }
        
        // 2. 然后应用基于 unitID 的转换规则
        if let unitID = unitID,
           let unitTransform = unitTransformRules[unitID] {
            transformedValue = unitTransform(transformedValue)
        }
        
        // 3. 应用基于 unitID 的格式化规则
        if let unitID = unitID,
           let formatRule = unitFormatRules[unitID] {
            let unit = attributeUnits[attributeID]
            return .text(formatRule(transformedValue, unit))
        }
        
        // 4. 默认格式化
        if let unit = attributeUnits[attributeID] {
            // 百分号不添加空格，其他单位添加空格
            return .number(transformedValue, unit == "%" ? unit : " " + unit)
        }
        return .number(transformedValue, nil)
    }
    
    // 获取属性在组内的排序权重
    static func getAttributeOrder(attributeID: Int, in groupID: Int) -> Int {
        activeAttributeOrder[groupID]?[attributeID] ?? 999  // 未定义顺序的属性放到最后
    }
    
    // 设置属性组内的属性顺序
    static func setAttributeOrder(for groupID: Int, orders: [Int: Int]) {
        if customAttributeOrder == nil {
            customAttributeOrder = defaultAttributeOrder
        }
        customAttributeOrder?[groupID] = orders
    }
    
    // 设置单个属性的顺序
    static func setAttributeOrder(attributeID: Int, order: Int, in groupID: Int) {
        if customAttributeOrder == nil {
            customAttributeOrder = defaultAttributeOrder
        }
        if customAttributeOrder?[groupID] == nil {
            customAttributeOrder?[groupID] = [:]
        }
        customAttributeOrder?[groupID]?[attributeID] = order
    }
    
    // 移除属性组的排序配置
    static func removeAttributeOrder(for groupID: Int) {
        customAttributeOrder?.removeValue(forKey: groupID)
        if customAttributeOrder?.isEmpty == true {
            customAttributeOrder = nil
        }
    }
    
    // 移除单个属性的排序配置
    static func removeAttributeOrder(attributeID: Int, in groupID: Int) {
        customAttributeOrder?[groupID]?.removeValue(forKey: attributeID)
        if customAttributeOrder?[groupID]?.isEmpty == true {
            customAttributeOrder?.removeValue(forKey: groupID)
        }
        if customAttributeOrder?.isEmpty == true {
            customAttributeOrder = nil
        }
    }
    
    // 重置所有配置到默认值
    static func resetToDefaults() {
        customGroupOrder = nil
        customHiddenGroups = nil
        customHiddenAttributes = nil
        customAttributeOrder = nil
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
    
    // 移除属性算规则
    static func removeCalculationRule(for attributeID: Int) {
        attributeCalculations.removeValue(forKey: attributeID)
    }
}
