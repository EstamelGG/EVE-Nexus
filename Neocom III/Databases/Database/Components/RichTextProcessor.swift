import SwiftUI

// 处理富文本，将HTML标签转换为SwiftUI的Text视图
struct RichTextProcessor {
    // 处理trait文本，返回组合的Text视图
    static func processRichText(_ text: String) -> Text {
        var result = Text("")
        var currentText = text
        
        // 1. 处理换行标签
        currentText = currentText.replacingOccurrences(of: "<br></br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "<br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "</br>", with: "\n")
        
        // 2. 删除所有非白名单的HTML标签
        // 使用负向前瞻，排除我们要保留的标签
        let pattern = "<(?!/?(b|a|br))[^>]*>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(in: currentText, options: [], range: range, withTemplate: "")
        }
        
        // 3. 优化连续换行
        currentText = currentText.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        
        // 4. 优化连续空格
        currentText = currentText.replacingOccurrences(
            of: " +",
            with: " ",
            options: .regularExpression
        )
        
        while !currentText.isEmpty {
            // 查找所有标签位置
            let boldStarts = currentText.ranges(of: "<b>")
            let boldEnds = currentText.ranges(of: "</b>")
            let linkStart = currentText.range(of: "<a href=")
            let linkEnd = currentText.range(of: "</a>")
            
            // 如果没有任何标签了，添加剩余文本并结束
            if boldStarts.isEmpty && linkStart == nil {
                result = result + Text(currentText)
                break
            }
            
            // 处理加粗文本
            if !boldStarts.isEmpty,
               !boldEnds.isEmpty,
               let firstStart = boldStarts.first,
               (linkStart == nil || firstStart.lowerBound < linkStart!.lowerBound) {
                // 找到与当前开始标签匹配的最近的结束标签
                let matchingEnd = boldEnds.first { $0.lowerBound > firstStart.upperBound }
                
                if let end = matchingEnd {
                    // 添加加粗标签前的普通文本
                    let beforeBold = String(currentText[..<firstStart.lowerBound])
                    if !beforeBold.isEmpty {
                        result = result + Text(beforeBold)
                    }
                    
                    // 提取并添加加粗文本
                    let boldText = String(currentText[firstStart.upperBound..<end.lowerBound])
                    result = result + Text(boldText).bold()
                    
                    // 更新剩余文本
                    currentText = String(currentText[end.upperBound...])
                    continue
                }
            }
            
            // 处理链接文本
            if let start = linkStart,
               let end = linkEnd {
                // 添加链接标签前的普通文本
                let beforeLink = String(currentText[..<start.lowerBound])
                if !beforeLink.isEmpty {
                    result = result + Text(beforeLink)
                }
                
                // 提取链接文本
                let linkText = currentText[start.lowerBound..<end.upperBound]
                if let textStart = linkText.range(of: ">")?.upperBound,
                   let textEnd = linkText.range(of: "</a>")?.lowerBound {
                    let displayText = String(linkText[textStart..<textEnd])
                    result = result + Text(displayText).foregroundColor(.blue)
                }
                
                // 更新剩余文本
                currentText = String(currentText[end.upperBound...])
                continue
            }
            
            // 如果到这里还有文本，说明有不匹配的标签，直接添加剩余文本
            result = result + Text(currentText)
            break
        }
        
        return result
    }
}

// 扩展 String 以支持查找所有匹配项
extension String {
    func ranges(of searchString: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = self.startIndex..<self.endIndex
        
        while let range = self.range(of: searchString, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<self.endIndex
        }
        
        return ranges
    }
} 