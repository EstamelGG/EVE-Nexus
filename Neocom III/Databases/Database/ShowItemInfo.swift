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
                ItemBasicInfoView(itemDetails: itemDetails, databaseManager: databaseManager)
                
                // 基础属性 Section
                if itemDetails.volume != nil || itemDetails.capacity != nil || itemDetails.mass != nil {
                    Section(header: Text(NSLocalizedString("Item_Basic_Info", comment: "")).font(.headline)) {
                        if let volume = itemDetails.volume {
                            HStack {
                                IconManager.shared.loadImage(for: "items_2_64_9.png")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(NSLocalizedString("Item_Volume", comment: ""))
                                Spacer()
                                Text("\(NumberFormatUtil.format(Double(volume))) m3")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let capacity = itemDetails.capacity {
                            HStack {
                                IconManager.shared.loadImage(for: "items_3_64_13.png")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(NSLocalizedString("Item_Capacity", comment: ""))
                                Spacer()
                                Text("\(NumberFormatUtil.format(Double(capacity))) m3")
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let mass = itemDetails.mass {
                            HStack {
                                IconManager.shared.loadImage(for: "items_2_64_10.png")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(NSLocalizedString("Item_Mass", comment: ""))
                                Spacer()
                                Text("\(NumberFormatUtil.format(Double(mass))) Kg")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
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
                // 只针对矿物、突变残渣、化学元素、同位素等产物展示精炼来源
                let sourceMaterials: [(typeID: Int, name: String, iconFileName: String, outputQuantityPerUnit: Double)]? = if let groupID = itemDetails.groupID {
                    ([18, 1996, 423, 427].contains(groupID)) ? databaseManager.getSourceMaterials(for: itemID, groupID: groupID) : nil
                } else {
                    nil
                }
                
                if materials != nil || blueprintID != nil || sourceMaterials != nil {
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
                                    Text("\(NSLocalizedString("Main_Database_Item_info_Reprocess", comment: ""))(\(NSLocalizedString("Misc_per", comment: "")) \(materials[0].process_size) \(NSLocalizedString("Misc_unit", comment: "")))")
                                    Spacer()
                                    Text("\(materials.count)\(NSLocalizedString("Misc_number_types", comment: ""))")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        // 源物品下拉列表
                        if let sourceMaterials = sourceMaterials, !sourceMaterials.isEmpty {
                            DisclosureGroup {
                                ForEach(sourceMaterials, id: \.typeID) { material in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(for: material.typeID) {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: material.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(for: material.iconFileName)
                                                .resizable()
                                                .frame(width: 32, height: 32)
                                                .cornerRadius(6)
                                            
                                            Text(material.name)
                                                .font(.body)
                                            
                                            Spacer()
                                            
                                            Text("\(NumberFormatUtil.format(material.outputQuantityPerUnit))/\(NSLocalizedString("Misc_unit", comment: "")) ")
                                                .font(.body)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    IconManager.shared.loadImage(for: sourceMaterials[0].iconFileName)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                    Text(NSLocalizedString("Main_Database_Source", comment: ""))
                                    Spacer()
                                    Text("\(sourceMaterials.count)\(NSLocalizedString("Misc_number_types", comment: ""))")
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
