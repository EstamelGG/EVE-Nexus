import SwiftUI

// 显示依赖该技能的物品列表
struct SkillDependencyListView: View {
    let skillID: Int
    let level: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    var body: some View {
        List {
            ForEach(databaseManager.getItemsRequiringSkill(skillID: skillID, level: level), id: \.typeID) { item in
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
                            List {
                                ForEach(items, id: \.typeID) { item in
                                    if let categoryID = databaseManager.getCategoryID(for: item.typeID) {
                                        NavigationLink {
                                            ItemInfoMap.getItemInfoView(
                                                itemID: item.typeID,
                                                categoryID: categoryID,
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
                            .listStyle(.insetGrouped)
                            .navigationTitle(Text("Level \(level)"))
                        } label: {
                            Text("Level \(level)")
                        }
                    }
                }
            }
        }
    }
} 
