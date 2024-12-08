import Foundation

struct NumberFormatUtil {
    // 共享的 NumberFormatter 实例
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        return formatter
    }()
    
    /// 格式化数字，支持千位分隔符，自动处理小数位
    /// - Parameter value: 要格式化的数值
    /// - Returns: 格式化后的字符串
    static func format(_ value: Double) -> String {
        // 处理整数部分
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
        
        // 处理小数部分（保留必要的小数位）
        formatter.maximumFractionDigits = 2
        let roundedValue = (value * 100).rounded() / 100
        return formatter.string(from: NSNumber(value: roundedValue)) ?? String(format: "%g", roundedValue)
    }
    
    /// 格式化百分比
    /// - Parameter value: 要格式化的数值（原始值，如0.8表示80%）
    /// - Returns: 格式化后的百分比字符串
    static func formatPercent(_ value: Double) -> String {
        let percentValue = value * 100
        return format(percentValue) + "%"
    }
    
    /// 格式化带单位的数值
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - unit: 单位字符串
    /// - Returns: 格式化后的带单位的字符串
    static func formatWithUnit(_ value: Double, unit: String) -> String {
        return format(value) + unit
    }
    
    /// 格式化大数值（K, M, B）
    /// - Parameter value: 要格式化的数值
    /// - Returns: 格式化后的字符串
    static func formatLargeNumber(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return format(value / 1_000_000_000) + "B"
        } else if value >= 1_000_000 {
            return format(value / 1_000_000) + "M"
        } else if value >= 1_000 {
            return format(value / 1_000) + "K"
        }
        return format(value)
    }
} 