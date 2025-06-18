import SwiftUI
import UIKit

// 蓝图活动数据模型
struct BlueprintActivity {
    let materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)]
    let skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?)]
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
                ItemInfoMap.getItemInfoView(
                    itemID: item.typeID,
                    databaseManager: databaseManager
                )
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
                ItemInfoMap.getItemInfoView(
                    itemID: product.typeID,
                    databaseManager: databaseManager
                )
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

// 蓝图技能需求行
struct BlueprintSkillRow: View {
    let skill: (typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?)
    let databaseManager: DatabaseManager
    let currentSkillLevel: Int?
    
    // 获取当前技能点数（直接查表，不累加）
    private func getCurrentSkillPointsSimple() -> Int {
        guard let currentLevel = currentSkillLevel, let multiplier = skill.timeMultiplier else { return 0 }
        if currentLevel <= 0 { return 0 }
        if currentLevel > SkillTreeManager.levelBasePoints.count { return 0 }
        return Int(Double(SkillTreeManager.levelBasePoints[currentLevel - 1]) * multiplier)
    }
    
    // 获取所需总点数（直接查表）
    private func getRequiredSkillPointsSimple() -> Int {
        guard let multiplier = skill.timeMultiplier else { return 0 }
        if skill.level <= 0 || skill.level > SkillTreeManager.levelBasePoints.count { return 0 }
        return Int(Double(SkillTreeManager.levelBasePoints[skill.level - 1]) * multiplier)
    }
    
    // 获取技能点数文本
    private var skillPointsText: String {
        guard let multiplier = skill.timeMultiplier,
            skill.level > 0 && skill.level <= SkillTreeManager.levelBasePoints.count
        else {
            return ""
        }
        let points = Int(Double(SkillTreeManager.levelBasePoints[skill.level - 1]) * multiplier)
        return "\(FormatUtil.format(Double(points))) SP"
    }
    
    var body: some View {
        NavigationLink {
            ItemInfoMap.getItemInfoView(
                itemID: skill.typeID,
                databaseManager: databaseManager
            )
        } label: {
            HStack {
                // 技能图标
                if let currentLevel = currentSkillLevel, currentLevel == -1 {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 32, height: 32)
                        .foregroundColor(.red)
                } else if let currentLevel = currentSkillLevel, currentLevel >= skill.level {
                    Image(systemName: "checkmark.circle.fill")
                        .frame(width: 32, height: 32)
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "circle")
                        .frame(width: 32, height: 32)
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading) {
                    // 技能名称
                    Text(skill.typeName)
                        .font(.body)
                    
                    // 技能点数显示
                    if let currentLevel = currentSkillLevel, currentLevel >= -1, currentLevel < skill.level {
                        // 当有技能但等级不足时，显示当前/需要的技能点数
                        let currentSP = getCurrentSkillPointsSimple()
                        let requiredSP = getRequiredSkillPointsSimple()
                        Text(
                            "\(FormatUtil.format(Double(currentSP)))/\(FormatUtil.format(Double(requiredSP))) SP"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    } else {
                        // 其他情况显示需要的总技能点数
                        if !skillPointsText.isEmpty {
                            Text(skillPointsText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // 等级要求
                Text(
                    String(
                        format: NSLocalizedString(
                            "Misc_Level", comment: ""
                        ), skill.level
                    )
                )
                .foregroundColor(.secondary)
                .frame(alignment: .trailing)
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
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @State private var characterSkills: [Int: Int] = [:]
    @State private var showingCopyAlert = false
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
            
            // 获取制造技能要求
            let manufacturingSkills = databaseManager.getBlueprintManufacturingSkills(for: blueprintID)
            let skillIDs = manufacturingSkills.map { $0.typeID }
            // 获取所有技能的训练时间倍增系数
            let multipliers = SkillTreeManager.shared.getTrainingTimeMultipliers(for: skillIDs, databaseManager: databaseManager)
            
            // 将时间倍率添加到技能列表中
            let skillsWithMultipliers = manufacturingSkills.map { skill -> (typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?) in
                return (typeID: skill.typeID, typeName: skill.typeName, typeIcon: skill.typeIcon, level: skill.level, timeMultiplier: multipliers[skill.typeID])
            }

            manufacturing = BlueprintActivity(
                materials: manufacturingMaterials,
                skills: skillsWithMultipliers,
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
            
            // 获取所有技能的训练时间倍增系数
            let skillIDs = researchMaterialSkills.map { $0.typeID }
            let multipliers = SkillTreeManager.shared.getTrainingTimeMultipliers(for: skillIDs, databaseManager: databaseManager)
            
            // 将时间倍率添加到技能列表中
            let skillsWithMultipliers = researchMaterialSkills.map { skill -> (typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?) in
                return (typeID: skill.typeID, typeName: skill.typeName, typeIcon: skill.typeIcon, level: skill.level, timeMultiplier: multipliers[skill.typeID])
            }

            researchMaterial = BlueprintActivity(
                materials: researchMaterialMaterials,
                skills: skillsWithMultipliers,
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
            
            // 获取所有技能的训练时间倍增系数
            let skillIDs = researchTimeSkills.map { $0.typeID }
            let multipliers = SkillTreeManager.shared.getTrainingTimeMultipliers(for: skillIDs, databaseManager: databaseManager)
            
            // 将时间倍率添加到技能列表中
            let skillsWithMultipliers = researchTimeSkills.map { skill -> (typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?) in
                return (typeID: skill.typeID, typeName: skill.typeName, typeIcon: skill.typeIcon, level: skill.level, timeMultiplier: multipliers[skill.typeID])
            }

            researchTime = BlueprintActivity(
                materials: researchTimeMaterials,
                skills: skillsWithMultipliers,
                products: [],
                time: processTime.research_time_time
            )
        }

        // 复制活动
        if processTime.copying_time > 0 {
            let copyingMaterials = databaseManager.getBlueprintCopyingMaterials(for: blueprintID)
            let copyingSkills = databaseManager.getBlueprintCopyingSkills(for: blueprintID)
            
            // 获取所有技能的训练时间倍增系数
            let skillIDs = copyingSkills.map { $0.typeID }
            let multipliers = SkillTreeManager.shared.getTrainingTimeMultipliers(for: skillIDs, databaseManager: databaseManager)
            
            // 将时间倍率添加到技能列表中
            let skillsWithMultipliers = copyingSkills.map { skill -> (typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?) in
                return (typeID: skill.typeID, typeName: skill.typeName, typeIcon: skill.typeIcon, level: skill.level, timeMultiplier: multipliers[skill.typeID])
            }

            copying = BlueprintActivity(
                materials: copyingMaterials,
                skills: skillsWithMultipliers,
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
            
            // 获取所有技能的训练时间倍增系数
            let skillIDs = inventionSkills.map { $0.typeID }
            let multipliers = SkillTreeManager.shared.getTrainingTimeMultipliers(for: skillIDs, databaseManager: databaseManager)
            
            // 将时间倍率添加到技能列表中
            let skillsWithMultipliers = inventionSkills.map { skill -> (typeID: Int, typeName: String, typeIcon: String, level: Int, timeMultiplier: Double?) in
                return (typeID: skill.typeID, typeName: skill.typeName, typeIcon: skill.typeIcon, level: skill.level, timeMultiplier: multipliers[skill.typeID])
            }

            invention = BlueprintActivity(
                materials: inventionMaterials,
                skills: skillsWithMultipliers,
                products: inventionProducts.map {
                    ($0.typeID, $0.typeName, $0.typeIcon, $0.quantity, $0.probability)
                },
                time: processTime.invention_time
            )
        }
    }

    // 计算特定等级的时间
    private func calculateLevelTime(baseTime: Int, level: Int) -> Int {
        let levelMultipliers = [105, 250, 595, 1414, 3360, 8000, 19000, 45255, 107_700, 256_000]
        let rank = baseTime / 105
        return levelMultipliers[level - 1] * rank

        // 此处采用blueprints.yaml中提供的基准时间，除以rank1的基准时间获取rank值，再乘各个rank的标准时间来计算。
        // rank值也可以通过查询typeAttributes表中对应物品的attribute_id = 1955的值来获取
    }

    // 加载所有技能等级
    private func loadAllSkills() {
        if currentCharacterId == 0 {
            characterSkills = [:]
            return
        }
        
        let skillsQuery = "SELECT skills_data FROM character_skills WHERE character_id = ?"
        
        guard
            case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
                skillsQuery, parameters: [currentCharacterId]),
            let row = rows.first,
            let skillsJson = row["skills_data"] as? String,
            let data = skillsJson.data(using: .utf8)
        else {
            characterSkills = [:]
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let skillsResponse = try decoder.decode(CharacterSkillsResponse.self, from: data)
            
            // 将所有技能映射到字典中
            var skillsDict = [Int: Int]()
            for skill in skillsResponse.skills {
                skillsDict[skill.skill_id] = skill.trained_skill_level
            }
            characterSkills = skillsDict
        } catch {
            Logger.error("解析技能数据失败: \(error)")
            characterSkills = [:]
        }
    }
    
    // 获取当前技能等级
    private func getCurrentSkillLevel(for skillID: Int) -> Int {
        return characterSkills[skillID] ?? -1
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
                    header: HStack {
                        Text(NSLocalizedString("Blueprint_Manufacturing", comment: "")).font(
                            .headline)
                        Spacer()
                        Button(action: {
                            // 复制材料列表到剪贴板
                            let materialsText = manufacturing.materials.map { material in
                                "\(material.typeName)      \(material.quantity)"
                            }.joined(separator: "\n")
                            UIPasteboard.general.string = materialsText
                            
                            // 显示复制成功弹窗
                            showingCopyAlert = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 14))
                                Text(NSLocalizedString("Blueprint_Copy_Materials", comment: ""))
                                    .font(.system(size: 14))
                            }
                        }
                        .buttonStyle(.borderless)
                    }
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

                                            Text(
                                                "\(material.quantity) \(NSLocalizedString("Misc_unit", comment: ""))"
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
                                    BlueprintSkillRow(
                                        skill: skill, 
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(manufacturing.skills.count) \(NSLocalizedString("Misc_number_types", comment: ""))"
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
                                        ItemInfoMap.getItemInfoView(
                                            itemID: material.typeID,
                                            databaseManager: databaseManager
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
                                        "\(researchMaterial.materials.count) \(NSLocalizedString("Misc_number_types", comment: ""))"
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
                                    BlueprintSkillRow(
                                        skill: skill, 
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(researchMaterial.skills.count) \(NSLocalizedString("Misc_number_types", comment: ""))"
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
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Misc_Level", comment: "lv%d"), level))
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
                                        ItemInfoMap.getItemInfoView(
                                            itemID: material.typeID,
                                            databaseManager: databaseManager
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

                                            Text(
                                                "\(material.quantity) \(NSLocalizedString("Misc_unit", comment: ""))"
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
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        ))
                                    Spacer()
                                    Text(
                                        "\(researchTime.materials.count) \(NSLocalizedString("Misc_number_types", comment: ""))"
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
                                    BlueprintSkillRow(
                                        skill: skill, 
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(researchTime.skills.count) \(NSLocalizedString("Misc_number_types", comment: ""))"
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
                                    Text(
                                        String(
                                            format: NSLocalizedString(
                                                "Misc_Level", comment: "lv%d"), 2 * level))
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
                                        ItemInfoMap.getItemInfoView(
                                            itemID: material.typeID,
                                            databaseManager: databaseManager
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

                                            Text(
                                                "\(material.quantity) \(NSLocalizedString("Misc_unit", comment: ""))"
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
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        ))
                                    Spacer()
                                    Text(
                                        "\(copying.materials.count) \(NSLocalizedString("Misc_number_types", comment: ""))"
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
                                    BlueprintSkillRow(
                                        skill: skill, 
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(copying.skills.count) \(NSLocalizedString("Misc_number_types", comment: ""))"
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
                                        ItemInfoMap.getItemInfoView(
                                            itemID: material.typeID,
                                            databaseManager: databaseManager
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

                                            Text(
                                                "\(material.quantity) \(NSLocalizedString("Misc_unit", comment: ""))"
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
                                        NSLocalizedString(
                                            "Blueprint_Required_Materials", comment: ""
                                        ))
                                    Spacer()
                                    Text(
                                        "\(invention.materials.count) \(NSLocalizedString("Misc_number_types", comment: ""))"
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
                                    BlueprintSkillRow(
                                        skill: skill, 
                                        databaseManager: databaseManager,
                                        currentSkillLevel: getCurrentSkillLevel(for: skill.typeID)
                                    )
                                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            },
                            label: {
                                HStack {
                                    Text(
                                        NSLocalizedString("Blueprint_Required_Skills", comment: ""))
                                    Spacer()
                                    Text(
                                        "\(invention.skills.count) \(NSLocalizedString("Misc_number_types", comment: ""))"
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
        .alert(NSLocalizedString("Blueprint_Copy_Success", comment: "材料已复制"), isPresented: $showingCopyAlert) {
            Button("OK", role: .cancel) { }
        }
        .onAppear {
            itemDetails = databaseManager.getItemDetails(for: blueprintID)
            loadBlueprintData()
            loadBlueprintSource()
            loadAllSkills()
        }
    }
}
