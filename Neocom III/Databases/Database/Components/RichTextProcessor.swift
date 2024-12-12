import SwiftUI

// 处理富文本，将HTML标签转换为SwiftUI的视图
struct RichTextProcessor {
    // 处理trait文本，返回组合的视图
    static func processRichText(_ text: String, databaseManager: DatabaseManager) -> some View {
        var views: [AnyView] = []
        var currentText = text
        
        // 1. 处理换行标签
        currentText = currentText.replacingOccurrences(of: "<br></br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "<br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "</br>", with: "\n")
        
        // 2. 删除所有非白名单的HTML标签
        // 使用负向前瞻，排除我们要保留的标签
        let pattern = "<(?!/?(b|a|url|br))[^>]*>"
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
            let urlStart = currentText.range(of: "<url=")
            let urlEnd = currentText.range(of: "</url>")
            
            // 如果没有任何标签了，添加剩余文本并结束
            if boldStarts.isEmpty && linkStart == nil && urlStart == nil {
                if !currentText.isEmpty {
                    views.append(AnyView(Text(currentText)))
                }
                break
            }
            
            // 处理加粗文本
            if !boldStarts.isEmpty,
               !boldEnds.isEmpty,
               let firstStart = boldStarts.first,
               (linkStart == nil || firstStart.lowerBound < linkStart!.lowerBound) &&
               (urlStart == nil || firstStart.lowerBound < urlStart!.lowerBound) {
                // 找到与当前开始标签匹配的最近的结束标签
                let matchingEnd = boldEnds.first { $0.lowerBound > firstStart.upperBound }
                
                if let end = matchingEnd {
                    // 添加加粗标签前的普通文本
                    let beforeBold = String(currentText[..<firstStart.lowerBound])
                    if !beforeBold.isEmpty {
                        views.append(AnyView(Text(beforeBold)))
                    }
                    
                    // 提取并添加加粗文本
                    let boldText = String(currentText[firstStart.upperBound..<end.lowerBound])
                    views.append(AnyView(Text(boldText).bold()))
                    
                    // 更新剩余文本
                    currentText = String(currentText[end.upperBound...])
                    continue
                }
            }
            
            // 处理showinfo链接文本
            if let start = linkStart,
               let end = linkEnd,
               (urlStart == nil || start.lowerBound < urlStart!.lowerBound) {
                // 添加链接标签前的普通文本
                let beforeLink = String(currentText[..<start.lowerBound])
                if !beforeLink.isEmpty {
                    views.append(AnyView(Text(beforeLink)))
                }
                
                // 提取链接文本和类型
                let linkText = currentText[start.lowerBound..<end.upperBound]
                if let textStart = linkText.range(of: ">")?.upperBound,
                   let textEnd = linkText.range(of: "</a>")?.lowerBound {
                    let displayText = String(linkText[textStart..<textEnd])
                    
                    // 处理showinfo链接
                    if linkText.contains("href=showinfo:"),
                       let idStart = linkText.range(of: "showinfo:")?.upperBound,
                       let idEnd = linkText.range(of: ">")?.lowerBound,
                       let itemID = Int(linkText[idStart..<idEnd]) {
                        views.append(AnyView(
                            LinkText(
                                text: displayText,
                                type: .showInfo,
                                itemID: itemID,
                                url: nil,
                                databaseManager: databaseManager
                            )
                        ))
                    }
                }
                
                // 更新剩余文本
                currentText = String(currentText[end.upperBound...])
                continue
            }
            
            // 处理url链接
            if let start = urlStart,
               let end = urlEnd {
                // 添加url标签前的普通文本
                let beforeUrl = String(currentText[..<start.lowerBound])
                if !beforeUrl.isEmpty {
                    views.append(AnyView(Text(beforeUrl)))
                }
                
                // 提取url文本
                let urlText = currentText[start.lowerBound..<end.upperBound]
                if let urlValueStart = urlText.range(of: "=")?.upperBound,
                   let urlValueEnd = urlText.range(of: ">")?.lowerBound,
                   let textStart = urlText.range(of: ">")?.upperBound,
                   let textEnd = urlText.range(of: "</url>")?.lowerBound {
                    let url = String(urlText[urlValueStart..<urlValueEnd])
                    let displayText = String(urlText[textStart..<textEnd])
                    
                    views.append(AnyView(
                        LinkText(
                            text: displayText,
                            type: .url,
                            itemID: nil,
                            url: url,
                            databaseManager: databaseManager
                        )
                    ))
                }
                
                // 更新剩余文本
                currentText = String(currentText[end.upperBound...])
                continue
            }
            
            // 如果到这里还有文本，说明有不匹配的标签，直接添加剩余文本
            if !currentText.isEmpty {
                views.append(AnyView(Text(currentText)))
            }
            break
        }
        
        return HStack(spacing: 0) {
            ForEach(0..<views.count, id: \.self) { index in
                views[index]
            }
        }
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