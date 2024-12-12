import SwiftUI

struct RichTextView: View {
    let text: String
    @ObservedObject var databaseManager: DatabaseManager
    @State private var selectedItem: (itemID: Int, categoryID: Int)?
    @State private var showingSheet = false
    
    var body: some View {
        RichTextProcessor.processRichText(text)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "showinfo",
                   let itemID = Int(url.host ?? ""),
                   let categoryID = databaseManager.getCategoryID(for: itemID) {
                    selectedItem = (itemID, categoryID)
                    DispatchQueue.main.async {
                        showingSheet = true
                    }
                    return .handled
                }
                return .systemAction
            })
            .sheet(item: Binding(
                get: { selectedItem.map { SheetItem(itemID: $0.itemID, categoryID: $0.categoryID) } },
                set: { if $0 == nil { selectedItem = nil } }
            )) { item in
                NavigationView {
                    ItemInfoMap.getItemInfoView(
                        itemID: item.itemID,
                        categoryID: item.categoryID,
                        databaseManager: databaseManager
                    )
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
    static func processRichText(_ text: String) -> Text {
        var currentText = text
        
        // 1. 处理换行标签
        currentText = currentText.replacingOccurrences(of: "<br></br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "<br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "</br>", with: "\n")
        
        // 2. 删除所有非白名单的HTML标签
        let pattern = "<(?!/?(b|a|url|br))[^>]*>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(in: currentText, options: [], range: range, withTemplate: "")
        }
        
        // 3. 优化连续换行和空格
        currentText = currentText.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        currentText = currentText.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        
        // 4. 创建AttributedString
        var attributedString = AttributedString(currentText)
        
        // 5. 处理链接
        while let linkStart = currentText.range(of: "<a href="),
              let linkEnd = currentText.range(of: "</a>") {
            let linkText = currentText[linkStart.lowerBound..<linkEnd.upperBound]
            
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
                    }
                }
            }
            
            // 更新剩余文本
            currentText = String(currentText[linkEnd.upperBound...])
        }
        
        // 6. 处理加粗文本
        while let boldStart = currentText.range(of: "<b>"),
              let boldEnd = currentText.range(of: "</b>") {
            let boldText = currentText[boldStart.upperBound..<boldEnd.lowerBound]
            let startIndex = attributedString.range(of: "<b>\(boldText)</b>")?.lowerBound
            let endIndex = attributedString.range(of: "<b>\(boldText)</b>")?.upperBound
            
            if let start = startIndex, let end = endIndex {
                attributedString.replaceSubrange(start..<end, with: AttributedString(String(boldText)))
                var container = AttributeContainer()
                container.font = .boldSystemFont(ofSize: UIFont.systemFontSize)
                attributedString[start..<attributedString.index(start, offsetByCharacters: boldText.count)].setAttributes(container)
            }
            
            currentText = String(currentText[boldEnd.upperBound...])
        }
        
        // 7. 创建文本视图
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