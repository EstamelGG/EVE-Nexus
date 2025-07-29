import Foundation

/// 属性值格式化工具
///
/// 该工具用于处理属性值的格式化和单位拼接，与 AttributeDisplayConfig 集成
/// 以提供一致的属性值格式化体验。
///
/// 主要功能：
/// 1. 当提供 attributeID 时，直接使用 AttributeDisplayConfig.transformValue 进行转换
/// 2. 当没有 attributeID 时，只格式化数值而不添加单位
/// 3. 处理各种特殊属性格式（如时间、百分比、抗性等）
///
/// 使用方法：
/// let formattedValue = AttributeValueFormatter.format(
///     value: 10.5,      // 属性值
///     unitID: 101,      // 单位ID (可选)
///     attributeID: 155  // 属性ID (可选)
/// )
enum AttributeValueFormatter {
    /// 格式化属性值并添加单位
    /// - Parameters:
    ///   - value: 属性值
    ///   - unitID: 属性单位ID
    ///   - attributeID: 可选的属性ID，用于特殊处理某些属性
    /// - Returns: 格式化后的字符串，包含值和单位
    static func format(value: Double, unitID: Int?, attributeID: Int? = nil) -> String {
        // 如果没有提供attributeID，只进行简单的数值格式化
        guard let attributeID = attributeID else {
            return formatValue(value)
        }

        // 创建一个包含单个属性值的属性字典
        var allAttributes: [Int: Double] = [:]
        allAttributes[attributeID] = value

        // 使用 AttributeDisplayConfig 进行转换
        let result = AttributeDisplayConfig.transformValue(
            attributeID, allAttributes: allAttributes, unitID: unitID)

        // 处理不同的转换结果类型
        switch result {
        case let .number(value, unit):
            // 如果有单位，拼接值和单位
            return unit.map { "\(formatValue(value))\($0)" } ?? formatValue(value)

        case let .text(text):
            // 直接返回格式化好的文本
            return text

        case let .resistance(values):
            // 抗性值是特殊情况，通常不会单独显示，但如果需要，可以格式化为字符串
            return values.map { formatValue($0) + "%" }.joined(separator: ", ")
        }
    }

    /// 格式化数值
    private static func formatValue(_ value: Double) -> String {
        return FormatUtil.format(value, true, maxFractionDigits: 2)
    }
}
