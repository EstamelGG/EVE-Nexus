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
    let regex = try! NSRegularExpression(pattern: "<(?!br|b|url)(.*?)>", options: .caseInsensitive)
    processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: NSRange(location: 0, length: processedText.utf16.count), withTemplate: "")
    
    // 5. 替换多个连续的换行符为一个换行符
    processedText = processedText.replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
    
    // 6. 替换多个连续的空格为一个空格
    processedText = processedText.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
    
    return processedText
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
    
    var body: some View {
        Form {
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
                        .padding(.vertical, 8)
                    }
                    
                    let desc = filterText(itemDetails.description)
                    if !desc.isEmpty {
                        Text(.init(desc))
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.top, standardPadding)
                    }
                }
            } else {
                Section {
                    Text("Details not found")
                        .foregroundColor(.gray)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Info")
        .navigationBarBackButtonHidden(false)  // 显示返回按钮
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
                // 加载失败时保持使用原来的小图显示，不需要特殊处理
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

