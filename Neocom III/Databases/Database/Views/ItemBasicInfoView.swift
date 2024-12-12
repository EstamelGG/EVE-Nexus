import SwiftUI

struct ItemBasicInfoView: View {
    let itemDetails: ItemDetails
    @State private var renderImage: UIImage?
    
    // iOS 标准圆角半径
    private let cornerRadius: CGFloat = 10
    // 标准边距
    private let standardPadding: CGFloat = 16
    
    var body: some View {
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
                        Text("\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)")
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
                        Text("\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            let desc = itemDetails.description
            if !desc.isEmpty {
                RichTextProcessor.processRichText(desc)
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .onAppear {
            loadRenderImage(for: itemDetails.typeId)
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
                Logger.error("加载渲染图失败: \(error.localizedDescription)")
                // 加载失败时保持使用原来的小图显示，不需特殊处理
            }
        }
    }
} 
