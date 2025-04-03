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

    // 用于毫秒精度的 NumberFormatter 实例
    private static let msFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3  // 最多3位小数（毫秒级）
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

    /// 格式化数字（毫秒精度）：支持千位分隔符，最多3位有效小数
    /// - Parameter value: 要格式化的数值
    /// - Returns: 格式化后的字符串
    static func formatWithMillisecondPrecision(_ value: Double) -> String {
        // 如果是整数，不显示小数部分
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            msFormatter.maximumFractionDigits = 0
            return msFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }

        // 获取小数部分
        let decimalPart = value - floor(value)

        // 根据小数精度调整显示
        var digits = 3

        // 如果小数第3位是0，最多显示2位
        if (decimalPart * 1000).truncatingRemainder(dividingBy: 1) == 0 {
            // 如果小数第2位也是0，最多显示1位
            if (decimalPart * 100).truncatingRemainder(dividingBy: 1) == 0 {
                // 如果小数第1位也是0，不显示小数
                if (decimalPart * 10).truncatingRemainder(dividingBy: 1) == 0 {
                    digits = 0
                } else {
                    digits = 1
                }
            } else {
                digits = 2
            }
        }

        msFormatter.maximumFractionDigits = digits
        return msFormatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\(digits)f", value)
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
        let trillion = 1_000_000_000_000.0
        let billion = 1_000_000_000.0
        let million = 1_000_000.0
        let thousand = 1000.0

        if value >= trillion {
            let formatted = value / trillion
            if formatted >= 100 {
                return String(format: "%.1fT ISK", formatted)
            } else {
                return String(format: "%.2fT ISK", formatted)
            }
        } else if value >= billion {
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

    /// 格式化时间（保留毫秒精度）
    /// - Parameter milliseconds: 时间（毫秒）
    /// - Returns: 格式化后的时间字符串
    static func formatTimeWithMillisecondPrecision(_ milliseconds: Double) -> String {
        // 如果值小于1毫秒，四舍五入到1毫秒
        if milliseconds < 1 {
            return "1ms"
        }

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
}
