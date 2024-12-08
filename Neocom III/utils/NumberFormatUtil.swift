import Foundation

struct NumberFormatUtil {
    // 共享的 NumberFormatter 实例
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3  // 最多3位小数
        formatter.groupingSeparator = ","    // 千位分隔符
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        return formatter
    }()
    
    /// 格式化数字：支持千位分隔符，最多3位有效小数
    /// - Parameter value: 要格式化的数值
    /// - Returns: 格式化后的字符串
    static func format(_ value: Double) -> String {
        // 如果是整数，不显示小数部分
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
        
        // 对于小数，显示最多3位有效小数（去除末尾的0）
        formatter.maximumFractionDigits = 3
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.3g", value)
    }
    
    /// 格式化带单位的数值
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - unit: 单位字符串
    /// - Returns: 格式化后的带单位的字符串
    static func formatWithUnit(_ value: Double, unit: String) -> String {
        return format(value) + unit
    }
} 
