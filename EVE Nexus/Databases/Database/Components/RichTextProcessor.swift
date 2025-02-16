import SwiftUI

struct RichTextView: View {
    let text: String
    @ObservedObject var databaseManager: DatabaseManager
    @State private var selectedItem: (itemID: Int, categoryID: Int)?
    @State private var showingSheet = false
    @State private var urlToConfirm: URL?
    @State private var showingURLAlert = false
    
    var body: some View {
        RichTextProcessor.processRichText(text)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "showinfo",
                   let itemID = Int(url.host ?? ""),
                   let categoryID = databaseManager.getCategoryID(for: itemID) {
                    selectedItem = (itemID, categoryID)
                    DispatchQueue.main.async {
                        showingSheet = true
                    }
                    return .handled
                } else if url.scheme == "externalurl",
                          let urlString = url.host?.removingPercentEncoding,
                          let externalURL = URL(string: urlString) {
                    urlToConfirm = externalURL
                    showingURLAlert = true
                    return .handled
                }
                return .systemAction
            })
            .sheet(item: Binding(
                get: { selectedItem.map { SheetItem(itemID: $0.itemID, categoryID: $0.categoryID) } },
                set: { if $0 == nil { selectedItem = nil } }
            )) { item in
                NavigationStack {
                    ItemInfoMap.getItemInfoView(
                        itemID: item.itemID,
                        categoryID: item.categoryID,
                        databaseManager: databaseManager
                    )
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(NSLocalizedString("Misc_back", comment: "")) {
                                selectedItem = nil
                                showingSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.fraction(0.85)])  // 设置为屏幕高度的85%
                .presentationDragIndicator(.visible)     // 显示拖动指示器
            }
            .alert("Open Link", isPresented: $showingURLAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Yes") {
                    if let url = urlToConfirm {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                if let url = urlToConfirm {
                    Text("\(url.absoluteString)")
                }
            }
    }
}

// 用于sheet的标识符类型
private struct SheetItem: Identifiable {
    let id = UUID()
    let itemID: Int
    let categoryID: Int
}

struct RichTextProcessor {
    static func cleanRichText(_ text: String) -> String {
        var currentText = text
        
        // 1. 处理换行标签
        currentText = currentText.replacingOccurrences(of: "<br></br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "<br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "</br>", with: "\n")
        
        // 2. 处理font标签，保留内容
        if let regex = try? NSRegularExpression(pattern: "<font[^>]*>(.*?)</font>", options: [.dotMatchesLineSeparators]) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(in: currentText, options: [], range: range, withTemplate: "$1")
        }
        
        // 3. 统一链接格式：将带引号的href转换为不带引号的格式
        // 先处理双引号的情况
        if let regex = try? NSRegularExpression(pattern: "<a href=\"([^\"]*)\"", options: []) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(in: currentText, options: [], range: range, withTemplate: "<a href=$1")
        }
        // 再处理单引号的情况
        if let regex = try? NSRegularExpression(pattern: "<a href='([^']*)'", options: []) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(in: currentText, options: [], range: range, withTemplate: "<a href=$1")
        }
        
        // 4. 优化连续换行和空格
        currentText = currentText.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        currentText = currentText.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        
        // 5. 删除所有非白名单的HTML标签（除了链接相关的标签）
        let pattern = "<(?!/?(a|url))[^>]*>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(in: currentText, options: [], range: range, withTemplate: "")
        }
        
        return currentText
    }

    static func processRichText(_ text: String) -> Text {
        // 记录原始文本
        Logger.debug("RichText processing - Original text:\n\(text)")
        
        // 清理文本
        let currentText = cleanRichText(text)
        
        // 记录基础清理后的文本
        Logger.debug("RichText processing - After basic cleanup:\n\(currentText)")
        
        // 5. 创建AttributedString
        var attributedString = AttributedString(currentText)
        var processedText = currentText
        
        // 6. 处理链接
        while let linkStart = processedText.range(of: "<a href="),
              let linkEnd = processedText.range(of: "</a>") {
            let linkText = processedText[linkStart.lowerBound..<linkEnd.upperBound]
            
            if let textStart = linkText.range(of: ">")?.upperBound,
               let textEnd = linkText.range(of: "</a>")?.lowerBound {
                let displayText = String(linkText[textStart..<textEnd])
                
                // 处理showinfo链接
                if linkText.contains("href=showinfo:"),
                   let idStart = linkText.range(of: "showinfo:")?.upperBound,
                   let idEnd = linkText.range(of: ">")?.lowerBound,
                   let itemID = Int(linkText[idStart..<idEnd]) {
                    
                    let startIndex = attributedString.range(of: linkText)?.lowerBound
                    let endIndex = attributedString.range(of: linkText)?.upperBound
                    
                    if let start = startIndex, let end = endIndex {
                        attributedString.replaceSubrange(start..<end, with: AttributedString(displayText))
                        attributedString[start..<attributedString.index(start, offsetByCharacters: displayText.count)].foregroundColor = .blue
                        attributedString[start..<attributedString.index(start, offsetByCharacters: displayText.count)].link = URL(string: "showinfo://\(itemID)")
                        
                        Logger.debug("Processed showinfo link - ID: \(itemID), Text: \(displayText)")
                    }
                }
            }
            
            // 更新剩余文本
            processedText = String(processedText[linkEnd.upperBound...])
        }
        
        // 记录处理链接后的文本
        Logger.debug("RichText processing - After processing links:\n\(attributedString.characters)")
        
        // 7. 处理URL标签
        processedText = currentText
        while let urlStart = processedText.range(of: "<url="),
              let urlEnd = processedText.range(of: "</url>") {
            let urlText = processedText[urlStart.lowerBound..<urlEnd.upperBound]
            
            if let urlValueStart = urlText.range(of: "=")?.upperBound,
               let urlValueEnd = urlText.range(of: ">")?.lowerBound,
               let textStart = urlText.range(of: ">")?.upperBound,
               let textEnd = urlText.range(of: "</url>")?.lowerBound {
                let url = String(urlText[urlValueStart..<urlValueEnd])
                let displayText = String(urlText[textStart..<textEnd])
                
                let startIndex = attributedString.range(of: urlText)?.lowerBound
                let endIndex = attributedString.range(of: urlText)?.upperBound
                
                if let start = startIndex, let end = endIndex {
                    attributedString.replaceSubrange(start..<end, with: AttributedString(displayText))
                    attributedString[start..<attributedString.index(start, offsetByCharacters: displayText.count)].foregroundColor = .blue
                    // 使用自定义scheme来处理外部URL
                    if let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
                        attributedString[start..<attributedString.index(start, offsetByCharacters: displayText.count)].link = URL(string: "externalurl://\(encodedUrl)")
                    }
                }
            }
            
            // 更新剩余文本
            processedText = String(processedText[urlEnd.upperBound...])
        }
        
        // 记录处理URL后的文本
        Logger.debug("RichText processing - After processing URLs:\n\(attributedString.characters)")
        
        // 8. 处理加粗文本
        // 首先找出所有的加粗标签对
        var boldRanges: [(Range<String.Index>, String)] = []
        var searchRange = currentText.startIndex..<currentText.endIndex
        
        while let boldStart = currentText.range(of: "<b>", range: searchRange),
              let boldEnd = currentText.range(of: "</b>", range: boldStart.upperBound..<currentText.endIndex) {
            let boldTextRange = boldStart.upperBound..<boldEnd.lowerBound
            let boldText = String(currentText[boldTextRange])
            let fullRange = boldStart.lowerBound..<boldEnd.upperBound
            boldRanges.append((fullRange, boldText))
            searchRange = boldEnd.upperBound..<currentText.endIndex
        }
        
        // 记录找到的加粗文本
        Logger.debug("RichText processing - Found \(boldRanges.count) bold ranges:")
        for (_, text) in boldRanges {
            Logger.debug("Bold text: \(text)")
        }
        
        // 从后向前处理每个加粗标签对
        for (fullRange, boldText) in boldRanges.reversed() {
            if let attrStartIndex = attributedString.range(of: String(currentText[fullRange]))?.lowerBound {
                let attrEndIndex = attributedString.index(attrStartIndex, offsetByCharacters: "<b>".count + boldText.count + "</b>".count)
                attributedString.replaceSubrange(attrStartIndex..<attrEndIndex, with: AttributedString(boldText))
                
                let boldEndIndex = attributedString.index(attrStartIndex, offsetByCharacters: boldText.count)
                var container = AttributeContainer()
                // 使用比系统字体大1.2倍的字号
                container.font = .boldSystemFont(ofSize: UIFont.systemFontSize * 1.2)
                attributedString[attrStartIndex..<boldEndIndex].setAttributes(container)
                
                Logger.debug("Applied bold style to: \(boldText)")
            }
        }
        
        // 记录最终处理后的文本
        Logger.debug("RichText processing - Final processed text:\n\(attributedString.characters)")
        
        // 9. 创建文本视图
        return Text(attributedString)
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
