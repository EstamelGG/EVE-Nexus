import Foundation

/// HTML工具类，提供HTML实体解码等功能
class HTMLUtils {
    /// 常见的HTML实体映射表
    private static let htmlEntities: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
    ]

    /// 解码HTML实体
    /// - Parameter text: 包含HTML实体的文本
    /// - Returns: 解码后的文本
    static func decodeHTMLEntities(_ text: String) -> String {
        var result = text

        // 按长度排序，先处理长的实体（避免部分匹配问题）
        let sortedEntities = htmlEntities.keys.sorted { $0.count > $1.count }

        for entity in sortedEntities {
            if let character = htmlEntities[entity] {
                result = result.replacingOccurrences(of: entity, with: character)
            }
        }

        return result
    }
}
