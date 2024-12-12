import SwiftUI

// 添加新的结构体来存储链接信息
struct LinkInfo: Identifiable {
    let id = UUID()
    let typeID: Int
    let displayText: String
}

// 处理trait文本，现在返回View而不是Text
@ViewBuilder
func processRichText(_ text: String, databaseManager: DatabaseManager, showItemSheet: Binding<LinkInfo?>) -> some View {
    let processedText = processTextSegments(text, showItemSheet: showItemSheet)
    processedText
}

// 处理文本段落，返回Text
private func processTextSegments(_ text: String, showItemSheet: Binding<LinkInfo?>) -> some View {
    var segments: [AnyView] = []
    var currentText = text
    
    // 1. 处理换行标签
    currentText = currentText.replacingOccurrences(of: "<br></br>", with: "\n")
    currentText = currentText.replacingOccurrences(of: "<br>", with: "\n")
    currentText = currentText.replacingOccurrences(of: "</br>", with: "\n")
    
    // 2. 删除所有非白名单的HTML标签
    let pattern = "<(?!/?(b|a|br))[^>]*>"
    if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
        let range = NSRange(currentText.startIndex..<currentText.endIndex, in: currentText)
        currentText = regex.stringByReplacingMatches(in: currentText, options: [], range: range, withTemplate: "")
    }
    
    // 3. 优化连续换行和空格
    currentText = currentText.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    currentText = currentText.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
    
    while !currentText.isEmpty {
        // 查找所有标签位置
        let boldStarts = currentText.ranges(of: "<b>")
        let boldEnds = currentText.ranges(of: "</b>")
        let linkStart = currentText.range(of: "<a href=")
        let linkEnd = currentText.range(of: "</a>")
        
        // 如果没有任何标签了，添加剩余文本并结束
        if boldStarts.isEmpty && linkStart == nil {
            segments.append(AnyView(Text(currentText)))
            break
        }
        
        // 处理加粗文本
        if !boldStarts.isEmpty,
           !boldEnds.isEmpty,
           let firstStart = boldStarts.first,
           (linkStart == nil || firstStart.lowerBound < linkStart!.lowerBound) {
            let matchingEnd = boldEnds.first { $0.lowerBound > firstStart.upperBound }
            
            if let end = matchingEnd {
                let beforeBold = String(currentText[..<firstStart.lowerBound])
                if !beforeBold.isEmpty {
                    segments.append(AnyView(Text(beforeBold)))
                }
                
                let boldText = String(currentText[firstStart.upperBound..<end.lowerBound])
                segments.append(AnyView(Text(boldText).bold()))
                
                currentText = String(currentText[end.upperBound...])
                continue
            }
        }
        
        // 处理链接文本
        if let start = linkStart,
           let end = linkEnd {
            let beforeLink = String(currentText[..<start.lowerBound])
            if !beforeLink.isEmpty {
                segments.append(AnyView(Text(beforeLink)))
            }
            
            let linkText = currentText[start.lowerBound..<end.upperBound]
            if let hrefStart = linkText.range(of: "showinfo:"),
               let textStart = linkText.range(of: ">")?.upperBound,
               let textEnd = linkText.range(of: "</a>")?.lowerBound {
                let typeIDEndIndex = linkText[hrefStart.upperBound...].firstIndex(where: { !$0.isNumber }) ?? linkText.endIndex
                let typeIDString = String(linkText[hrefStart.upperBound..<typeIDEndIndex])
                let displayText = String(linkText[textStart..<textEnd])
                
                if let typeID = Int(typeIDString) {
                    segments.append(AnyView(
                        Text(displayText)
                            .foregroundColor(.blue)
                            .underline()
                            .onTapGesture {
                                showItemSheet.wrappedValue = LinkInfo(typeID: typeID, displayText: displayText)
                            }
                    ))
                }
            }
            
            currentText = String(currentText[end.upperBound...])
            continue
        }
        
        segments.append(AnyView(Text(currentText)))
        break
    }
    
    return HStack(spacing: 0) {
        ForEach(0..<segments.count, id: \.self) { index in
            segments[index]
        }
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

// ShowItemInfo view
struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    var itemID: Int
    
    @State private var itemDetails: ItemDetails?
    @State private var attributeGroups: [AttributeGroup] = []
    @State private var selectedLink: LinkInfo?
    
    var body: some View {
        List {
            if let itemDetails = itemDetails {
                ItemBasicInfoView(itemDetails: itemDetails, databaseManager: databaseManager)
                
                // 变体 Section（如果有的话）
                let variationsCount = databaseManager.getVariationsCount(for: itemID)
                if variationsCount > 1 {
                    Section {
                        NavigationLink(destination: VariationsView(databaseManager: databaseManager, typeID: itemID)) {
                            Text(String(format: NSLocalizedString("Main_Database_Browse_Variations", comment: ""), variationsCount))
                        }
                    } header: {
                        Text(NSLocalizedString("Main_Database_Variations", comment: ""))
                            .font(.headline)
                    }
                }
                
                // 属性 Sections
                AttributesView(attributeGroups: attributeGroups, databaseManager: databaseManager)
                
                // Industry Section
                let materials = databaseManager.getTypeMaterials(for: itemID)
                let blueprintID = databaseManager.getBlueprintIDForProduct(itemID)
                if materials != nil || blueprintID != nil {
                    Section(header: Text("Industry").font(.headline)) {
                        // 蓝图按钮
                        if let blueprintID = blueprintID,
                           let blueprintDetails = databaseManager.getItemDetails(for: blueprintID) {
                            NavigationLink {
                                ShowBluePrintInfo(blueprintID: blueprintID, databaseManager: databaseManager)
                            } label: {
                                HStack {
                                    IconManager.shared.loadImage(for: blueprintDetails.iconFileName)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)
                                    Text(blueprintDetails.name)
                                    Spacer()
                                }
                            }
                        }
                        
                        // 回收按钮
                        if let materials = materials, !materials.isEmpty {
                            NavigationLink {
                                ReprocessMaterialsView(itemID: itemID, databaseManager: databaseManager)
                            } label: {
                                HStack {
                                    Image("reprocess")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                    Text(NSLocalizedString("Main_Database_Item_info_Reprocess", comment: ""))
                                    Spacer()
                                    Text("\(materials.count)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Details not found")
                    .foregroundColor(.gray)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Item_Info", comment: ""))
        .navigationBarBackButtonHidden(false)
        .sheet(item: $selectedLink) { linkInfo in
            NavigationView {
                ShowItemInfo(databaseManager: databaseManager, itemID: linkInfo.typeID)
                    .navigationBarItems(trailing: Button("关闭") {
                        selectedLink = nil
                    })
            }
        }
        .onAppear {
            loadItemDetails(for: itemID)
            loadAttributes(for: itemID)
        }
    }
    
    // 加载 item 详细信息
    private func loadItemDetails(for itemID: Int) {
        if let itemDetail = databaseManager.loadItemDetails(for: itemID) {
            itemDetails = itemDetail
        } else {
            Logger.error("Item details not found for ID: \(itemID)")
        }
    }
    
    // 加载属性
    private func loadAttributes(for itemID: Int) {
        attributeGroups = databaseManager.loadAttributeGroups(for: itemID)
        // 初始化属性单位
        let units = databaseManager.loadAttributeUnits()
        AttributeDisplayConfig.initializeUnits(with: units)
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

// 重新加工材料列表视图
struct ReprocessMaterialsView: View {
    let itemID: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    var body: some View {
        List {
            if let materials = databaseManager.getTypeMaterials(for: itemID) {
                ForEach(materials, id: \.outputMaterial) { material in
                    NavigationLink {
                        if let categoryID = databaseManager.getCategoryID(for: material.outputMaterial) {
                            ItemInfoMap.getItemInfoView(
                                itemID: material.outputMaterial,
                                categoryID: categoryID,
                                databaseManager: databaseManager
                            )
                        }
                    } label: {
                        HStack {
                            // 材料图标
                            IconManager.shared.loadImage(for: material.outputMaterialIcon)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            
                            // 材料名称
                            Text(material.outputMaterialName)
                                .font(.body)
                            
                            Spacer()
                            
                            // 数量
                            Text("\(material.outputQuantity)")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Database_Item_info_Reprocess_Materials", comment: ""))
    }
}
