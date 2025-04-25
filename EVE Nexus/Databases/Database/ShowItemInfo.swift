import SwiftUI

// ShowItemInfo view
struct ShowItemInfo: View {
    @ObservedObject var databaseManager: DatabaseManager
    private let currentCharacterId: Int = {
        guard let id = UserDefaults.standard.object(forKey: "currentCharacterId") as? Int else {
            return 0
        }
        return id
    }()

    var itemID: Int

    @State private var itemDetails: ItemDetails?
    @State private var attributeGroups: [AttributeGroup] = []

    private func buildTraitsText(
        roleBonuses: [Trait], typeBonuses: [Trait], databaseManager: DatabaseManager
    ) -> String {
        var text = ""

        // Role Bonuses
        if !roleBonuses.isEmpty {
            text += "- <b>\(NSLocalizedString("Main_Database_Role_Bonuses", comment: ""))</b>\n"
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
                        "- <a href=showinfo:\(skill)>\(skillName)</a> \(NSLocalizedString("Main_Database_Bonuses_Per_Level", comment: ""))\n"

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
                IndustrySection(
                    itemID: itemID, databaseManager: databaseManager, itemDetails: itemDetails)

                // 突变来源 Section
                let mutationSource = databaseManager.getMutationSource(for: itemID)
                if !mutationSource.sourceItems.isEmpty {
                    // 源装备 Section
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

                    // 突变质体 Section
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

                // 突变结果 Section
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

                // 所需突变体 Section
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
            } else {
                Text(NSLocalizedString("Item_details_notfound", comment: ""))
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
                    repackagedVolume: itemDetail.repackagedVolume,
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
