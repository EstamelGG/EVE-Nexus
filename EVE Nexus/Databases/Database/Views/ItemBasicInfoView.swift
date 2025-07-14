import SwiftUI

struct ItemBasicInfoView: View {
    let itemDetails: ItemDetails
    @State private var renderImage: UIImage?
    @ObservedObject var databaseManager: DatabaseManager
    let modifiedAttributes: [Int: Double]?

    // iOS 标准圆角半径
    private let cornerRadius: CGFloat = 10
    // 标准边距
    private let standardPadding: CGFloat = 16

    // 获取修改后的属性值，如果没有则返回原始值
    private func getAttributeValue(attributeId: Int, originalValue: Double?) -> Double? {
        if let modifiedValue = modifiedAttributes?[attributeId] {
            return modifiedValue
        }
        return originalValue
    }
    
    // 获取属性值的颜色
    private func getAttributeColor(attributeId: Int, originalValue: Double?) -> Color {
        guard let originalValue = originalValue,
              let modifiedValue = modifiedAttributes?[attributeId] else {
            return .secondary
        }
        
        if abs(modifiedValue - originalValue) < 0.0001 {
            return .secondary // 没有变化
        }
        
        // 对于 mass 和 capacity，通常值越大越好（capacity）或越小越好（mass）
        // mass(4): 质量，越小越好，所以 highIsGood = false
        // capacity(38): 容量，越大越好，所以 highIsGood = true
        let highIsGood = (attributeId == 38) // capacity 是 highIsGood
        
        if highIsGood {
            return modifiedValue > originalValue ? .green : .red
        } else {
            return modifiedValue < originalValue ? .green : .red
        }
    }

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
                        Text(
                            "\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
                        )
                        .font(.subheadline)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = itemDetails.name
                        } label: {
                            Label(NSLocalizedString("Misc_Copy_Name", comment: ""), systemImage: "doc.on.doc")
                        }
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
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = itemDetails.name
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy_Name", comment: ""), systemImage: "doc.on.doc")
                                }
                            }
                        Text(
                            "\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
                        )
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
            Logger.debug(
                "物品 \(itemDetails.name) 的 marketGroupID: \(String(describing: itemDetails.marketGroupID))"
            )
            if let marketGroupID = itemDetails.marketGroupID {
                Logger.debug("显示市场按钮，marketGroupID: \(marketGroupID)")
            }
        }

        // 市场详情 Section
        if itemDetails.marketGroupID != nil {
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
        if itemDetails.volume != nil || itemDetails.capacity != nil || itemDetails.mass != nil
            || itemDetails.repackagedVolume != nil
        {
            Section(header: Text(NSLocalizedString("Item_Basic_Info", comment: "")).font(.headline))
            {
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

                if let repackagedVolume = itemDetails.repackagedVolume {
                    HStack {
                        Image("packages")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(NSLocalizedString("Item_RepackagesVolume", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.format(Double(repackagedVolume))) m3")
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }

                if let capacity = itemDetails.capacity {
                    let finalCapacity = getAttributeValue(attributeId: 38, originalValue: Double(capacity)) ?? Double(capacity)
                    let capacityColor = getAttributeColor(attributeId: 38, originalValue: Double(capacity))
                    
                    HStack {
                        Image("cargo_fit")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(NSLocalizedString("Item_Capacity", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.format(finalCapacity)) m3")
                            .foregroundColor(capacityColor)
                            .frame(alignment: .trailing)
                    }
                }

                if let mass = itemDetails.mass {
                    let finalMass = getAttributeValue(attributeId: 4, originalValue: Double(mass)) ?? Double(mass)
                    let massColor = getAttributeColor(attributeId: 4, originalValue: Double(mass))
                    
                    HStack {
                        Image("hull")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(NSLocalizedString("Item_Mass", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.format(finalMass)) Kg")
                            .foregroundColor(massColor)
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
                let image = try await ItemRenderAPI.shared.fetchItemRender(
                    typeId: itemID, size: 512
                )
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
