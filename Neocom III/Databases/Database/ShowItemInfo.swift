import SwiftUI

// ShowItemInfo view
struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    var itemID: Int
    
    @State private var itemDetails: ItemDetails?
    @State private var attributeGroups: [AttributeGroup] = []
    
    var body: some View {
        List {
            if let itemDetails = itemDetails {
                ItemBasicInfoView(itemDetails: itemDetails)
                
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
                        
                        // 回收材料下拉列表
                        if let materials = materials, !materials.isEmpty {
                            DisclosureGroup {
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
                                            IconManager.shared.loadImage(for: material.outputMaterialIcon)
                                                .resizable()
                                                .frame(width: 32, height: 32)
                                                .cornerRadius(6)
                                            
                                            Text(material.outputMaterialName)
                                                .font(.body)
                                            
                                            Spacer()
                                            
                                            Text("\(material.outputQuantity)")
                                                .font(.body)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image("reprocess")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                    Text(NSLocalizedString("Main_Database_Item_info_Reprocess", comment: ""))
                                    Spacer()
                                    Text("\(materials.count)\(NSLocalizedString("Misc_number_types", comment: ""))")
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
