import SwiftUI

let itemSectionRowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

/// 工业相关 Section
struct IndustrySection: View {
    let itemID: Int
    let databaseManager: DatabaseManager
    let itemDetails: ItemDetails?

    private let sourceGroups = [18, 1996, 423, 427]

    var body: some View {
        let materials = databaseManager.getTypeMaterials(for: itemID)
        let randomizedMaterials = databaseManager.getTypeRandomizedMaterials(for: itemID)
        let blueprintIDs = databaseManager.getBlueprintIDsForProduct(itemID)
        let sourceMaterials:
            [(typeID: Int, name: String, iconFileName: String, outputQuantityPerUnit: Double)]? =
                if let groupID = itemDetails?.groupID, sourceGroups.contains(groupID) {
                    databaseManager.getSourceMaterials(for: itemID, groupID: groupID)
                } else {
                    nil
                }
        let blueprintDest = databaseManager.getBlueprintDest(for: itemID)

        if materials != nil
            || randomizedMaterials != nil
            || !blueprintIDs.isEmpty
            || sourceMaterials != nil
            || !blueprintDest.blueprints.isEmpty
        {
            Section(header: Text(NSLocalizedString("Industry", comment: "")).font(.headline)) {
                ForEach(blueprintIDs, id: \.self) { blueprintID in
                    if let blueprintDetails = databaseManager.getItemDetails(for: blueprintID) {
                        NavigationLink {
                            ItemInfoMap.getItemInfoView(
                                itemID: blueprintID,
                                databaseManager: databaseManager
                            )
                        } label: {
                            ItemIconNameRow(
                                iconFileName: blueprintDetails.iconFileName,
                                name: blueprintDetails.name
                            )
                        }
                    }
                }
                .listRowInsets(itemSectionRowInsets)

                if !blueprintDest.blueprints.isEmpty {
                    NavigationLink {
                        BlueprintDestView(
                            itemID: itemID,
                            databaseManager: databaseManager,
                            blueprintDest: blueprintDest
                        )
                    } label: {
                        HStack {
                            IconManager.shared.loadImage(for: "blueprints")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            VStack(alignment: .leading) {
                                Text(
                                    NSLocalizedString(
                                        "Main_Database_Applicable_Blueprints", comment: ""
                                    )
                                )
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                                Text(
                                    NSLocalizedString(
                                        "Main_Database_Applicable_Blueprints_info", comment: ""
                                    )
                                )
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            }
                            Spacer()
                            Text(
                                "\(blueprintDest.blueprints.count) \(NSLocalizedString("Misc_number_items", comment: ""))"
                            )
                            .foregroundColor(.secondary)
                        }
                    }
                    .listRowInsets(itemSectionRowInsets)
                }

                if let materials, !materials.isEmpty {
                    DisclosureGroup {
                        ForEach(materials, id: \.outputMaterial) { material in
                            NavigationLink {
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: material.outputMaterial
                                )
                            } label: {
                                HStack {
                                    IconManager.shared.loadImage(for: material.outputMaterialIcon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)
                                    Text(material.outputMaterialName)
                                        .font(.body)
                                    Spacer()
                                    Text("× \(material.outputQuantity)")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .frame(alignment: .trailing)
                                }
                            }
                        }
                        .listRowInsets(itemSectionRowInsets)
                    } label: {
                        HStack {
                            Image("reprocess")
                                .resizable()
                                .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    NSLocalizedString(
                                        "Main_Database_Item_info_Reprocess", comment: ""
                                    )
                                )
                                Text(
                                    "\(NSLocalizedString("Misc_per", comment: "")) \(materials[0].process_size) \(NSLocalizedString("Misc_unit", comment: ""))"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(
                                "\(materials.count)\(NSLocalizedString("Misc_number_items", comment: ""))"
                            )
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                        }
                    }
                    .listRowInsets(itemSectionRowInsets)
                }

                if let randomizedMaterials, !randomizedMaterials.isEmpty {
                    DisclosureGroup {
                        ForEach(randomizedMaterials, id: \.materialTypeID) { material in
                            NavigationLink {
                                ShowItemInfo(
                                    databaseManager: databaseManager,
                                    itemID: material.materialTypeID
                                )
                            } label: {
                                HStack {
                                    IconManager.shared.loadImage(for: material.materialIcon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)
                                    Text(material.materialName)
                                        .font(.body)
                                    Spacer()
                                    Text("\(material.quantityMin) - \(material.quantityMax)")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .frame(alignment: .trailing)
                                }
                            }
                        }
                        .listRowInsets(itemSectionRowInsets)
                    } label: {
                        HStack {
                            Image("reprocess")
                                .resizable()
                                .frame(width: 32, height: 32)
                            Text(NSLocalizedString("Main_Database_Randomized_Output", comment: ""))
                            Spacer()
                            Text(
                                "\(randomizedMaterials.count)\(NSLocalizedString("Misc_number_items", comment: ""))"
                            )
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                        }
                    }
                    .listRowInsets(itemSectionRowInsets)
                }

                if let sourceMaterials, !sourceMaterials.isEmpty {
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
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(material.name)
                                            .font(.body)
                                        Text(
                                            "\(FormatUtil.format(material.outputQuantityPerUnit))/\(NSLocalizedString("Misc_unit", comment: ""))"
                                        )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .listRowInsets(itemSectionRowInsets)
                    } label: {
                        HStack {
                            IconManager.shared.loadImage(for: sourceMaterials[0].iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                            Text(NSLocalizedString("Main_Database_refine_Source", comment: ""))
                            Spacer()
                            Text(
                                "\(sourceMaterials.count)\(NSLocalizedString("Misc_number_items", comment: ""))"
                            )
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                        }
                    }
                    .listRowInsets(itemSectionRowInsets)
                }
            }
        }
    }
}

/// 蓝图目标视图
struct BlueprintDestView: View {
    let itemID: Int
    let databaseManager: DatabaseManager
    let blueprintDest: (
        blueprints: [(typeID: Int, name: String, iconFileName: String)],
        groups: [(groupID: Int, name: String, iconFileName: String)]
    )

    var body: some View {
        if blueprintDest.blueprints.count <= 50 {
            List {
                ForEach(blueprintDest.blueprints, id: \.typeID) { blueprint in
                    NavigationLink {
                        ItemInfoMap.getItemInfoView(
                            itemID: blueprint.typeID,
                            databaseManager: databaseManager
                        )
                    } label: {
                        ItemIconNameRow(iconFileName: blueprint.iconFileName, name: blueprint.name)
                    }
                }
                .listRowInsets(itemSectionRowInsets)
            }
            .navigationTitle(NSLocalizedString("Main_Database_Applicable_Blueprints", comment: ""))
        } else {
            List {
                ForEach(blueprintDest.groups, id: \.groupID) { group in
                    NavigationLink {
                        BlueprintGroupView(
                            groupID: group.groupID,
                            groupName: group.name,
                            databaseManager: databaseManager,
                            itemID: itemID
                        )
                    } label: {
                        ItemIconNameRow(iconFileName: group.iconFileName, name: group.name)
                    }
                }
                .listRowInsets(itemSectionRowInsets)
            }
            .navigationTitle(NSLocalizedString("Main_Database_Applicable_Blueprints", comment: ""))
        }
    }
}

/// 蓝图组视图
struct BlueprintGroupView: View {
    let groupID: Int
    let groupName: String
    let databaseManager: DatabaseManager
    let itemID: Int

    var body: some View {
        let (blueprints, _) = databaseManager.getBlueprintDest(for: itemID)
        let groupBlueprints = blueprints.filter { blueprint in
            databaseManager.getItemDetails(for: blueprint.typeID)?.groupID == groupID
        }

        List {
            ForEach(groupBlueprints, id: \.typeID) { blueprint in
                NavigationLink {
                    ItemInfoMap.getItemInfoView(
                        itemID: blueprint.typeID,
                        databaseManager: databaseManager
                    )
                } label: {
                    ItemIconNameRow(iconFileName: blueprint.iconFileName, name: blueprint.name)
                }
            }
            .listRowInsets(itemSectionRowInsets)
        }
        .navigationTitle(groupName)
    }
}

/// 变体 Section
struct VariationsSection: View {
    let typeID: Int
    let databaseManager: DatabaseManager

    var body: some View {
        let variationsCount = databaseManager.getVariationsCount(for: typeID)
        if variationsCount > 1 {
            Section {
                NavigationLink(
                    destination: VariationsView(
                        databaseManager: databaseManager,
                        typeID: typeID
                    )
                ) {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Main_Database_Browse_Variations", comment: ""
                            ),
                            variationsCount
                        )
                    )
                }
            } header: {
                Text(NSLocalizedString("Main_Database_Variations", comment: ""))
                    .font(.headline)
            }
        }
    }
}

/// 技能相关 Section
struct SkillSection: View {
    let skillID: Int
    let currentCharacterId: Int
    let databaseManager: DatabaseManager

    var body: some View {
        SkillPointForLevelView(
            skillId: skillID,
            characterId: currentCharacterId == 0 ? nil : currentCharacterId,
            databaseManager: databaseManager
        )
        SkillDependencySection(
            skillID: skillID,
            databaseManager: databaseManager
        )
    }
}

/// 突变来源（设备 + 所需突变体）Section
/// 共享一次 getMutationSource 查询结果，避免两个独立 Section 各查询一次
struct MutationSourceSection: View {
    let itemID: Int
    let databaseManager: DatabaseManager

    var body: some View {
        let mutationSource = databaseManager.getMutationSource(for: itemID)
        if !mutationSource.sourceItems.isEmpty {
            Section(
                header: Text(NSLocalizedString("Main_Database_Mutation_Source", comment: ""))
                    .font(.headline)
            ) {
                ForEach(mutationSource.sourceItems, id: \.typeID) { item in
                    NavigationLink {
                        ShowItemInfo(databaseManager: databaseManager, itemID: item.typeID)
                    } label: {
                        ItemIconNameRow(iconFileName: item.iconFileName, name: item.name)
                    }
                }
                .listRowInsets(itemSectionRowInsets)
            }

            if !mutationSource.mutaplasmids.isEmpty {
                Section(
                    header: Text(
                        NSLocalizedString("Main_Database_Required_Mutaplasmids", comment: "")
                    )
                    .font(.headline)
                ) {
                    ForEach(mutationSource.mutaplasmids, id: \.typeID) { mutaplasmid in
                        NavigationLink {
                            ShowMutationInfo(
                                itemID: mutaplasmid.typeID,
                                databaseManager: databaseManager
                            )
                        } label: {
                            ItemIconNameRow(
                                iconFileName: mutaplasmid.iconFileName,
                                name: mutaplasmid.name
                            )
                        }
                    }
                    .listRowInsets(itemSectionRowInsets)
                }
            }
        }
    }
}

/// 突变结果 Section
struct MutationResultsSection: View {
    let itemID: Int
    let databaseManager: DatabaseManager

    var body: some View {
        let mutationResults = databaseManager.getMutationResults(for: itemID)
        if !mutationResults.isEmpty {
            Section(
                header: Text(NSLocalizedString("Main_Database_Mutation_Results", comment: ""))
                    .font(.headline)
            ) {
                ForEach(mutationResults, id: \.typeID) { result in
                    NavigationLink {
                        ShowItemInfo(databaseManager: databaseManager, itemID: result.typeID)
                    } label: {
                        ItemIconNameRow(iconFileName: result.iconFileName, name: result.name)
                    }
                }
                .listRowInsets(itemSectionRowInsets)
            }
        }
    }
}

/// 所需突变体 Section
struct RequiredMutaplasmidsSection: View {
    let itemID: Int
    let databaseManager: DatabaseManager

    var body: some View {
        let requiredMutaplasmids = databaseManager.getRequiredMutaplasmids(for: itemID)
        if !requiredMutaplasmids.isEmpty {
            Section(
                header: Text(NSLocalizedString("Main_Database_Required_Mutaplasmids", comment: ""))
                    .font(.headline)
            ) {
                NavigationLink {
                    MutationCalculatorView(
                        databaseManager: databaseManager,
                        preselectedItemID: itemID
                    )
                } label: {
                    HStack {
                        Image("calculator")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(NSLocalizedString("Calculator_Mutation", comment: ""))
                            .font(.body)
                        Spacer(minLength: 0)
                    }
                }
                .listRowInsets(itemSectionRowInsets)

                ForEach(requiredMutaplasmids, id: \.typeID) { mutaplasmid in
                    NavigationLink {
                        ShowMutationInfo(
                            itemID: mutaplasmid.typeID,
                            databaseManager: databaseManager
                        )
                    } label: {
                        ItemIconNameRow(
                            iconFileName: mutaplasmid.iconFileName,
                            name: mutaplasmid.name
                        )
                    }
                }
                .listRowInsets(itemSectionRowInsets)
            }
        }
    }
}

/// 图标 + 名称行（列表详情通用）
private struct ItemIconNameRow: View {
    let iconFileName: String
    let name: String

    var body: some View {
        HStack {
            IconManager.shared.loadImage(for: iconFileName)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            Text(name)
                .font(.body)
            Spacer(minLength: 0)
        }
    }
}
