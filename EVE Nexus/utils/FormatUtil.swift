import Foundation

struct FormatUtil {
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
    
    /// 格式化文件大小
    /// - Parameter size: 文件大小（字节）
    /// - Returns: 格式化后的文件大小字符串
    static func formatFileSize(_ size: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB"]
        var size = Double(size)
        var unitIndex = 0
        
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        // 根据大小使用不同的小数位数
        let formattedSize: String
        if unitIndex == 0 {
            formattedSize = String(format: "%.0f", size) // 字节不显示小数
        } else if size >= 100 {
            formattedSize = String(format: "%.0f", size) // 大于100时不显示小数
        } else if size >= 10 {
            formattedSize = String(format: "%.1f", size) // 大于10时显示1位小数
        } else {
            formattedSize = String(format: "%.2f", size) // 其他情况显示2位小数
        }
        
        return "\(formattedSize) \(units[unitIndex])"
    }
} 