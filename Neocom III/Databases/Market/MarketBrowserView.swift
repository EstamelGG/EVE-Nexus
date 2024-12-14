import SwiftUI

struct MarketBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var marketGroups: [MarketGroup] = []
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(MarketManager.shared.getRootGroups(marketGroups)) { group in
                    MarketGroupRow(group: group, allGroups: marketGroups, databaseManager: databaseManager)
                }
            }
            .navigationTitle(NSLocalizedString("Main_Market", comment: ""))
            .onAppear {
                marketGroups = MarketManager.shared.loadMarketGroups(databaseManager: databaseManager)
            }
        }
    }
}

struct MarketGroupRow: View {
    let group: MarketGroup
    let allGroups: [MarketGroup]
    let databaseManager: DatabaseManager
    
    var body: some View {
        if MarketManager.shared.isLeafGroup(group, in: allGroups) {
            // 最后一级目录，显示物品列表
            NavigationLink {
                MarketItemListView(
                    databaseManager: databaseManager,
                    marketGroupID: group.id,
                    title: group.name
                )
            } label: {
                MarketGroupLabel(group: group)
            }
        } else {
            // 非最后一级目录，显示子目录
            NavigationLink {
                List {
                    ForEach(MarketManager.shared.getSubGroups(allGroups, for: group.id)) { subGroup in
                        MarketGroupRow(group: subGroup, allGroups: allGroups, databaseManager: databaseManager)
                    }
                }
                .navigationTitle(group.name)
            } label: {
                MarketGroupLabel(group: group)
            }
        }
    }
}

struct MarketItemListView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let marketGroupID: Int
    let title: String
    
    @State private var items: [DatabaseListItem] = []
    @State private var metaGroupNames: [Int: String] = [:]
    
    var groupedItems: [(id: Int, name: String, items: [DatabaseListItem])] {
        let publishedItems = items.filter { $0.published }
        let unpublishedItems = items.filter { !$0.published }
        
        var result: [(id: Int, name: String, items: [DatabaseListItem])] = []
        
        // 按科技等级分组
        var techLevelGroups: [Int: [DatabaseListItem]] = [:]
        for item in publishedItems {
            let techLevel = item.metaGroupID ?? 0
            if techLevelGroups[techLevel] == nil {
                techLevelGroups[techLevel] = []
            }
            techLevelGroups[techLevel]?.append(item)
        }
        
        // 添加已发布物品组
        for (techLevel, items) in techLevelGroups.sorted(by: { $0.key < $1.key }) {
            let name = metaGroupNames[techLevel] ?? NSLocalizedString("Main_Database_base", comment: "基础物品")
            result.append((id: techLevel, name: name, items: items))
        }
        
        // 添加未发布物品组
        if !unpublishedItems.isEmpty {
            result.append((
                id: -1,
                name: NSLocalizedString("Main_Database_unpublished", comment: "未发布"),
                items: unpublishedItems
            ))
        }
        
        return result
    }
    
    var body: some View {
        List {
            ForEach(groupedItems, id: \.id) { group in
                Section(header: Text(group.name)
                    .fontWeight(.bold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
                ) {
                    ForEach(group.items) { item in
                        NavigationLink {
                            MarketItemDetailView(
                                databaseManager: databaseManager,
                                itemID: item.id
                            )
                        } label: {
                            DatabaseListItemView(
                                item: item,
                                showDetails: true
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .onAppear {
            loadItems()
        }
    }
    
    private func loadItems() {
        // 加载该市场组下的所有物品
        let query = """
            SELECT type_id as id, name, published, icon_filename as iconFileName,
                   categoryID, groupID, metaGroupID,
                   pg_need as pgNeed, cpu_need as cpuNeed, rig_cost as rigCost,
                   em_damage as emDamage, them_damage as themDamage, kin_damage as kinDamage, exp_damage as expDamage,
                   high_slot as highSlot, mid_slot as midSlot, low_slot as lowSlot,
                   rig_slot as rigSlot, gun_slot as gunSlot, miss_slot as missSlot
            FROM types
            WHERE marketGroupID = ?
            ORDER BY name
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [marketGroupID]) {
            items = rows.compactMap { row in
                guard let id = row["id"] as? Int,
                      let name = row["name"] as? String,
                      let iconFileName = row["iconFileName"] as? String,
                      let published = row["published"] as? Int
                else { return nil }
                
                return DatabaseListItem(
                    id: id,
                    name: name,
                    iconFileName: iconFileName,
                    published: published == 1,
                    categoryID: row["categoryID"] as? Int,
                    groupID: row["groupID"] as? Int,
                    pgNeed: row["pgNeed"] as? Int,
                    cpuNeed: row["cpuNeed"] as? Int,
                    rigCost: row["rigCost"] as? Int,
                    emDamage: row["emDamage"] as? Double,
                    themDamage: row["themDamage"] as? Double,
                    kinDamage: row["kinDamage"] as? Double,
                    expDamage: row["expDamage"] as? Double,
                    highSlot: row["highSlot"] as? Int,
                    midSlot: row["midSlot"] as? Int,
                    lowSlot: row["lowSlot"] as? Int,
                    rigSlot: row["rigSlot"] as? Int,
                    gunSlot: row["gunSlot"] as? Int,
                    missSlot: row["missSlot"] as? Int,
                    metaGroupID: row["metaGroupID"] as? Int,
                    navigationDestination: AnyView(EmptyView())
                )
            }
            
            // 加载科技等级名称
            let metaGroupIDs = Set(items.compactMap { $0.metaGroupID })
            metaGroupNames = databaseManager.loadMetaGroupNames(for: Array(metaGroupIDs))
        }
    }
}

struct MarketGroupLabel: View {
    let group: MarketGroup
    
    var body: some View {
        HStack {
            IconManager.shared.loadImage(for: group.iconName)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
            
            Text(group.name)
                .font(.body)
        }
    }
}

#Preview {
    MarketBrowserView(databaseManager: DatabaseManager())
} 
