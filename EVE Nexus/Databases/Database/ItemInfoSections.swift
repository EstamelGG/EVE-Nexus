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
        
        // 获取可以制造该物品的蓝图列表
        let blueprintDest = databaseManager.getBlueprintDest(for: itemID)

        if materials != nil || blueprintID != nil || sourceMaterials != nil || !blueprintDest.blueprints.isEmpty {
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

                // 可以制造该物品的蓝图列表跳转链接
                if !blueprintDest.blueprints.isEmpty {
                    NavigationLink {
                        BlueprintDestView(
                            itemID: itemID,
                            databaseManager: databaseManager,
                            blueprintDest: blueprintDest
                        )
                    } label: {
                        HStack {
                            IconManager.shared.loadImage(for: "items_9_64_15.png")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Main_Database_Applicable_Blueprints", comment: ""))
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
                            Text("\(blueprintDest.blueprints.count) \(NSLocalizedString("Misc_number_types", comment: ""))")
                                .foregroundColor(.secondary)
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

                                    Text("\(material.outputQuantity) \(NSLocalizedString("Misc_unit", comment: ""))")
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

// 蓝图目标视图
struct BlueprintDestView: View {
    let itemID: Int
    let databaseManager: DatabaseManager
    let blueprintDest: (blueprints: [(typeID: Int, name: String, iconFileName: String)], groups: [(groupID: Int, name: String, iconFileName: String)])
    
    var body: some View {
        if blueprintDest.blueprints.count <= 50 {
            // 直接显示蓝图列表
            List {
                ForEach(blueprintDest.blueprints, id: \.typeID) { blueprint in
                    NavigationLink {
                        ItemInfoMap.getItemInfoView(
                            itemID: blueprint.typeID,
                            databaseManager: databaseManager
                        )
                    } label: {
                        HStack {
                            IconManager.shared.loadImage(for: blueprint.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(blueprint.name)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Database_Applicable_Blueprints", comment: ""))
        } else {
            // 显示组列表
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
                        HStack {
                            IconManager.shared.loadImage(for: group.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(group.name)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Database_Applicable_Blueprints", comment: ""))
        }
    }
}

// 蓝图组视图
struct BlueprintGroupView: View {
    let groupID: Int
    let groupName: String
    let databaseManager: DatabaseManager
    let itemID: Int
    
    var body: some View {
        let (blueprints, _) = databaseManager.getBlueprintDest(for: itemID)
        let groupBlueprints = blueprints.filter { blueprint in
            if let details = databaseManager.getItemDetails(for: blueprint.typeID) {
                return details.groupID == groupID
            }
            return false
        }
        
        List {
            ForEach(groupBlueprints, id: \.typeID) { blueprint in
                NavigationLink {
                    ItemInfoMap.getItemInfoView(
                        itemID: blueprint.typeID,
                        databaseManager: databaseManager
                    )
                } label: {
                    HStack {
                        IconManager.shared.loadImage(for: blueprint.iconFileName)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                        Text(blueprint.name)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(groupName)
    }
}

/// 变体 Section 组件
struct VariationsSection: View {
    let typeID: Int
    let databaseManager: DatabaseManager
    
    var body: some View {
        let variationsCount = databaseManager.getVariationsCount(for: typeID)
        if variationsCount > 1 {
            Section {
                NavigationLink(
                    destination: VariationsView(
                        databaseManager: databaseManager, typeID: typeID
                    )
                ) {
                    Text(
                        String(
                            format: NSLocalizedString(
                                "Main_Database_Browse_Variations", comment: ""
                            ),
                            variationsCount
                        ))
                }
            } header: {
                Text(NSLocalizedString("Main_Database_Variations", comment: ""))
                    .font(.headline)
            }
        }
    }
}

/// 技能相关 Section 组件
struct SkillSection: View {
    let skillID: Int
    let currentCharacterId: Int
    let databaseManager: DatabaseManager
    
    var body: some View {
        VStack(spacing: 0) {
            // 技能点数和训练时间列表
            SkillPointForLevelView(
                skillId: skillID,
                characterId: currentCharacterId == 0 ? nil : currentCharacterId,
                databaseManager: databaseManager
            )
            
            // 依赖该技能的物品列表
            SkillDependencySection(
                skillID: skillID,
                databaseManager: databaseManager
            )
        }
    }
}

/// 突变来源设备 Section 组件
struct MutationSourceItemsSection: View {
    let itemID: Int
    let databaseManager: DatabaseManager
    
    var body: some View {
        let mutationSource = databaseManager.getMutationSource(for: itemID)
        if !mutationSource.sourceItems.isEmpty {
            Section(
                header: Text(
                    NSLocalizedString("Main_Database_Mutation_Source", comment: "")
                ).font(.headline)
            ) {
                ForEach(mutationSource.sourceItems, id: \.typeID) { item in
                    NavigationLink {
                        ShowItemInfo(databaseManager: databaseManager, itemID: item.typeID)
                    } label: {
                        HStack {
                            IconManager.shared.loadImage(for: item.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)

                            Text(item.name)
                                .font(.body)
                        }
                    }
                }
            }
        }
    }
}

/// 突变来源质体 Section 组件
struct MutationSourceMutaplasmidsSection: View {
    let itemID: Int
    let databaseManager: DatabaseManager
    
    var body: some View {
        let mutationSource = databaseManager.getMutationSource(for: itemID)
        if !mutationSource.sourceItems.isEmpty && !mutationSource.mutaplasmids.isEmpty {
            Section(
                header: Text(
                    NSLocalizedString("Main_Database_Required_Mutaplasmids", comment: "")
                ).font(.headline)
            ) {
                ForEach(mutationSource.mutaplasmids, id: \.typeID) { mutaplasmid in
                    NavigationLink {
                        ShowMutationInfo(
                            itemID: mutaplasmid.typeID, databaseManager: databaseManager)
                    } label: {
                        HStack {
                            IconManager.shared.loadImage(for: mutaplasmid.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)

                            Text(mutaplasmid.name)
                                .font(.body)
                        }
                    }
                }
            }
        }
    }
}

/// 突变结果 Section 组件
struct MutationResultsSection: View {
    let itemID: Int
    let databaseManager: DatabaseManager
    
    var body: some View {
        let mutationResults = databaseManager.getMutationResults(for: itemID)
        if !mutationResults.isEmpty {
            Section(
                header: Text(
                    NSLocalizedString("Main_Database_Mutation_Results", comment: "")
                ).font(.headline)
            ) {
                ForEach(mutationResults, id: \.typeID) { result in
                    NavigationLink {
                        ShowItemInfo(
                            databaseManager: databaseManager, itemID: result.typeID)
                    } label: {
                        HStack {
                            IconManager.shared.loadImage(for: result.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)

                            Text(result.name)
                                .font(.body)
                        }
                    }
                }
            }
        }
    }
}

/// 所需突变体 Section 组件
struct RequiredMutaplasmidsSection: View {
    let itemID: Int
    let databaseManager: DatabaseManager
    
    var body: some View {
        let requiredMutaplasmids = databaseManager.getRequiredMutaplasmids(for: itemID)
        if !requiredMutaplasmids.isEmpty {
            Section(
                header: Text(
                    NSLocalizedString("Main_Database_Required_Mutaplasmids", comment: "")
                ).font(.headline)
            ) {
                ForEach(requiredMutaplasmids, id: \.typeID) { mutaplasmid in
                    NavigationLink {
                        ShowMutationInfo(
                            itemID: mutaplasmid.typeID, databaseManager: databaseManager)
                    } label: {
                        HStack {
                            IconManager.shared.loadImage(for: mutaplasmid.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)

                            Text(mutaplasmid.name)
                                .font(.body)
                        }
                    }
                }
            }
        }
    }
}
