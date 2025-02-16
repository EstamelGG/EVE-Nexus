import SwiftUI

struct ItemBasicInfoView: View {
    let itemDetails: ItemDetails
    @State private var renderImage: UIImage?
    @ObservedObject var databaseManager: DatabaseManager
    
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
                RichTextView(text: desc, databaseManager: databaseManager)
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .onAppear {
            loadRenderImage(for: itemDetails.typeId)
            // 调试输出移到这里
            Logger.debug("物品 \(itemDetails.name) 的 marketGroupID: \(String(describing: itemDetails.marketGroupID))")
            if let marketGroupID = itemDetails.marketGroupID {
                Logger.debug("显示市场按钮，marketGroupID: \(marketGroupID)")
            }
        }
        
        // 市场详情 Section
        if let _ = itemDetails.marketGroupID {
            Section {
                NavigationLink {
                    MarketItemDetailView(
                        databaseManager: databaseManager,
                        itemID: itemDetails.typeId
                    )
                } label: {
                    HStack {
                        Image("isk")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(NSLocalizedString("Main_Market", comment: ""))
                        Spacer()
                    }
                }
            }
        }
        
        // 基础属性 Section
        if itemDetails.volume != nil || itemDetails.capacity != nil || itemDetails.mass != nil {
            Section(header: Text(NSLocalizedString("Item_Basic_Info", comment: "")).font(.headline)) {
                if let volume = itemDetails.volume {
                    HStack {
                        Image("structure")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(NSLocalizedString("Item_Volume", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.format(Double(volume))) m3")
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }
                
                if let capacity = itemDetails.capacity {
                    HStack {
                        Image("cargo_fit")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(NSLocalizedString("Item_Capacity", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.format(Double(capacity))) m3")
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }
                
                if let mass = itemDetails.mass {
                    HStack {
                        Image("hull")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(NSLocalizedString("Item_Mass", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.format(Double(mass))) Kg")
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }
            }
        }
    }
    
    // 加载渲染图
    private func loadRenderImage(for itemID: Int) {
        Task {
            do {
                let image = try await ItemRenderAPI.shared.fetchItemRender(typeId: itemID, size: 512)
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
