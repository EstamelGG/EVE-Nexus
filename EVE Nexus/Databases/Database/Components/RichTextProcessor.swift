import SwiftUI

struct RichTextView: View {
    let text: String
    @ObservedObject var databaseManager: DatabaseManager
    @State private var selectedItem: (itemID: Int, categoryID: Int)?
    @State private var showingSheet = false
    @State private var urlToConfirm: URL?
    @State private var showingURLAlert = false
    @State private var plainText: String = ""

    var body: some View {
        let processedResult = RichTextProcessor.processRichText(text)
        let _ = DispatchQueue.main.async {
            plainText = processedResult.plainText
        }
        
        processedResult.richText
            .environment(
                \.openURL,
                OpenURLAction { url in
                    if url.scheme == "showinfo",
                        let itemID = Int(url.host ?? ""),
                        let categoryID = databaseManager.getCategoryID(for: itemID)
                    {
                        selectedItem = (itemID, categoryID)
                        DispatchQueue.main.async {
                            showingSheet = true
                        }
                        return .handled
                    } else if url.scheme == "externalurl",
                        let urlString = url.host?.removingPercentEncoding,
                        let externalURL = URL(string: urlString)
                    {
                        urlToConfirm = externalURL
                        showingURLAlert = true
                        return .handled
                    }
                    return .systemAction
                }
            )
            .contextMenu {
                Button {
                    UIPasteboard.general.string = plainText
                } label: {
                    Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                }
            }
            .sheet(
                item: Binding(
                    get: {
                        selectedItem.map { SheetItem(itemID: $0.itemID, categoryID: $0.categoryID) }
                    },
                    set: { if $0 == nil { selectedItem = nil } }
                )
            ) { item in
                NavigationStack {
                    ItemInfoMap.getItemInfoView(
                        itemID: item.itemID,
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
                .presentationDetents([.fraction(0.81)])  // 设置为屏幕高度的82%
                .presentationDragIndicator(.visible)  // 显示拖动指示器
            }
            .alert(NSLocalizedString("Misc_OpenLink", comment: ""), isPresented: $showingURLAlert) {
                Button(NSLocalizedString("Common_Cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("Misc_Yes", comment: "")) {
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

// 处理结果结构体
struct RichTextProcessResult {
    let richText: Text
    let plainText: String
}

enum RichTextProcessor {
    static func cleanRichText(_ text: String) -> String {
        var currentText = text

        // 1. 处理换行标签（包括自闭合标签）
        currentText = currentText.replacingOccurrences(of: "<br></br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "<br />", with: "\n")
        currentText = currentText.replacingOccurrences(of: "<br/>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "<br>", with: "\n")
        currentText = currentText.replacingOccurrences(of: "</br>", with: "\n")

        // 2. 处理font标签，保留内容
        if let regex = try? NSRegularExpression(
            pattern: "<font[^>]*>(.*?)</font>", options: [.dotMatchesLineSeparators]
        ) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(
                in: currentText, options: [], range: range, withTemplate: "$1"
            )
        }

        // 3. 统一链接格式：将带引号的href转换为不带引号的格式
        // 先处理双引号的情况
        if let regex = try? NSRegularExpression(pattern: "<a href=\"([^\"]*)\"", options: []) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(
                in: currentText, options: [], range: range, withTemplate: "<a href=$1"
            )
        }
        // 再处理单引号的情况
        if let regex = try? NSRegularExpression(pattern: "<a href='([^']*)'", options: []) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(
                in: currentText, options: [], range: range, withTemplate: "<a href=$1"
            )
        }

        // 4. 优化连续换行和空格
        currentText = currentText.replacingOccurrences(
            of: "\n{3,}", with: "\n\n", options: .regularExpression
        )
        currentText = currentText.replacingOccurrences(
            of: " +", with: " ", options: .regularExpression
        )

        // 5. 删除所有非白名单的HTML标签（除了链接相关的标签）
        let pattern = "<(?!/?(a|b|url))[^>]*>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(
                in: currentText, options: [], range: range, withTemplate: ""
            )
        }

        return currentText
    }
    
    static func processRichText(_ text: String) -> RichTextProcessResult {
        // 记录原始文本
        Logger.debug("RichText processing - Original text:\n\(text)")

        // 清理文本
        let currentText = cleanRichText(text)

        // 记录基础清理后的文本
        Logger.debug("RichText processing - After basic cleanup:\n\(currentText)")

        // 创建AttributedString
        var attributedString = AttributedString(currentText)
        var processedText = currentText

        // 处理链接
        while let linkStart = processedText.range(of: "<a href="),
            let linkEnd = processedText.range(of: "</a>")
        {
            let linkText = processedText[linkStart.lowerBound..<linkEnd.upperBound]

            if let textStart = linkText.range(of: ">")?.upperBound,
                let textEnd = linkText.range(of: "</a>")?.lowerBound
            {
                let displayText = String(linkText[textStart..<textEnd])
                let startIndex = attributedString.range(of: linkText)?.lowerBound
                let endIndex = attributedString.range(of: linkText)?.upperBound

                if let start = startIndex, let end = endIndex {
                    // 处理showinfo链接
                    if linkText.contains("href=showinfo:"),
                        let idStart = linkText.range(of: "showinfo:")?.upperBound,
                        let idEnd = linkText.range(of: ">")?.lowerBound
                    {
                        let idString = String(linkText[idStart..<idEnd])
                        if let itemID = Int(idString),
                            idString.range(of: "^\\d+$", options: .regularExpression) != nil
                        {
                            // 有效的showinfo链接，设置为可点击
                            attributedString.replaceSubrange(
                                start..<end, with: AttributedString(displayText)
                            )
                            attributedString[
                                start..<attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].foregroundColor = .blue
                            attributedString[
                                start..<attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].link = URL(string: "showinfo://\(itemID)")

                            Logger.debug(
                                "Processed showinfo link - ID: \(itemID), Text: \(displayText)")
                        } else {
                            // 无效的showinfo链接，只保留文本内容
                            attributedString.replaceSubrange(
                                start..<end, with: AttributedString(displayText)
                            )
                            Logger.debug(
                                "Invalid showinfo link format - Text: \(displayText)")
                        }
                    } else {
                        // 处理普通链接
                        attributedString.replaceSubrange(
                            start..<end, with: AttributedString(displayText)
                        )
                        attributedString[
                            start..<attributedString.index(
                                start, offsetByCharacters: displayText.count
                            )
                        ].foregroundColor = .blue
                        if let hrefStart = linkText.range(of: "href=")?.upperBound,
                            let hrefEnd = linkText.range(of: ">")?.lowerBound,
                            let url = URL(string: String(linkText[hrefStart..<hrefEnd]))
                        {
                            attributedString[
                                start..<attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].link = url
                        }
                    }
                }
            }

            // 更新剩余文本
            processedText = String(processedText[linkEnd.upperBound...])
        }

        // 记录处理链接后的文本
        Logger.debug(
            "RichText processing - After processing links:\n\(attributedString.characters)")

        // 处理URL标签
        processedText = currentText
        while let urlStart = processedText.range(of: "<url="),
            let urlEnd = processedText.range(of: "</url>")
        {
            let urlText = processedText[urlStart.lowerBound..<urlEnd.upperBound]

            if let urlValueStart = urlText.range(of: "=")?.upperBound,
                let urlValueEnd = urlText.range(of: ">")?.lowerBound,
                let textStart = urlText.range(of: ">")?.upperBound,
                let textEnd = urlText.range(of: "</url>")?.lowerBound
            {
                let url = String(urlText[urlValueStart..<urlValueEnd])
                let displayText = String(urlText[textStart..<textEnd])

                let startIndex = attributedString.range(of: urlText)?.lowerBound
                let endIndex = attributedString.range(of: urlText)?.upperBound

                if let start = startIndex, let end = endIndex {
                    // 处理showinfo链接
                    if url.contains("showinfo:") {
                        let idString = url.replacingOccurrences(of: "showinfo:", with: "")
                        if let itemID = Int(idString),
                            idString.range(of: "^\\d+$", options: .regularExpression) != nil
                        {
                            // 有效的showinfo链接，设置为可点击
                            attributedString.replaceSubrange(
                                start..<end, with: AttributedString(displayText)
                            )
                            attributedString[
                                start..<attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].foregroundColor = .blue
                            attributedString[
                                start..<attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].link = URL(string: "showinfo://\(itemID)")

                            Logger.debug(
                                "Processed showinfo URL - ID: \(itemID), Text: \(displayText)")
                        } else {
                            // 无效的showinfo链接，只保留文本内容
                            attributedString.replaceSubrange(
                                start..<end, with: AttributedString(displayText)
                            )
                            Logger.debug(
                                "Invalid showinfo URL format - Text: \(displayText)")
                        }
                    } else {
                        // 处理普通URL
                        attributedString.replaceSubrange(
                            start..<end, with: AttributedString(displayText)
                        )
                        attributedString[
                            start..<attributedString.index(
                                start, offsetByCharacters: displayText.count
                            )
                        ].foregroundColor = .blue
                        // 使用自定义scheme来处理外部URL
                        if let encodedUrl = url.addingPercentEncoding(
                            withAllowedCharacters: .urlHostAllowed)
                        {
                            attributedString[
                                start..<attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].link = URL(string: "externalurl://\(encodedUrl)")
                        }
                    }
                }
            }

            // 更新剩余文本
            processedText = String(processedText[urlEnd.upperBound...])
        }

        // 记录处理URL后的文本
        Logger.debug("RichText processing - After processing URLs:\n\(attributedString.characters)")

        // 处理加粗文本
        // 首先找出所有的加粗标签对
        var boldRanges: [(Range<String.Index>, String)] = []
        var searchRange = currentText.startIndex..<currentText.endIndex

        while let boldStart = currentText.range(of: "<b>", range: searchRange),
            let boldEnd = currentText.range(
                of: "</b>", range: boldStart.upperBound..<currentText.endIndex
            )
        {
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
            if let attrStartIndex = attributedString.range(of: String(currentText[fullRange]))?
                .lowerBound
            {
                let attrEndIndex = attributedString.index(
                    attrStartIndex, offsetByCharacters: "<b>".count + boldText.count + "</b>".count
                )
                attributedString.replaceSubrange(
                    attrStartIndex..<attrEndIndex, with: AttributedString(boldText)
                )

                let boldEndIndex = attributedString.index(
                    attrStartIndex, offsetByCharacters: boldText.count
                )
                // 使用最简单的粗体设置方式
                attributedString[attrStartIndex..<boldEndIndex].inlinePresentationIntent = .stronglyEmphasized

                Logger.debug("Applied bold style to: \(boldText)")
            }
        }

        // 记录最终处理后的文本
        Logger.debug("RichText processing - Final processed text:\n\(attributedString.characters)")

        // 使用 NSAttributedString 的内置方法提取纯文本
        let nsAttributedString = NSAttributedString(attributedString)
        let plainText = nsAttributedString.string

        Logger.debug("RichText processing - Final plain text:\n\(plainText)")

        // 创建文本视图并返回结果
        let richText = Text(attributedString)
        return RichTextProcessResult(richText: richText, plainText: plainText)
    }
}
