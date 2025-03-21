import SwiftUI

// 蓝图活动数据模型
struct BlueprintActivity {
    let materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)]
    let skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)]
    let products:
        [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)]
    let time: Int
}

// 产出物项视图
struct ProductItemView: View {
    let item: (typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)
    let databaseManager: DatabaseManager

    var body: some View {
        NavigationLink(
            destination: {
                if let categoryID = databaseManager.getCategoryID(for: item.typeID) {
                    ItemInfoMap.getItemInfoView(
                        itemID: item.typeID,
                        categoryID: categoryID,
                        databaseManager: databaseManager
                    )
                }
            }
        ) {
            HStack {
                IconManager.shared.loadImage(
                    for: item.typeIcon.isEmpty ? "not_found" : item.typeIcon
                )
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

                Text(NSLocalizedString("Blueprint_Product", comment: ""))

                Spacer()

                Text("\(item.quantity) × \(item.typeName)")
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// 发明产出项视图
struct InventionProductItemView: View {
    let product:
        (typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)
    let databaseManager: DatabaseManager

    var body: some View {
        NavigationLink(
            destination: {
                if let categoryID = databaseManager.getCategoryID(for: product.typeID) {
                    ItemInfoMap.getItemInfoView(
                        itemID: product.typeID,
                        categoryID: categoryID,
                        databaseManager: databaseManager
                    )
                }
            }
        ) {
            HStack {
                IconManager.shared.loadImage(
                    for: product.typeIcon.isEmpty ? "not_found" : product.typeIcon
                )
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

                VStack(alignment: .leading) {
                    Text(product.typeName)
                        .foregroundColor(.primary)
                    if let probability = product.probability {
                        Text(
                            String(
                                format: NSLocalizedString("Blueprint_Success_Rate", comment: ""),
                                Int(probability * 100)
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// 主视图
struct ShowBluePrintInfo: View {
    let blueprintID: Int
    let databaseManager: DatabaseManager
    @State private var manufacturing: BlueprintActivity?
    @State private var researchMaterial: BlueprintActivity?
    @State private var researchTime: BlueprintActivity?
    @State private var copying: BlueprintActivity?
    @State private var invention: BlueprintActivity?
    @State private var itemDetails: ItemDetails?
    @State private var blueprintSource: [(typeID: Int, typeName: String, typeIcon: String)] = []
    @State private var isManufacturingMaterialsExpanded = false
    @State private var isManufacturingSkillsExpanded = false
    @State private var isResearchMaterialMaterialsExpanded = false
    @State private var isResearchMaterialSkillsExpanded = false
    @State private var isResearchMaterialLevelsExpanded = false
    @State private var isResearchTimeMaterialsExpanded = false
    @State private var isResearchTimeSkillsExpanded = false
    @State private var isResearchTimeLevelsExpanded = false
    @State private var isCopyingMaterialsExpanded = false
    @State private var isCopyingSkillsExpanded = false
    @State private var isInventionMaterialsExpanded = false
    @State private var isInventionSkillsExpanded = false

    // 加载蓝图来源
    private func loadBlueprintSource() {
        blueprintSource = databaseManager.getBlueprintSource(for: blueprintID)
    }

    // 加载蓝图数据
    private func loadBlueprintData() {
        // 首先获取所有处理时间
        guard let processTime = databaseManager.getBlueprintProcessTime(for: blueprintID) else {
            return
        }

        // 制造活动
        if processTime.manufacturing_time > 0 {
            let manufacturingMaterials = databaseManager.getBlueprintManufacturingMaterials(
                for: blueprintID)
            let manufacturingProducts = databaseManager.getBlueprintManufacturingOutput(
                for: blueprintID)
            let manufacturingSkills = databaseManager.getBlueprintManufacturingSkills(
                for: blueprintID)

            manufacturing = BlueprintActivity(
                materials: manufacturingMaterials,
                skills: manufacturingSkills,
                products: manufacturingProducts.map {
                    ($0.typeID, $0.typeName, $0.typeIcon, $0.quantity, nil)
                },
                time: processTime.manufacturing_time
            )
        }

        // 材料研究活动
        if processTime.research_material_time > 0 {
            let researchMaterialMaterials = databaseManager.getBlueprintResearchMaterialMaterials(
                for: blueprintID)
            let researchMaterialSkills = databaseManager.getBlueprintResearchMaterialSkills(
                for: blueprintID)

            researchMaterial = BlueprintActivity(
                materials: researchMaterialMaterials,
                skills: researchMaterialSkills,
                products: [],
                time: processTime.research_material_time
            )
        }

        // 时间研究活动
        if processTime.research_time_time > 0 {
            let researchTimeMaterials = databaseManager.getBlueprintResearchTimeMaterials(
                for: blueprintID)
            let researchTimeSkills = databaseManager.getBlueprintResearchTimeSkills(
                for: blueprintID)

            researchTime = BlueprintActivity(
                materials: researchTimeMaterials,
                skills: researchTimeSkills,
                products: [],
                time: processTime.research_time_time
            )
        }

        // 复制活动
        if processTime.copying_time > 0 {
            let copyingMaterials = databaseManager.getBlueprintCopyingMaterials(for: blueprintID)
            let copyingSkills = databaseManager.getBlueprintCopyingSkills(for: blueprintID)

            copying = BlueprintActivity(
                materials: copyingMaterials,
                skills: copyingSkills,
                products: [],
                time: processTime.copying_time
            )
        }

        // 发明活动
        if processTime.invention_time > 0 {
            let inventionMaterials = databaseManager.getBlueprintInventionMaterials(
                for: blueprintID)
            let inventionSkills = databaseManager.getBlueprintInventionSkills(for: blueprintID)
            let inventionProducts = databaseManager.getBlueprintInventionProducts(for: blueprintID)

            invention = BlueprintActivity(
                materials: inventionMaterials,
                skills: inventionSkills,
                products: inventionProducts.map {
                    ($0.typeID, $0.typeName, $0.typeIcon, $0.quantity, $0.probability)
                },
                time: processTime.invention_time
            )
        }
    }

    // 计算研究等级
    private func calculateRank(from baseTime: Int) -> Int {
        return baseTime / 105  // 使用 level 1 的基础时间 105 来计算 rank
    }

    // 计算特定等级的时间
    private func calculateLevelTime(baseTime: Int, level: Int) -> Int {
        let levelMultipliers = [105, 250, 595, 1414, 3360, 8000, 19000, 45255, 107_700, 256_000]
        let rank = baseTime / 105
        return levelMultipliers[level - 1] * rank

        // 此处采用blueprints.yaml中提供的基准时间，除以rank1的基准时间获取rank值，再乘各个rank的标准时间来计算。
        // rank值也可以通过查询typeAttributes表中对应物品的attribute_id = 1955的值来获取
    }

    var body: some View {
        List {
            // 基础信息部分
            if let itemDetails = itemDetails {
                ItemBasicInfoView(itemDetails: itemDetails, databaseManager: databaseManager)
            }

            // 制造活动
            if let manufacturing = manufacturing {
                Section(
                    header: Text(NSLocalizedString("Blueprint_Manufacturing", comment: "")).font(
                        .headline)
                ) {
                    // 产出物
                    if !manufacturing.products.isEmpty {
                        ForEach(manufacturing.products, id: \.typeID) { product in
                            ProductItemView(item: product, databaseManager: databaseManager)
                        }
                    }

                    // 材料折叠组
                    if !manufacturing.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isManufacturingMaterialsExpanded,
                            content: {
                                ForEach(manufacturing.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        ShowItemInfo(
                                            databaseManager: databaseManager,
                                            itemID: material.typeID
                                        )
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text("\(material.quantity)")
                                                .foregroundColor(.secondary)
                                                .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        ))
                                    Spacer()
                                    Text(
                                        "\(manufacturing.materials.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !manufacturing.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isManufacturingSkillsExpanded,
                            content: {
                                ForEach(manufacturing.skills, id: \.typeID) { skill in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(
                                            for: skill.typeID)
                                        {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: skill.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: skill.typeIcon.isEmpty
                                                    ? "not_found" : skill.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(skill.typeName)

                                            Spacer()

                                            Text(
                                                String(
                                                    format: NSLocalizedString(
                                                        "Blueprint_Level", comment: ""
                                                    ), skill.level
                                                )
                                            )
                                            .foregroundColor(.secondary)
                                            .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(manufacturing.skills.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 制造时间
                    HStack {
                        Text(NSLocalizedString("Blueprint_Manufacturing_Time", comment: ""))
                        Spacer()
                        Text(formatTime(manufacturing.time))
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }
            }

            // 材料研究活动
            if let researchMaterial = researchMaterial {
                Section(
                    header: Text(NSLocalizedString("Blueprint_Research_Material", comment: ""))
                        .font(.headline)
                ) {
                    // 材料折叠组
                    if !researchMaterial.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isResearchMaterialMaterialsExpanded,
                            content: {
                                ForEach(researchMaterial.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(
                                            for: material.typeID)
                                        {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: material.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text("\(material.quantity)")
                                                .foregroundColor(.secondary)
                                                .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        ))
                                    Spacer()
                                    Text(
                                        "\(researchMaterial.materials.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !researchMaterial.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isResearchMaterialSkillsExpanded,
                            content: {
                                ForEach(researchMaterial.skills, id: \.typeID) { skill in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(
                                            for: skill.typeID)
                                        {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: skill.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: skill.typeIcon.isEmpty
                                                    ? "not_found" : skill.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(skill.typeName)

                                            Spacer()

                                            Text(
                                                String(
                                                    format: NSLocalizedString(
                                                        "Blueprint_Level", comment: ""
                                                    ), skill.level
                                                )
                                            )
                                            .foregroundColor(.secondary)
                                            .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(researchMaterial.skills.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 时间等级折叠组
                    DisclosureGroup(
                        isExpanded: $isResearchMaterialLevelsExpanded,
                        content: {
                            ForEach(1...10, id: \.self) { level in
                                HStack {
                                    Text(String("Level \(level)"))
                                    Spacer()
                                    Text(
                                        formatTime(
                                            calculateLevelTime(
                                                baseTime: researchMaterial.time, level: level
                                            ))
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        },
                        label: {
                            HStack {
                                Text(
                                    NSLocalizedString("Blueprint_Research_Time_Label", comment: ""))
                                Spacer()
                            }
                        }
                    )
                }
            }

            // 时间研究活动
            if let researchTime = researchTime {
                Section(
                    header: Text(NSLocalizedString("Blueprint_Research_Time", comment: "")).font(
                        .headline)
                ) {
                    // 材料折叠组
                    if !researchTime.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isResearchTimeMaterialsExpanded,
                            content: {
                                ForEach(researchTime.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(
                                            for: material.typeID)
                                        {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: material.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text("\(material.quantity)")
                                                .foregroundColor(.secondary)
                                                .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        ))
                                    Spacer()
                                    Text(
                                        "\(researchTime.materials.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !researchTime.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isResearchTimeSkillsExpanded,
                            content: {
                                ForEach(researchTime.skills, id: \.typeID) { skill in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(
                                            for: skill.typeID)
                                        {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: skill.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: skill.typeIcon.isEmpty
                                                    ? "not_found" : skill.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(skill.typeName)

                                            Spacer()

                                            Text(
                                                String(
                                                    format: NSLocalizedString(
                                                        "Blueprint_Level", comment: ""
                                                    ), skill.level
                                                )
                                            )
                                            .foregroundColor(.secondary)
                                            .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(researchTime.skills.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 时间等级折叠组
                    DisclosureGroup(
                        isExpanded: $isResearchTimeLevelsExpanded,
                        content: {
                            ForEach(1...10, id: \.self) { level in
                                HStack {
                                    Text(String("Level \(2 * level)"))
                                    Spacer()
                                    Text(
                                        formatTime(
                                            calculateLevelTime(
                                                baseTime: researchTime.time, level: level
                                            ))
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        },
                        label: {
                            HStack {
                                Text(
                                    NSLocalizedString("Blueprint_Research_Time_Label", comment: ""))
                                Spacer()
                            }
                        }
                    )
                }
            }

            // 复制活动
            if let copying = copying {
                Section(
                    header: Text(NSLocalizedString("Blueprint_Copying", comment: "")).font(
                        .headline)
                ) {
                    // 材料折叠组
                    if !copying.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isCopyingMaterialsExpanded,
                            content: {
                                ForEach(copying.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(
                                            for: material.typeID)
                                        {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: material.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text("\(material.quantity)")
                                                .foregroundColor(.secondary)
                                                .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        ))
                                    Spacer()
                                    Text(
                                        "\(copying.materials.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !copying.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isCopyingSkillsExpanded,
                            content: {
                                ForEach(copying.skills, id: \.typeID) { skill in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(
                                            for: skill.typeID)
                                        {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: skill.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: skill.typeIcon.isEmpty
                                                    ? "not_found" : skill.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(skill.typeName)

                                            Spacer()

                                            Text(
                                                String(
                                                    format: NSLocalizedString(
                                                        "Blueprint_Level", comment: ""
                                                    ), skill.level
                                                )
                                            )
                                            .foregroundColor(.secondary)
                                            .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(copying.skills.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 复制时间
                    HStack {
                        Text(NSLocalizedString("Blueprint_Copying_Time", comment: ""))
                        Spacer()
                        Text(formatTime(copying.time))
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }
            }

            // 发明活动
            if let invention = invention {
                Section(
                    header: Text(NSLocalizedString("Blueprint_Invention", comment: "")).font(
                        .headline)
                ) {
                    // 产出物
                    if !invention.products.isEmpty {
                        ForEach(invention.products, id: \.typeID) { product in
                            InventionProductItemView(
                                product: product, databaseManager: databaseManager
                            )
                        }
                    }

                    // 材料折叠组
                    if !invention.materials.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isInventionMaterialsExpanded,
                            content: {
                                ForEach(invention.materials, id: \.typeID) { material in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(
                                            for: material.typeID)
                                        {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: material.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: material.typeIcon.isEmpty
                                                    ? "not_found" : material.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(material.typeName)

                                            Spacer()

                                            Text("\(material.quantity)")
                                                .foregroundColor(.secondary)
                                                .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        ))
                                    Spacer()
                                    Text(
                                        "\(invention.materials.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 技能折叠组
                    if !invention.skills.isEmpty {
                        DisclosureGroup(
                            isExpanded: $isInventionSkillsExpanded,
                            content: {
                                ForEach(invention.skills, id: \.typeID) { skill in
                                    NavigationLink {
                                        if let categoryID = databaseManager.getCategoryID(
                                            for: skill.typeID)
                                        {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: skill.typeID,
                                                categoryID: categoryID,
                                                databaseManager: databaseManager
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            IconManager.shared.loadImage(
                                                for: skill.typeIcon.isEmpty
                                                    ? "not_found" : skill.typeIcon
                                            )
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)

                                            Text(skill.typeName)

                                            Spacer()

                                            Text(
                                                String(
                                                    format: NSLocalizedString(
                                                        "Blueprint_Level", comment: ""
                                                    ), skill.level
                                                )
                                            )
                                            .foregroundColor(.secondary)
                                            .frame(alignment: .trailing)
                                        }
                                    }
                                }
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(invention.skills.count)\(NSLocalizedString("Misc_number_types", comment: ""))"
                                    )
                                    .foregroundColor(.secondary)
                                    .frame(alignment: .trailing)
                                }
                            }
                        )
                    }

                    // 发明时间
                    HStack {
                        Text(NSLocalizedString("Blueprint_Invention_Time", comment: ""))
                        Spacer()
                        Text(formatTime(invention.time))
                            .foregroundColor(.secondary)
                            .frame(alignment: .trailing)
                    }
                }
            }

            // 来源部分
            if !blueprintSource.isEmpty {  // 检查是否有来源
                Section(
                    header: Text(NSLocalizedString("Blueprint_Source", comment: "")).font(.headline)
                ) {
                    ForEach(blueprintSource, id: \.typeID) { source in
                        NavigationLink(
                            destination: ItemInfoMap.getItemInfoView(
                                itemID: source.typeID,
                                categoryID: databaseManager.getCategoryID(for: source.typeID) ?? 0,
                                databaseManager: databaseManager
                            )
                        ) {
                            HStack {
                                IconManager.shared.loadImage(
                                    for: source.typeIcon.isEmpty
                                        ? DatabaseConfig.defaultItemIcon : source.typeIcon
                                )
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)

                                Text(source.typeName)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Blueprint_Info", comment: ""))
        .onAppear {
            itemDetails = databaseManager.getItemDetails(for: blueprintID)
            loadBlueprintData()
            loadBlueprintSource()
        }
    }
}
