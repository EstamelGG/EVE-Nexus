import SwiftUI

struct RichTextView: View {
    let text: String
    @ObservedObject var databaseManager: DatabaseManager
    @State private var selectedItem: (itemID: Int, categoryID: Int)?
    @State private var showingSheet = false
    @State private var urlToConfirm: URL?
    @State private var showingURLAlert = false
    @State private var plainText: String = ""
    @State private var fittingToShow: LocalFitting?
    @State private var killReportToShow: Int?

    var body: some View {
        let processedResult = RichTextProcessor.processRichText(text)
        let _ = DispatchQueue.main.async {
            plainText = processedResult.plainText
        }
        return richTextWithModifiers(processedResult)
    }

    @ViewBuilder
    private func richTextWithModifiers(_ result: RichTextProcessResult) -> some View {
        result.richText
            .environment(\.openURL, openURLAction)
            .contextMenu { copyContextMenu }
            .sheet(item: itemSheetBinding) { item in itemSheetContent(item) }
            .alert(NSLocalizedString("Misc_OpenLink", comment: ""), isPresented: $showingURLAlert) {
                Button(NSLocalizedString("Common_Cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("Misc_Yes", comment: "")) {
                    if let url = urlToConfirm { UIApplication.shared.open(url) }
                }
            } message: {
                if let url = urlToConfirm { Text(url.absoluteString) }
            }
            .sheet(item: fittingSheetBinding) { item in fittingSheetContent(item) }
            .sheet(item: killReportSheetBinding) { item in killReportSheetContent(item) }
    }

    private var openURLAction: OpenURLAction {
        OpenURLAction { url in
            if url.scheme == "showinfo",
               let itemID = Int(url.host ?? ""),
               let categoryID = databaseManager.getCategoryID(for: itemID)
            {
                selectedItem = (itemID, categoryID)
                DispatchQueue.main.async { showingSheet = true }
                return .handled
            } else if url.scheme == "fitting" {
                handleDNALink(url)
                return .handled
            } else if url.scheme == "killreport",
                      let killIdString = url.host,
                      let killId = Int(killIdString)
            {
                killReportToShow = killId
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
    }

    @ViewBuilder
    private var copyContextMenu: some View {
        Button {
            UIPasteboard.general.string = plainText
        } label: {
            Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
        }
    }

    private var itemSheetBinding: Binding<SheetItem?> {
        Binding(
            get: { selectedItem.map { SheetItem(itemID: $0.itemID, categoryID: $0.categoryID) } },
            set: { if $0 == nil { selectedItem = nil } }
        )
    }

    @ViewBuilder
    private func itemSheetContent(_ item: SheetItem) -> some View {
        NavigationStack {
            ItemInfoMap.getItemInfoView(itemID: item.itemID, databaseManager: databaseManager)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("Misc_back", comment: "")) {
                            selectedItem = nil
                            showingSheet = false
                        }
                    }
                }
        }
        .presentationDetents([.fraction(0.81)])
        .presentationDragIndicator(.visible)
    }

    private var fittingSheetBinding: Binding<FittingSheetItem?> {
        Binding(
            get: { fittingToShow.map { FittingSheetItem(fitting: $0) } },
            set: { if $0 == nil { fittingToShow = nil } }
        )
    }

    @ViewBuilder
    private func fittingSheetContent(_ item: FittingSheetItem) -> some View {
        NavigationStack {
            ShipFittingView(temporaryFitting: item.fitting, databaseManager: databaseManager)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("Misc_back", comment: "")) {
                            fittingToShow = nil
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var killReportSheetBinding: Binding<KillReportSheetItem?> {
        Binding(
            get: { killReportToShow.map { KillReportSheetItem(killId: $0) } },
            set: { if $0 == nil { killReportToShow = nil } }
        )
    }

    @ViewBuilder
    private func killReportSheetContent(_ item: KillReportSheetItem) -> some View {
        NavigationStack {
            KillMailDetailLoaderView(killmailId: item.killId, character: nil)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("Misc_back", comment: "")) {
                            killReportToShow = nil
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - DNA链接处理方法

    private func handleDNALink(_ url: URL) {
        Logger.info("处理DNA链接: \(url.absoluteString)")

        // 直接从URL中获取DNA字符串，类似showinfo的处理方式
        let dnaString = url.absoluteString
        let displayName = NSLocalizedString("DNA_Fitting_Link_Default_Name", comment: "")

        // 解析DNA字符串
        guard let dnaResult = DNAParser.parseDNA(dnaString, displayName: displayName) else {
            Logger.error("DNA解析失败: \(dnaString)")
            return
        }

        // 将DNA结果转换为LocalFitting
        guard
            let localFitting = DNAParser.dnaResultToLocalFitting(
                dnaResult, databaseManager: databaseManager
            )
        else {
            Logger.error("DNA转换为LocalFitting失败")
            return
        }

        // 直接显示装配详情，不保存到文件
        DispatchQueue.main.async {
            self.fittingToShow = localFitting
        }

        Logger.info("DNA装配已准备显示，不保存到文件，ID: \(localFitting.fitting_id)")
    }
}

// 用于sheet的标识符类型
private struct SheetItem: Identifiable {
    let id = UUID()
    let itemID: Int
    let categoryID: Int
}

// 用于装配sheet的标识符类型
private struct FittingSheetItem: Identifiable {
    let id = UUID()
    let fitting: LocalFitting
}

// 用于战斗日志sheet的标识符类型
private struct KillReportSheetItem: Identifiable {
    let id = UUID()
    let killId: Int
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
            let range = NSRange(currentText.startIndex ..< currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(
                in: currentText, options: [], range: range, withTemplate: "$1"
            )
        }

        // 3. 统一链接格式：将带引号的href转换为不带引号的格式
        // 先处理双引号的情况
        if let regex = try? NSRegularExpression(pattern: "<a href=\"([^\"]*)\"", options: []) {
            let range = NSRange(currentText.startIndex ..< currentText.endIndex, in: currentText)
            currentText = regex.stringByReplacingMatches(
                in: currentText, options: [], range: range, withTemplate: "<a href=$1"
            )
        }
        // 再处理单引号的情况
        if let regex = try? NSRegularExpression(pattern: "<a href='([^']*)'", options: []) {
            let range = NSRange(currentText.startIndex ..< currentText.endIndex, in: currentText)
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
            let range = NSRange(currentText.startIndex ..< currentText.endIndex, in: currentText)
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
            let linkText = processedText[linkStart.lowerBound ..< linkEnd.upperBound]

            if let textStart = linkText.range(of: ">")?.upperBound,
               let textEnd = linkText.range(of: "</a>")?.lowerBound
            {
                let displayText = String(linkText[textStart ..< textEnd])
                let startIndex = attributedString.range(of: linkText)?.lowerBound
                let endIndex = attributedString.range(of: linkText)?.upperBound

                if let start = startIndex, let end = endIndex {
                    // 处理showinfo链接
                    if linkText.contains("href=showinfo:"),
                       let idStart = linkText.range(of: "showinfo:")?.upperBound,
                       let idEnd = linkText.range(of: ">")?.lowerBound
                    {
                        let idString = String(linkText[idStart ..< idEnd])
                        if let itemID = Int(idString),
                           idString.range(of: "^\\d+$", options: .regularExpression) != nil
                        {
                            // 有效的showinfo链接，设置为可点击
                            attributedString.replaceSubrange(
                                start ..< end, with: AttributedString(displayText)
                            )
                            attributedString[
                                start ..< attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].foregroundColor = .blue
                            attributedString[
                                start ..< attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].link = URL(string: "showinfo://\(itemID)")

                            Logger.debug(
                                "Processed showinfo link - ID: \(itemID), Text: \(displayText)")
                        } else {
                            // 无效的showinfo链接，只保留文本内容
                            attributedString.replaceSubrange(
                                start ..< end, with: AttributedString(displayText)
                            )
                            Logger.debug(
                                "Invalid showinfo link format - Text: \(displayText)")
                        }
                    } else if linkText.contains("href=fitting:") {
                        // 处理DNA装配链接
                        if let dnaStart = linkText.range(of: "fitting:")?.lowerBound,
                           let dnaEnd = linkText.range(of: ">")?.lowerBound
                        {
                            let dnaString = String(linkText[dnaStart ..< dnaEnd])

                            // 设置为可点击的DNA链接
                            attributedString.replaceSubrange(
                                start ..< end, with: AttributedString(displayText)
                            )
                            attributedString[
                                start ..< attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].foregroundColor = .blue

                            // 直接使用fitting://格式，类似showinfo://
                            attributedString[
                                start ..< attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].link = URL(string: dnaString)

                            Logger.debug(
                                "Processed DNA fitting link - DNA: \(dnaString), Text: \(displayText)"
                            )
                        } else {
                            // 无效的DNA链接，只保留文本内容
                            attributedString.replaceSubrange(
                                start ..< end, with: AttributedString(displayText)
                            )
                            Logger.debug(
                                "Invalid DNA fitting link format - Text: \(displayText)")
                        }
                    } else if linkText.contains("href=killReport:") {
                        // 处理战斗日志链接
                        if let killStart = linkText.range(of: "killReport:")?.upperBound,
                           let hrefEnd = linkText.range(of: ">")?.lowerBound
                        {
                            let hrefContent = String(linkText[killStart ..< hrefEnd])
                            // 提取第一个冒号前的数字作为 killmail ID
                            let components = hrefContent.components(separatedBy: ":")
                            if let killIdString = components.first, let killId = Int(killIdString) {
                                // 设置为可点击的战斗日志链接
                                attributedString.replaceSubrange(
                                    start ..< end, with: AttributedString(displayText)
                                )
                                attributedString[
                                    start ..< attributedString.index(
                                        start, offsetByCharacters: displayText.count
                                    )
                                ].foregroundColor = .blue
                                attributedString[
                                    start ..< attributedString.index(
                                        start, offsetByCharacters: displayText.count
                                    )
                                ].link = URL(string: "killreport://\(killId)")

                                Logger.debug(
                                    "Processed killReport link - ID: \(killId), Text: \(displayText)"
                                )
                            } else {
                                // 无效的killReport链接，只保留文本内容
                                attributedString.replaceSubrange(
                                    start ..< end, with: AttributedString(displayText)
                                )
                                Logger.debug(
                                    "Invalid killReport ID format - Text: \(displayText)")
                            }
                        } else {
                            // 无效的killReport链接格式，只保留文本内容
                            attributedString.replaceSubrange(
                                start ..< end, with: AttributedString(displayText)
                            )
                            Logger.debug(
                                "Invalid killReport link format - Text: \(displayText)")
                        }
                    } else {
                        // 处理普通链接
                        attributedString.replaceSubrange(
                            start ..< end, with: AttributedString(displayText)
                        )
                        attributedString[
                            start ..< attributedString.index(
                                start, offsetByCharacters: displayText.count
                            )
                        ].foregroundColor = .blue
                        if let hrefStart = linkText.range(of: "href=")?.upperBound,
                           let hrefEnd = linkText.range(of: ">")?.lowerBound,
                           let url = URL(string: String(linkText[hrefStart ..< hrefEnd]))
                        {
                            attributedString[
                                start ..< attributedString.index(
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
            let urlText = processedText[urlStart.lowerBound ..< urlEnd.upperBound]

            if let urlValueStart = urlText.range(of: "=")?.upperBound,
               let urlValueEnd = urlText.range(of: ">")?.lowerBound,
               let textStart = urlText.range(of: ">")?.upperBound,
               let textEnd = urlText.range(of: "</url>")?.lowerBound
            {
                let url = String(urlText[urlValueStart ..< urlValueEnd])
                let displayText = String(urlText[textStart ..< textEnd])

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
                                start ..< end, with: AttributedString(displayText)
                            )
                            attributedString[
                                start ..< attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].foregroundColor = .blue
                            attributedString[
                                start ..< attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].link = URL(string: "showinfo://\(itemID)")

                            Logger.debug(
                                "Processed showinfo URL - ID: \(itemID), Text: \(displayText)")
                        } else {
                            // 无效的showinfo链接，只保留文本内容
                            attributedString.replaceSubrange(
                                start ..< end, with: AttributedString(displayText)
                            )
                            Logger.debug(
                                "Invalid showinfo URL format - Text: \(displayText)")
                        }
                    } else if url.hasPrefix("fitting:") {
                        // 处理DNA装配链接
                        attributedString.replaceSubrange(
                            start ..< end, with: AttributedString(displayText)
                        )
                        attributedString[
                            start ..< attributedString.index(
                                start, offsetByCharacters: displayText.count
                            )
                        ].foregroundColor = .blue

                        // 直接使用fitting://格式，类似showinfo://
                        attributedString[
                            start ..< attributedString.index(
                                start, offsetByCharacters: displayText.count
                            )
                        ].link = URL(string: url)

                        Logger.debug(
                            "Processed DNA fitting URL - DNA: \(url), Text: \(displayText)")
                    } else if url.hasPrefix("killReport:") {
                        // 处理战斗日志链接
                        let killReportContent = String(url.dropFirst("killReport:".count))
                        let components = killReportContent.components(separatedBy: ":")
                        if let killIdString = components.first, let killId = Int(killIdString) {
                            attributedString.replaceSubrange(
                                start ..< end, with: AttributedString(displayText)
                            )
                            attributedString[
                                start ..< attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].foregroundColor = .blue
                            attributedString[
                                start ..< attributedString.index(
                                    start, offsetByCharacters: displayText.count
                                )
                            ].link = URL(string: "killreport://\(killId)")

                            Logger.debug(
                                "Processed killReport URL - ID: \(killId), Text: \(displayText)")
                        } else {
                            // 无效的killReport链接，只保留文本内容
                            attributedString.replaceSubrange(
                                start ..< end, with: AttributedString(displayText)
                            )
                            Logger.debug(
                                "Invalid killReport URL format - Text: \(displayText)")
                        }
                    } else {
                        // 处理普通URL
                        attributedString.replaceSubrange(
                            start ..< end, with: AttributedString(displayText)
                        )
                        attributedString[
                            start ..< attributedString.index(
                                start, offsetByCharacters: displayText.count
                            )
                        ].foregroundColor = .blue
                        // 使用自定义scheme来处理外部URL
                        if let encodedUrl = url.addingPercentEncoding(
                            withAllowedCharacters: .urlHostAllowed)
                        {
                            attributedString[
                                start ..< attributedString.index(
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
        var searchRange = currentText.startIndex ..< currentText.endIndex

        while let boldStart = currentText.range(of: "<b>", range: searchRange),
              let boldEnd = currentText.range(
                  of: "</b>", range: boldStart.upperBound ..< currentText.endIndex
              )
        {
            let boldTextRange = boldStart.upperBound ..< boldEnd.lowerBound
            let boldText = String(currentText[boldTextRange])
            let fullRange = boldStart.lowerBound ..< boldEnd.upperBound
            boldRanges.append((fullRange, boldText))
            searchRange = boldEnd.upperBound ..< currentText.endIndex
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
                    attrStartIndex ..< attrEndIndex, with: AttributedString(boldText)
                )

                let boldEndIndex = attributedString.index(
                    attrStartIndex, offsetByCharacters: boldText.count
                )
                // 使用最简单的粗体设置方式
                attributedString[attrStartIndex ..< boldEndIndex].inlinePresentationIntent =
                    .stronglyEmphasized

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
