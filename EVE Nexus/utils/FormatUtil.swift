import Foundation

enum FormatUtil {
    // 共享的 NumberFormatter 实例
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2  // 最多2位小数
        formatter.groupingSeparator = ","  // 千位分隔符
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

        // 对于小数，显示最多2位有效小数（去除末尾的0）
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2g", value)
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
    /// - Parameter isk: ISK 数值
    /// - Returns: 格式化后的 ISK 字符串
    static func formatISK(_ value: Double) -> String {
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1000.0

        if value >= billion {
            let formatted = value / billion
            if formatted >= 100 {
                return String(format: "%.1fB ISK", formatted)
            } else {
                return String(format: "%.2fB ISK", formatted)
            }
        } else if value >= million {
            let formatted = value / million
            if formatted >= 100 {
                return String(format: "%.1fM ISK", formatted)
            } else {
                return String(format: "%.2fM ISK", formatted)
            }
        } else if value >= thousand {
            let formatted = value / thousand
            if formatted >= 100 {
                return String(format: "%.1fK ISK", formatted)
            } else {
                return String(format: "%.2fK ISK", formatted)
            }
        } else {
            return String(format: "%.1f ISK", value)
        }
    }

    /// 格式化时间
    /// - Parameter totalSeconds: 总秒数
    /// - Returns: 格式化后的时间字符串
    static func formatTime(_ totalSeconds: Int) -> String {
        if totalSeconds < 1 {
            return "1s"
        }

        var days = totalSeconds / 86400
        var hours = (totalSeconds % 86400) / 3600
        var minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        // 当显示两个单位时，对第二个单位进行四舍五入
        if days > 0 {
            // 对小时进行四舍五入
            if minutes >= 30 {
                hours += 1
                if hours == 24 {  // 如果四舍五入后小时数达到24
                    days += 1
                    hours = 0
                }
            }
            if hours > 0 {
                return "\(days)d \(hours)h"
            }
            return "\(days)d"
        } else if hours > 0 {
            // 对分钟进行四舍五入
            if seconds >= 30 {
                minutes += 1
                if minutes == 60 {  // 如果四舍五入后分钟数达到60
                    hours += 1
                    minutes = 0
                }
            }
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        } else if minutes > 0 {
            // 对秒进行四舍五入
            if seconds >= 30 {
                minutes += 1
            }
            return "\(minutes)m"
        }
        return "\(seconds)s"
    }
}
