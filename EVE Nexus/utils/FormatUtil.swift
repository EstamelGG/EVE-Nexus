import Foundation

enum FormatUtil {
    // 共享的 NumberFormatter 实例
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3  // 默认最大3位小数
        formatter.groupingSeparator = ","  // 千位分隔符
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        return formatter
    }()

    // 用于毫秒精度的 NumberFormatter 实例
    private static let msFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumSignificantDigits = 1
        formatter.maximumSignificantDigits = 6  // 允许最多6位有效数字
        formatter.usesSignificantDigits = true  // 启用有效数字模式
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        return formatter
    }()

    // 用于UI显示的 NumberFormatter 实例（不使用千位分隔符）
    private static let uiFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1  // UI显示最多1位小数
        formatter.groupingSeparator = ""     // 不使用千位分隔符
        formatter.decimalSeparator = "."
        return formatter
    }()

    /// 通用的数字格式化函数
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - maxFractionDigits: 最大小数位数
    ///   - showDigit: 是否显示小数部分
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   formatNumber(1234.567, maxFractionDigits: 2)  // "1,234.57"
    ///   formatNumber(1234.0, maxFractionDigits: 2)     // "1,234"
    ///   formatNumber(1234.567, maxFractionDigits: 0)   // "1,235"
    ///   ```
    private static func formatNumber(
        _ value: Double, maxFractionDigits: Int, showDigit: Bool = true
    ) -> String {
        if !showDigit || value.truncatingRemainder(dividingBy: 1) == 0 {
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\(maxFractionDigits)f", value)
    }

    /// 通用的单位格式化函数
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - unit: 单位符号
    ///   - threshold: 单位阈值
    ///   - maxFractionDigits: 最大小数位数
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   formatWithUnit(1500, unit: "K", threshold: 1000, maxFractionDigits: 1)  // "1.5K"
    ///   formatWithUnit(1200, unit: "K", threshold: 1000, maxFractionDigits: 1)  // "1.2K"
    ///   formatWithUnit(1000, unit: "K", threshold: 1000, maxFractionDigits: 1)  // "1K"
    ///   ```
    private static func formatWithUnit(
        _ value: Double, unit: String, threshold: Double, maxFractionDigits: Int
    ) -> String {
        if value >= threshold {
            let formatted = value / threshold
            if formatted.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f\(unit)", formatted)
            }
            return String(format: "%.\(maxFractionDigits)f\(unit)", formatted)
        }
        return formatNumber(value, maxFractionDigits: 0)
    }

    /// 格式化数字：支持千位分隔符，最多3位有效小数
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - showDigit: 是否显示小数部分
    ///   - maxFractionDigits: 最大小数位数（默认3位）
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   format(1234.567)                // "1,234.567"
    ///   format(1234.0)                  // "1,234"
    ///   format(1234.567, false)         // "1,235"
    ///   format(1234.567, maxFractionDigits: 2)  // "1,234.57"
    ///   ```
    static func format(_ value: Double, _ showDigit: Bool = true, maxFractionDigits: Int = 3)
        -> String
    {
        return formatNumber(value, maxFractionDigits: maxFractionDigits, showDigit: showDigit)
    }

    /// 格式化数字（毫秒精度）：支持千位分隔符，最多3位有效小数，自动去除末尾的0
    /// - Parameter value: 要格式化的数值
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   formatWithMillisecondPrecision(1.234)    // "1.234"
    ///   formatWithMillisecondPrecision(1.200)    // "1.2"
    ///   formatWithMillisecondPrecision(1.000)    // "1"
    ///   formatWithMillisecondPrecision(0.001)    // "0.001"
    ///   ```
    static func formatWithMillisecondPrecision(_ value: Double) -> String {
        return msFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.3g", value)
    }

    /// 格式化文件大小
    /// - Parameter size: 文件大小（字节）
    /// - Returns: 格式化后的文件大小字符串
    /// - Example:
    ///   ```
    ///   formatFileSize(1024)        // "1 KB"
    ///   formatFileSize(1024 * 1024) // "1 MB"
    ///   formatFileSize(1500)        // "1.46 KB"
    ///   formatFileSize(999)         // "999 bytes"
    ///   ```
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
            formattedSize = String(format: "%.0f", size)  // 字节不显示小数
        } else if size >= 100 {
            formattedSize = String(format: "%.0f", size)  // 大于100时不显示小数
        } else if size >= 10 {
            formattedSize = String(format: "%.1f", size)  // 大于10时显示1位小数
        } else {
            formattedSize = String(format: "%.2f", size)  // 其他情况显示2位小数
        }

        return "\(formattedSize) \(units[unitIndex])"
    }

    /// 格式化 ISK 货币
    /// - Parameter value: ISK 数值
    /// - Returns: 格式化后的 ISK 字符串
    /// - Example:
    ///   ```
    ///   formatISK(1200)     // "1.2K ISK"
    ///   formatISK(1200000)  // "1.2M ISK"
    ///   formatISK(1200000000) // "1.2B ISK"
    ///   formatISK(1200000000000) // "1.2T ISK"
    ///   formatISK(999)      // "999 ISK"
    ///   ```
    static func formatISK(_ value: Double) -> String {
        let trillion = 1_000_000_000_000.0
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1000.0

        if value >= trillion {
            return formatWithUnit(value, unit: "T ISK", threshold: trillion, maxFractionDigits: 2)
        } else if value >= billion {
            return formatWithUnit(value, unit: "B ISK", threshold: billion, maxFractionDigits: 2)
        } else if value >= million {
            return formatWithUnit(value, unit: "M ISK", threshold: million, maxFractionDigits: 2)
        } else if value >= thousand {
            return formatWithUnit(value, unit: "K ISK", threshold: thousand, maxFractionDigits: 2)
        } else {
            return formatNumber(value, maxFractionDigits: 1) + " ISK"
        }
    }

    /// 格式化时间（保留毫秒精度）
    /// - Parameter milliseconds: 时间（毫秒）
    /// - Returns: 格式化后的时间字符串
    /// - Example:
    ///   ```
    ///   formatTimeWithMillisecondPrecision(1000)    // "1s"
    ///   formatTimeWithMillisecondPrecision(1500)    // "1.5s"
    ///   formatTimeWithMillisecondPrecision(61000)   // "1m 1s"
    ///   formatTimeWithMillisecondPrecision(3661000) // "1h 1m 1s"
    ///   formatTimeWithMillisecondPrecision(0.5)     // "1ms"
    ///   ```
    static func formatTimeWithMillisecondPrecision(_ milliseconds: Double) -> String {
        // 将毫秒转换为秒
        let seconds = milliseconds / 1000.0

        // 如果小于1秒，显示为毫秒
        if seconds < 1 {
            // 格式化毫秒，去掉末尾的0
            let formattedMs = formatWithMillisecondPrecision(milliseconds)
            return "\(formattedMs)ms"
        }

        // 转换为天时分秒
        let totalSecondsInt = Int(seconds)
        let days = totalSecondsInt / 86400
        let hours = (totalSecondsInt % 86400) / 3600
        let minutes = (totalSecondsInt % 3600) / 60
        let remainingSeconds = seconds - Double(days * 86400 + hours * 3600 + minutes * 60)

        // 组合时间字符串
        var result = ""

        if days > 0 {
            result += "\(days)d "
        }

        if hours > 0 || (days > 0 && (minutes > 0 || remainingSeconds > 0)) {
            result += "\(hours)h "
        }

        if minutes > 0 || (hours > 0 && remainingSeconds > 0) {
            result += "\(minutes)m "
        }

        // 秒数部分（保留毫秒精度）
        if remainingSeconds > 0 || result.isEmpty {
            // 格式化秒数，保留毫秒精度
            let formattedSeconds = formatWithMillisecondPrecision(remainingSeconds)
            result += "\(formattedSeconds)s"
        } else {
            // 移除最后的空格
            result = String(result.dropLast())
        }

        return result
    }

    /// 格式化时间（保留精度版本）
    /// - Parameter totalSeconds: 总秒数（浮点数，保留原始精度）
    /// - Returns: 格式化后的时间字符串
    /// - Example:
    ///   ```
    ///   formatTimeWithPrecision(1.5)    // "1.5s"
    ///   formatTimeWithPrecision(61.5)   // "1m 1.5s"
    ///   formatTimeWithPrecision(3661.5) // "1h 1m 1.5s"
    ///   formatTimeWithPrecision(0.5)    // "0.5s"
    ///   ```
    static func formatTimeWithPrecision(_ totalSeconds: Double) -> String {
        if totalSeconds < 1 {
            // 对于小于1秒的情况，保留原始精度
            let formattedSeconds = format(totalSeconds)
            return "\(formattedSeconds)s"
        }

        let totalSecondsInt = Int(totalSeconds)
        let days = totalSecondsInt / 86400
        let hours = (totalSecondsInt % 86400) / 3600
        let minutes = (totalSecondsInt % 3600) / 60
        let seconds = totalSeconds - Double(days * 86400 + hours * 3600 + minutes * 60)

        // 组合时间字符串
        var result = ""

        if days > 0 {
            result += "\(days)d "
        }

        if hours > 0 || (days > 0 && minutes > 0) {
            result += "\(hours)h "
        }

        if minutes > 0 || (hours > 0 && seconds > 0) {
            result += "\(minutes)m "
        }

        // 秒数保留原始精度
        if seconds > 0 || result.isEmpty {
            // 格式化秒数，去掉末尾的0
            let formattedSeconds = format(seconds)
            result += "\(formattedSeconds)s"
        } else {
            // 移除最后的空格
            result = String(result.dropLast())
        }

        return result
    }

    /// 格式化数字用于UI显示：不使用千位分隔符，自动去除末尾的0
    /// - Parameters:
    ///   - value: 要格式化的数值
    ///   - maxFractionDigits: 最大小数位数（默认1位）
    /// - Returns: 格式化后的字符串
    /// - Example:
    ///   ```
    ///   formatForUI(1234.5)                    // "1234.5"
    ///   formatForUI(1000.0)                    // "1000"
    ///   formatForUI(1500000000)                // "1.5B"
    ///   formatForUI(1500000)                   // "1.5M"
    ///   formatForUI(12500)                     // "12.5k"
    ///   formatForUI(1234.567, maxFractionDigits: 2)  // "1234.57"
    ///   ```
    static func formatForUI(_ value: Double, maxFractionDigits: Int = 1) -> String {
        // 临时设置formatter的小数位数
        let originalMaxFractionDigits = uiFormatter.maximumFractionDigits
        uiFormatter.maximumFractionDigits = maxFractionDigits
        
        defer {
            // 恢复原始设置
            uiFormatter.maximumFractionDigits = originalMaxFractionDigits
        }
        
        if value == 0 {
            return "0"
        } else if value >= 1_000_000_000 {
            let formattedValue = value / 1_000_000_000
            let numberString = uiFormatter.string(from: NSNumber(value: formattedValue)) ?? String(format: "%.\(maxFractionDigits)f", formattedValue)
            return numberString + "B"
        } else if value >= 1_000_000 {
            let formattedValue = value / 1_000_000
            let numberString = uiFormatter.string(from: NSNumber(value: formattedValue)) ?? String(format: "%.\(maxFractionDigits)f", formattedValue)
            return numberString + "M"
        } else if value >= 10_000 {
            let formattedValue = value / 1000
            let numberString = uiFormatter.string(from: NSNumber(value: formattedValue)) ?? String(format: "%.\(maxFractionDigits)f", formattedValue)
            return numberString + "k"
        } else {
            return uiFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxFractionDigits)f", value)
        }
    }
    

}
