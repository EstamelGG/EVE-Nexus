import SwiftUI

// ShowItemInfo view
struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    @Environment(\.dismiss) private var dismiss
    private let currentCharacterId: Int = {
        guard let id = UserDefaults.standard.object(forKey: "currentCharacterId") as? Int else {
            return 0
        }
        return id
    }()

    var itemID: Int

    @State private var itemDetails: ItemDetails?
    @State private var attributeGroups: [AttributeGroup] = []
    @State private var roleBonuses: [Trait] = []
    @State private var typeBonuses: [Trait] = []

    private func buildTraitsText(
        roleBonuses: [Trait], typeBonuses: [Trait], databaseManager: DatabaseManager
    ) -> String {
        var text = ""

        // Role Bonuses
        if !roleBonuses.isEmpty {
            text += "<b>\(NSLocalizedString("Main_Database_Role_Bonuses", comment: ""))</b>\n"
            text +=
                roleBonuses
                .map { "• \($0.content)" }
                .joined(separator: "\n")
        }

        if !roleBonuses.isEmpty && !typeBonuses.isEmpty {
            text += "\n\n"
        }

        // Type Bonuses
        if !typeBonuses.isEmpty {
            let groupedBonuses = Dictionary(grouping: typeBonuses) { $0.skill }
            let sortedSkills = groupedBonuses.keys
                .compactMap { $0 }
                .sorted()

            for skill in sortedSkills {
                if let skillName = databaseManager.getTypeName(for: skill) {
                    text +=
                        "<b>\(skillName)</b> \(NSLocalizedString("Main_Database_Bonuses_Per_Level", comment: ""))\n"

                    let bonuses =
                        groupedBonuses[skill]?.sorted(by: { $0.importance < $1.importance }) ?? []
                    text +=
                        bonuses
                        .map { "• \($0.content)" }
                        .joined(separator: "\n")

                    if skill != sortedSkills.last {
                        text += "\n\n"
                    }
                }
            }
        }

        return text.isEmpty ? "" : text
    }

    var body: some View {
        List {
            if let itemDetails = itemDetails {
                ItemBasicInfoView(
                    itemDetails: itemDetails,
                    databaseManager: databaseManager
                )

                // 变体 Section（如果有的话）
                let variationsCount = databaseManager.getVariationsCount(for: itemID)
                if variationsCount > 1 {
                    Section {
                        NavigationLink(
                            destination: VariationsView(
                                databaseManager: databaseManager, typeID: itemID
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

                // 属性 Sections
                AttributesView(
                    attributeGroups: attributeGroups,
                    typeID: itemID,
                    databaseManager: databaseManager
                )

                // 如果是技能，显示依赖该技能的物品列表
                if let categoryID = itemDetails.categoryID,
                    categoryID == 16
                {
                    // 技能点数和训练时间列表
                    SkillPointForLevelView(
                        skillId: itemID,
                        characterId: currentCharacterId == 0 ? nil : currentCharacterId,
                        databaseManager: databaseManager
                    )

                    // 依赖该技能的物品列表
                    SkillDependencySection(
                        skillID: itemID,
                        databaseManager: databaseManager
                    )
                }

                // Industry Section
                let materials = databaseManager.getTypeMaterials(for: itemID)
                let blueprintID = databaseManager.getBlueprintIDForProduct(itemID)
                let groups_should_show_source = [18, 1996, 423, 427]
                // 只针对矿物、突变残渣、化学元素、同位素等产物展示精炼来源
                let sourceMaterials:
                    [(
                        typeID: Int, name: String, iconFileName: String,
                        outputQuantityPerUnit: Double
                    )]? =
                        if let groupID = itemDetails.groupID {
                            (groups_should_show_source.contains(groupID))
                                ? databaseManager.getSourceMaterials(for: itemID, groupID: groupID)
                                : nil
                        } else {
                            nil
                        }
                if materials != nil || blueprintID != nil || sourceMaterials != nil {
                    Section(header: Text("Industry").font(.headline)) {
                        // 蓝图按钮
                        if let blueprintID = blueprintID,
                            let blueprintDetails = databaseManager.getItemDetails(for: blueprintID)
                        {
                            NavigationLink {
                                ShowBluePrintInfo(
                                    blueprintID: blueprintID, databaseManager: databaseManager
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
            } else {
                Text("Details not found")
                    .foregroundColor(.gray)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Item_Info", comment: ""))
        .navigationBarBackButtonHidden(false)
        .onAppear {
            getItemDetails(for: itemID)
            loadAttributes(for: itemID)
        }
    }

    // 加载 item 详细信息
    private func getItemDetails(for itemID: Int) {
        if let itemDetail = databaseManager.getItemDetails(for: itemID) {
            // 加载 traits
            if let traitGroup = databaseManager.getTraits(for: itemID) {
                // 构建trait文本
                let traitText = buildTraitsText(
                    roleBonuses: traitGroup.roleBonuses,
                    typeBonuses: traitGroup.typeBonuses,
                    databaseManager: databaseManager
                )

                // 创建新的描述文本，将trait信息拼接到原始描述后面
                let fullDescription =
                    itemDetail.description + (traitText.isEmpty ? "" : "\n\n" + traitText)

                let details = ItemDetails(
                    name: itemDetail.name,
                    description: fullDescription,
                    iconFileName: itemDetail.iconFileName,
                    groupName: itemDetail.groupName,
                    categoryID: itemDetail.categoryID,
                    categoryName: itemDetail.categoryName,
                    typeId: itemDetail.typeId,
                    groupID: itemDetail.groupID,
                    volume: itemDetail.volume,
                    capacity: itemDetail.capacity,
                    mass: itemDetail.mass,
                    marketGroupID: itemDetail.marketGroupID
                )
                itemDetails = details
            } else {
                itemDetails = itemDetail
            }
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
        let path = UIBezierPath(
            roundedRect: rect, byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
