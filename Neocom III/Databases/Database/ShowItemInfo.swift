import SwiftUI

// 用于过滤 HTML 标签并处理换行的函数
func filterText(_ text: String) -> String {
    // 1. 替换 <b> 和 </b> 标签为一个空格
    var filteredText = text.replacingOccurrences(of: "<b>", with: " ")
    filteredText = filteredText.replacingOccurrences(of: "</b>", with: " ")
    filteredText = filteredText.replacingOccurrences(of: "<br>", with: "\n")
    // 2. 替换 <link> 和 </link> 标签为一个空格
    filteredText = filteredText.replacingOccurrences(of: "<link.*?>", with: " ", options: .regularExpression)
    filteredText = filteredText.replacingOccurrences(of: "</link>", with: " ", options: .regularExpression)
    
    // 3. 删除其他 HTML 标签
    let regex = try! NSRegularExpression(pattern: "<(?!b|link)(.*?)>", options: .caseInsensitive)
    filteredText = regex.stringByReplacingMatches(in: filteredText, options: [], range: NSRange(location: 0, length: filteredText.utf16.count), withTemplate: "")
    
    // 4. 替换多个连续的换行符为一个换行符
    filteredText = filteredText.replacingOccurrences(of: "\n\n+", with: "\n\n", options: .regularExpression)
    
    return filteredText
}

// ShowItemInfo view
struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    var itemID: Int  // 从上一页面传递过来的 itemID
    
    @State private var itemDetails: ItemDetails? // 改为使用可选类型
    @State private var renderImage: UIImage? // 在线渲染图
    
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
                        Text(desc)
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
        .navigationTitle("Info")
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

// 自定义圆角形状
struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

