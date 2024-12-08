import SwiftUI

// 用于过滤 HTML 标签并处理换行的函数
func filterText(_ text: String) -> String {
    // 1. 处理换行标签
    var processedText = text.replacingOccurrences(of: "<br>", with: "\n")
    
    // 2. 处理加粗标签，确保标签周围有空格
    processedText = processedText.replacingOccurrences(of: "<b>", with: " **")
    processedText = processedText.replacingOccurrences(of: "</b>", with: "** ")
    
    // 3. 处理URL标签
    let urlPattern = "<url=([^>]+)>([^<]*)</url>"
    let urlRegex = try! NSRegularExpression(pattern: urlPattern, options: [])
    while let match = urlRegex.firstMatch(in: processedText, options: [], range: NSRange(processedText.startIndex..<processedText.endIndex, in: processedText)) {
        guard let urlRange = Range(match.range(at: 1), in: processedText),
              let textRange = Range(match.range(at: 2), in: processedText),
              let fullRange = Range(match.range(at: 0), in: processedText) else {
            continue
        }
        
        let url = String(processedText[urlRange])
        let displayText = String(processedText[textRange])
        let markdownLink = " [\(displayText)](\(url)) "
        processedText.replaceSubrange(fullRange, with: markdownLink)
    }
    
    // 4. 删除其他HTML标签
    let regex = try! NSRegularExpression(pattern: "<(?!br|b|url|a)(.*?)>", options: .caseInsensitive)
    processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: NSRange(location: 0, length: processedText.utf16.count), withTemplate: "")
    
    // 5. 替换多个连续的换行符为一个换行符
    processedText = processedText.replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
    
    // 6. 替换多个连续的空格为一个空格
    processedText = processedText.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
    
    return processedText
}

// 处理trait文本，返回组合的Text视图
func processTraitText(_ text: String) -> Text {
    var result = Text("")
    var currentText = text
    
    // 处理换行标签
    currentText = currentText.replacingOccurrences(of: "<br></br>", with: "\n")
    currentText = currentText.replacingOccurrences(of: "<br>", with: "\n")
    currentText = currentText.replacingOccurrences(of: "</br>", with: "\n")
    
    while !currentText.isEmpty {
        // 1. 查找最近的特殊标签
        let boldStart = currentText.range(of: "<b>")
        let boldEnd = currentText.range(of: "</b>")
        let linkStart = currentText.range(of: "<a href=")
        let linkEnd = currentText.range(of: "</a>")
        
        // 2. 如果没有任何标签了，添加剩余文本并结束
        if boldStart == nil && linkStart == nil {
            result = result + Text(currentText)
            break
        }
        
        // 3. 处理加粗文本
        if let start = boldStart,
           let end = boldEnd,
           (linkStart == nil || start.lowerBound < linkStart!.lowerBound) {
            // 添加加粗标签前的普通文本
            let beforeBold = String(currentText[..<start.lowerBound])
            if !beforeBold.isEmpty {
                result = result + Text(beforeBold)
            }
            
            // 提取并添加加粗文本
            let boldText = String(currentText[start.upperBound..<end.lowerBound])
            result = result + Text(boldText).bold()
            
            // 更新剩余文本
            currentText = String(currentText[end.upperBound...])
            continue
        }
        
        // 4. 处理链接文本
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

// ShowItemInfo view
struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    var itemID: Int
    
    @State private var itemDetails: ItemDetails?
    @State private var renderImage: UIImage?
    
    // iOS 标准圆角半径
    private let cornerRadius: CGFloat = 10
    // 标准边距
    private let standardPadding: CGFloat = 16
    
    // 构建traits文本
    private func buildTraitsText(roleBonuses: [Trait], typeBonuses: [Trait], databaseManager: DatabaseManager) -> String {
        var text = ""
        
        // 添加Role Bonuses
        if !roleBonuses.isEmpty {
            text += "<b>Role Bonuses</b>\n"
            for bonus in roleBonuses {
                text += "- \(bonus.content).\n"
            }
        }
        
        // 添加Type Bonuses
        if !typeBonuses.isEmpty {
            let groupedBonuses = Dictionary(grouping: typeBonuses) { $0.skill }
            let sortedSkills = groupedBonuses.keys
                .compactMap { $0 }
                .sorted()
            
            for skill in sortedSkills {
                if let skillName = databaseManager.getTypeName(for: skill) {
                    text += "\n<b>\(skillName)</b> bonuses per level\n"
                    
                    let bonuses = groupedBonuses[skill]?.sorted(by: { $0.importance < $1.importance }) ?? []
                    for bonus in bonuses {
                        text += "- \(bonus.content).\n"
                    }
                }
            }
        }
        
        return text
    }
    
    var body: some View {
        List {
            if let itemDetails = itemDetails {
                Section {
                    if let renderImage = renderImage {
                        // 如果有渲染图，显示大图布局
                        ZStack(alignment: .bottomLeading) {
                            Image(uiImage: renderImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(cornerRadius)
                                .padding(.horizontal, standardPadding)
                                .padding(.vertical, standardPadding)
                            
                            // 物品信息覆盖层
                            VStack(alignment: .leading, spacing: 4) {
                                Text(itemDetails.name)
                                    .font(.title)
                                Text("\(itemDetails.categoryName) / \(itemDetails.groupName)")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, standardPadding * 2)
                            .padding(.vertical, standardPadding)
                            .background(
                                Color.black.opacity(0.5)
                                    .cornerRadius(cornerRadius, corners: [.bottomLeft, .topRight])
                            )
                            .foregroundColor(.white)
                            .padding(.horizontal, standardPadding)
                            .padding(.bottom, standardPadding)
                        }
                        .listRowInsets(EdgeInsets())  // 移除 List 的默认边距
                    } else {
                        // 如果没有渲染图，显示原来的布局
                        HStack {
                            IconManager.shared.loadImage(for: itemDetails.iconFileName)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(itemDetails.name)
                                    .font(.title)
                                Text("\(itemDetails.categoryName) / \(itemDetails.groupName)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    let desc = filterText(itemDetails.description)
                    if !desc.isEmpty {
                        Text(.init(desc))
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    
                    // 只有当有traits信息时才显示traits
                    if !itemDetails.roleBonuses.isEmpty || !itemDetails.typeBonuses.isEmpty {
                        processTraitText(buildTraitsText(
                            roleBonuses: itemDetails.roleBonuses,
                            typeBonuses: itemDetails.typeBonuses,
                            databaseManager: databaseManager
                        ))
                        .font(.body)
                        .lineSpacing(2)  // 减小行距
                    }
                }
            } else {
                Text("Details not found")
                    .foregroundColor(.gray)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Info")
        .navigationBarBackButtonHidden(false)
        .onAppear {
            loadItemDetails(for: itemID)
            loadRenderImage(for: itemID)
        }
    }
    
    // 加载 item 详细信息
    private func loadItemDetails(for itemID: Int) {
        if let itemDetail = databaseManager.loadItemDetails(for: itemID) {
            itemDetails = itemDetail
        } else {
            print("Item details not found for ID: \(itemID)")
        }
    }
    
    // 加载渲染图
    private func loadRenderImage(for itemID: Int) {
        Task {
            do {
                let image = try await NetworkManager.shared.fetchEVEItemRender(typeID: itemID)
                await MainActor.run {
                    self.renderImage = image
                }
            } catch {
                print("加载渲染图失败: \(error.localizedDescription)")
                // 加载失败时保持使用原来的小图显示，不需特殊处理
            }
        }
    }
}

// 用于设置特定角落圆角的扩展
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// 自定义圆角形
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

