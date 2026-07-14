import SwiftUI

/// 显示依赖该技能的物品列表
struct SkillDependencyListView: View {
    let skillID: Int
    let level: Int
    let items: [(
        typeID: Int, name: String, iconFileName: String, categoryID: Int, categoryName: String
    )]
    @ObservedObject var databaseManager: DatabaseManager

    private var itemsByCategory: [(
        categoryName: String,
        items: [(
            typeID: Int, name: String, iconFileName: String, categoryID: Int, categoryName: String
        )]
    )] {
        Dictionary(grouping: items, by: \.categoryName)
            .map { (categoryName: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.categoryName < $1.categoryName }
    }

    var body: some View {
        List {
            ForEach(itemsByCategory, id: \.categoryName) { category in
                Section(header: Text(category.categoryName).font(.headline)) {
                    ForEach(category.items, id: \.typeID) { item in
                        NavigationLink {
                            ItemInfoMap.getItemInfoView(
                                itemID: item.typeID,
                                databaseManager: databaseManager
                            )
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
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .listStyle(.insetGrouped)
        .navigationTitle(
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("Misc_Level", comment: "lv%d"),
                    level
                )
            )
        )
    }
}

/// 显示技能依赖关系的入口视图
struct SkillDependencySection: View {
    let skillID: Int
    @ObservedObject var databaseManager: DatabaseManager

    var body: some View {
        let itemsByLevel = databaseManager.getAllItemsRequiringSkill(skillID: skillID)
        if !itemsByLevel.isEmpty {
            Section(
                header: Text(NSLocalizedString("Main_Database_Required_By", comment: ""))
                    .font(.headline)
            ) {
                ForEach(1 ... 5, id: \.self) { level in
                    if let items = itemsByLevel[level], !items.isEmpty {
                        NavigationLink {
                            SkillDependencyListView(
                                skillID: skillID,
                                level: level,
                                items: items,
                                databaseManager: databaseManager
                            )
                        } label: {
                            HStack {
                                Image("skill_lv_\(level)")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(
                                    String(
                                        format: NSLocalizedString("Misc_Level", comment: "lv%d"),
                                        level
                                    )
                                )
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
    }
}
