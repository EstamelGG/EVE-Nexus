import SwiftUI

// 显示依赖该技能的物品列表
struct SkillDependencyListView: View {
    let skillID: Int
    let level: Int
    let items: [(typeID: Int, name: String, iconFileName: String)]
    @ObservedObject var databaseManager: DatabaseManager
    
    // 按组分类的物品
    private var itemsByGroup: [(groupName: String, items: [(typeID: Int, name: String, iconFileName: String)])] {
        let groupedItems = Dictionary(grouping: items) { item in
            if let groupInfo = databaseManager.getGroupInfo(for: item.typeID) {
                return groupInfo.groupName
            }
            return "Other"
        }
        return groupedItems.map { (groupName: $0.key, items: $0.value) }
            .sorted { $0.groupName < $1.groupName }
    }
    
    var body: some View {
        List {
            ForEach(itemsByGroup, id: \.groupName) { group in
                Section(header: Text(group.groupName).font(.headline)) {
                    ForEach(group.items, id: \.typeID) { item in
                        NavigationLink {
                            if let categoryID = databaseManager.getCategoryID(for: item.typeID) {
                                ItemInfoMap.getItemInfoView(
                                    itemID: item.typeID,
                                    categoryID: categoryID,
                                    databaseManager: databaseManager
                                )
                            }
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
                            Text("Level \(level)")
                        }
                    }
                }
            }
        }
    }
} 
