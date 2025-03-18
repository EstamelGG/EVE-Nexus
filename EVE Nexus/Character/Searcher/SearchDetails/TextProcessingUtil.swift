import Foundation

// HTML和Unicode处理工具
class TextProcessingUtil {
    // 移除HTML标签和处理Unicode编码
    static func processDescription(_ description: String) -> String {
        // 检查是否为Unicode格式的字符串（u'开头，'结尾）
        if description.hasPrefix("u'") && description.hasSuffix("'") {
            // 先进行Unicode解码，再处理HTML标签
            let decodedString = decodeUnicodeString(description)
            return processHTMLContent(decodedString)
        }

        // 非Unicode格式的字符串直接处理HTML标签
        return processHTMLContent(description)
    }

    // 解码Unicode字符串的方法
    private static func decodeUnicodeString(_ unicodeString: String) -> String {
        // 移除前缀u'和后缀'
        let unicodeContent = String(unicodeString.dropFirst(2).dropLast())

        // 使用正则表达式查找所有\uXXXX格式的Unicode转义序列
        let pattern = "\\\\u([0-9a-fA-F]{4})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return unicodeContent
        }

        let nsString = unicodeContent as NSString
        let range = NSRange(location: 0, length: nsString.length)

        // 找出所有匹配项
        let matches = regex.matches(in: unicodeContent, options: [], range: range)

        // 如果没有匹配项，直接返回原始内容
        if matches.isEmpty {
            return unicodeContent
        }

        // 创建可变字符串进行替换
        let mutableString = NSMutableString(string: unicodeContent)

        // 从后向前遍历匹配项（避免替换影响后续位置）
        for match in matches.reversed() {
            // 提取十六进制字符串
            let hexRange = match.range(at: 1)
            guard hexRange.location != NSNotFound else { continue }

            let hexString = nsString.substring(with: hexRange)

            // 转换为Unicode字符
            guard let codePoint = UInt32(hexString, radix: 16),
                let scalar = UnicodeScalar(codePoint)
            else { continue }

            let unicodeChar = String(scalar)

            // 替换转义序列
            let fullRange = match.range
            mutableString.replaceCharacters(in: fullRange, with: unicodeChar)
        }

        return mutableString as String
    }

    // 处理HTML内容的辅助方法
    private static func processHTMLContent(_ content: String) -> String {
        // 使用RichTextProcessor的cleanRichText方法处理基本HTML结构
        var currentText = RichTextProcessor.cleanRichText(content)

        // 特别处理<br/>和<br />标签，确保换行正确
        currentText = currentText.replacingOccurrences(of: "<br/>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "<br />", with: "\n")

        // 移除可能残留的a标签和url标签（它们在cleanRichText中被保留）
        if let regex = try? NSRegularExpression(pattern: "</?a[^>]*>|</?url[^>]*>", options: []) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(
                in: currentText, options: [], range: range, withTemplate: ""
            )
        }

        // 处理HTML实体
        let htmlEntities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " ",
            "&ndash;": "–",
            "&mdash;": "—",
            "&lsquo;": "'",
            "&rsquo;": "'",
        ]

        for (entity, character) in htmlEntities {
            currentText = currentText.replacingOccurrences(of: entity, with: character)
        }

        // 优化空白和换行
        currentText = currentText.replacingOccurrences(
            of: "\n{3,}", with: "\n\n", options: .regularExpression
        )

        // 清理首尾空白
        return currentText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
