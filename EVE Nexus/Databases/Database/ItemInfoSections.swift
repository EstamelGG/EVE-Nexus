import SwiftUI

/// 工业相关 Section 组件
struct IndustrySection: View {
    let itemID: Int
    let databaseManager: DatabaseManager
    let itemDetails: ItemDetails?

    var body: some View {
        let materials = databaseManager.getTypeMaterials(for: itemID)
        let blueprintID = databaseManager.getBlueprintIDForProduct(itemID)
        let groups_should_show_source = [18, 1996, 423, 427]
        // 只针对矿物、突变残渣、化学元素、同位素等产物展示精炼来源
        let sourceMaterials:
            [(typeID: Int, name: String, iconFileName: String, outputQuantityPerUnit: Double)]? =
                if let groupID = itemDetails?.groupID {
                    (groups_should_show_source.contains(groupID))
                        ? databaseManager.getSourceMaterials(for: itemID, groupID: groupID)
                        : nil
                } else {
                    nil
                }

        if materials != nil || blueprintID != nil || sourceMaterials != nil {
            Section(header: Text(NSLocalizedString("Industry", comment: "")).font(.headline)) {
                // 蓝图按钮
                if let blueprintID = blueprintID,
                    let blueprintDetails = databaseManager.getItemDetails(for: blueprintID)
                {
                    NavigationLink {
                        ItemInfoMap.getItemInfoView(
                            itemID: blueprintID,
                            databaseManager: databaseManager
                        )
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
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: material.outputMaterial
                                )
                            } label: {
                                HStack {
                                    IconManager.shared.loadImage(
                                        for: material.outputMaterialIcon
                                    )
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)

                                    Text(material.outputMaterialName)
                                        .font(.body)

                                    Spacer()

                                    Text("\(material.outputQuantity)")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .frame(alignment: .trailing)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image("reprocess")
                                .resizable()
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    "\(NSLocalizedString("Main_Database_Item_info_Reprocess", comment: ""))"
                                )
                                Text(
                                    "\(NSLocalizedString("Misc_per", comment: "")) \(materials[0].process_size) \(NSLocalizedString("Misc_unit", comment: ""))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(
                                "\(materials.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                            )
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }

                // 源物品下拉列表
                if let sourceMaterials = sourceMaterials, !sourceMaterials.isEmpty {
                    DisclosureGroup {
                        ForEach(sourceMaterials, id: \.typeID) { material in
                            NavigationLink {
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: material.typeID
                                )
                            } label: {
                                HStack {
                                    IconManager.shared.loadImage(for: material.iconFileName)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)

                                    Text(material.name)
                                        .font(.body)

                                    Spacer()

                                    Text(
                                        "\(FormatUtil.format(material.outputQuantityPerUnit))/\(NSLocalizedString("Misc_unit", comment: "")) "
                                    )
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            IconManager.shared.loadImage(
                                for: sourceMaterials[0].iconFileName
                            )
                            .resizable()
                            .frame(width: 32, height: 32)
                            Text(NSLocalizedString("Main_Database_Source", comment: ""))
                            Spacer()
                            Text(
                                "\(sourceMaterials.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                            )
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}
