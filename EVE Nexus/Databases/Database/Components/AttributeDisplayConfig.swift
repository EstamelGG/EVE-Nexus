import Foundation

// 属性显示规则配置
enum AttributeDisplayConfig {
    // 转换结果类型
    enum TransformResult {
        case number(Double, String?)  // 数值和可选单位
        case text(String)  // 纯文本
        case resistance([Double])  // 抗性显示（EM, Thermal, Kinetic, Explosive）
    }

    // 特殊值映射类型
    private enum SpecialValueType {
        case boolean  // 布尔值 (True/False)
        case size  // 尺寸 (Small/Medium/Large)
        case gender  // 性别 (Male/Unisex/Female)

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
        5700: .boolean,
    ]

    // 抗性属性组定义
    struct ResistanceGroup {
        let groupID: Int
        let emIDs: [Int]  // 改为数组
        let thermalIDs: [Int]  // 改为数组
        let kineticIDs: [Int]  // 改为数组
        let explosiveIDs: [Int]  // 改为数组
    }

    // 定义抗性属性组
    private static let resistanceGroups: [ResistanceGroup] = [
        ResistanceGroup(
            groupID: 2,
            emIDs: [271, 1423, 2118],
            thermalIDs: [274, 1425, 2119],
            kineticIDs: [273, 1424, 2120],
            explosiveIDs: [272, 1422, 2121]
        ),  // 护盾抗性
        ResistanceGroup(
            groupID: 3,
            emIDs: [267, 1418],
            thermalIDs: [270, 1419],
            kineticIDs: [269, 1420],
            explosiveIDs: [268, 1421]
        ),  // 装甲抗性
        ResistanceGroup(
            groupID: 4,
            emIDs: [113, 974, 1426],
            thermalIDs: [110, 977, 1429],
            kineticIDs: [109, 976, 1428],
            explosiveIDs: [111, 975, 1427]
        ),  // 结构抗性
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
        let operation: Operation  // 算符
    }

    // 默认配置
    private static let defaultGroupOrder: [Int: Int] = [:]  // [categoryId: order] 自定义展示分组的顺序
    private static let defaultHiddenGroups: Set<Int> = [9, 52]  // 要隐藏的属性分组id
    private static let defaultHiddenAttributes: Set<Int> = [
        3, 15, 600, 715, 716, 1137, 1336, 1547,
    ]  // 要隐藏的属性id

    // 属性组内属性的默认排序配置 [groupId: [attributeId: order]]
    private static let defaultAttributeOrder: [Int: [Int: Int]] = [:]
    // [
    // 装备属性组
    //        1: [
    //            141: 1,  // 数量
    //            120: 2,  // 点数
    //            283: 3   // 体积
    //        ],
    // ]

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
        1281: AttributeCalculation(
            sourceAttribute1: 1281, sourceAttribute2: 600, operation: .multiply
        )
    ]

    // 基于 Attribute_id 的值转换规则
    private static let valueTransformRules: [Int: (Double) -> Double] = [:]

    // 基于 unitID 的值转换规则
    private static let unitTransformRules: [Int: (Double) -> Double] = [
        108: { value in (1 - value) * 100 },  // 百分比转换
        111: { value in (1 - value) * 100 },  // 百分比转换
        127: { value in value * 100 },  // 百分比转换
    ]

    // 基于 unitID 的值格式化规则
    private static let unitFormatRules: [Int: (Double, String?) -> String] = [
        109: { value, _ in
            let diff = value - 1
            return diff > 0
                ? "+\(FormatUtil.format(diff * 100))%" : "\(FormatUtil.format(diff * 100))%"
        },
        3: { value, _ in
            FormatUtil.formatTime(Int(value))
        },
        101: { value, _ in
            let seconds = value / 1000
            return FormatUtil.formatTime(Int(seconds))
        },
    ]

    // 布尔值转换规则
    private static let booleanTransformRules: Set<Int> = [
        188,  // immune
        861,  // true/false
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
        // 首先检查组是否被显式隐藏
        if activeHiddenGroups.contains(groupId) {
            return false
        }
        return true
    }

    // 新增：检查属性组是否有任何可显示的属性
    static func hasVisibleAttributes(
        groupId: Int, attributes: [DogmaAttribute]
    ) -> Bool {
        // 如果组被显式隐藏，直接返回false
        if !shouldShowGroup(groupId) {
            return false
        }

        // 检查组内是否有任何可显示的属性
        return attributes.contains { attribute in
            shouldShowAttribute(
                attribute.id, attribute: attribute
            )
        }
    }

    // 判断具体属性是否应该显示
    static func shouldShowAttribute(
        _ attributeID: Int, attribute: DogmaAttribute
    ) -> Bool {
        // 如果是抗性属性，不单独显示
        if isResistanceAttribute(attributeID) {
            return false
        }

        // 如果属性在隐藏列表中，不显示
        if activeHiddenAttributes.contains(attributeID) {
            return false
        }

        // 在完整模式下，显示所有有name的属性
        return !attribute.name.isEmpty
    }

    // 获取属性组的排序权重
    static func getGroupOrder(_ groupId: Int) -> Int {
        activeGroupOrder[groupId] ?? 999  // 未定义顺序的组放到最后
    }

    // 计算属性值
    private static func calculateValue(for attributeID: Int, in allAttributes: [Int: Double])
        -> Double
    {
        // 如果有计算规则
        if let calc = attributeCalculations[attributeID],
            let value1 = allAttributes[calc.sourceAttribute1],
            let value2 = allAttributes[calc.sourceAttribute2]
        {
            return calc.operation.calculate(value1, value2)
        }
        // 如果没有计算规则，返回原始值
        return allAttributes[attributeID] ?? 0
    }

    // 检查是否是抗性属性组
    private static func findResistanceGroup(for groupID: Int) -> ResistanceGroup? {
        return resistanceGroups.first { $0.groupID == groupID }
    }

    // 定义一个结构来存储命中的抗性属性ID
    struct ResistanceHits {
        let emID: Int?
        let thermalID: Int?
        let kineticID: Int?
        let explosiveID: Int?

        var hasAnyResistance: Bool {
            return emID != nil || thermalID != nil || kineticID != nil || explosiveID != nil
        }
    }

    // 修改检查方法，返回命中的属性ID
    private static func findResistanceAttributes(groupID: Int, in allAttributes: [Int: Double])
        -> ResistanceHits?
    {
        guard let group = findResistanceGroup(for: groupID) else { return nil }

        // 查找每种类型中第一个存在的属性ID
        let emID = group.emIDs.first { allAttributes[$0] != nil }
        let thermalID = group.thermalIDs.first { allAttributes[$0] != nil }
        let kineticID = group.kineticIDs.first { allAttributes[$0] != nil }
        let explosiveID = group.explosiveIDs.first { allAttributes[$0] != nil }

        let hits = ResistanceHits(
            emID: emID,
            thermalID: thermalID,
            kineticID: kineticID,
            explosiveID: explosiveID
        )

        return hits.hasAnyResistance ? hits : nil
    }

    // 原来的hasAnyResistance方法可以这样使用新方法
    private static func hasAnyResistance(groupID: Int, in allAttributes: [Int: Double]) -> Bool {
        return findResistanceAttributes(groupID: groupID, in: allAttributes)?.hasAnyResistance
            ?? false
    }

    // 修改获取抗性值的方法
    static func getResistanceValues(groupID: Int, from allAttributes: [Int: Double]) -> [Double]? {
        guard let hits = findResistanceAttributes(groupID: groupID, in: allAttributes) else {
            return nil
        }

        // 使用命中的属性ID获取值，如果没有则使用默认值1.0
        let emValue = hits.emID.flatMap { allAttributes[$0] } ?? 1.0
        let thermalValue = hits.thermalID.flatMap { allAttributes[$0] } ?? 1.0
        let kineticValue = hits.kineticID.flatMap { allAttributes[$0] } ?? 1.0
        let explosiveValue = hits.explosiveID.flatMap { allAttributes[$0] } ?? 1.0

        return [
            (1 - emValue) * 100,
            (1 - thermalValue) * 100,
            (1 - kineticValue) * 100,
            (1 - explosiveValue) * 100,
        ]
    }

    // 检查是否是抗性属性
    private static func isResistanceAttribute(_ attributeID: Int) -> Bool {
        for group in resistanceGroups {
            if group.emIDs.contains(attributeID) || group.thermalIDs.contains(attributeID)
                || group.kineticIDs.contains(attributeID)
                || group.explosiveIDs.contains(attributeID)
            {
                return true
            }
        }
        return false
    }

    // 转换属性值，将数值与单位拼接
    static func transformValue(_ attributeID: Int, allAttributes: [Int: Double], unitID: Int?)
        -> TransformResult
    {
        let value = calculateValue(for: attributeID, in: allAttributes)

        // 检查是否有特殊值映射
        if let specialType = specialValueMappings[attributeID] {
            return .text(specialType.transform(value))
        }

        // 处理布尔值
        if booleanTransformRules.contains(attributeID) {
            if attributeID == 188 {
                return value == 1
                    ? .text(NSLocalizedString("Main_Database_Item_info_Immune", comment: ""))
                    : .text(NSLocalizedString("Main_Database_Item_info_NonImmune", comment: ""))
            }
        }

        var transformedValue = value

        // 1. 首先应用基于 attribute_id 的转换规则
        if let transformRule = valueTransformRules[attributeID] {
            transformedValue = transformRule(transformedValue)
        }

        // 2. 然后应用基于 unitID 的转换规则
        if let unitID = unitID,
            let unitTransform = unitTransformRules[unitID]
        {
            transformedValue = unitTransform(transformedValue)
        }

        // 3. 应用基于 unitID 的格式化规则
        if let unitID = unitID,
            let formatRule = unitFormatRules[unitID]
        {
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
    static func addCalculationRule(
        for attributeID: Int, source1: Int, source2: Int, operation: Operation
    ) {
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
