import SwiftUI

// 显示依赖该技能的物品列表
struct SkillDependencyListView: View {
    let skillID: Int
    let level: Int
    let items: [(typeID: Int, name: String, iconFileName: String, categoryID: Int, categoryName: String)]
    @ObservedObject var databaseManager: DatabaseManager
    
    // 按分类分组的物品
    private var itemsByCategory: [(categoryName: String, items: [(typeID: Int, name: String, iconFileName: String, categoryID: Int, categoryName: String)])] {
        // 按分类名称分组
        let groupedItems = Dictionary(grouping: items) { item in
            item.categoryName
        }
        
        // 按分类名称排序
        return groupedItems.map { (categoryName: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
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
                                categoryID: item.categoryID,
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
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Level \(level)"))
    }
}

// 显示技能依赖关系的入口视图
struct SkillDependencySection: View {
    let skillID: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    // 获取等级对应的图标名称
    private func getIconForLevel(_ level: Int) -> String {
        return "skill_lv_\(level + 1)"
    }
    
    var body: some View {
        let itemsByLevel = databaseManager.getAllItemsRequiringSkill(skillID: skillID)
        
        if !itemsByLevel.isEmpty {
            Section(header: Text(NSLocalizedString("Main_Database_Required_By", comment: "")).font(.headline)) {
                ForEach(1...5, id: \.self) { level in
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
                                Image(getIconForLevel(level))
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                
                                Text("Level \(level)")
                            }
                        }
                    }
                }
            }
        }
    }
} 
