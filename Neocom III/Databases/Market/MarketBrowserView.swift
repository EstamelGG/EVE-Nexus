import SwiftUI

struct MarketBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var marketGroups: [MarketGroup] = []
    
    var body: some View {
        NavigationView {
            List {
                ForEach(MarketManager.shared.getRootGroups(marketGroups)) { group in
                    MarketGroupRow(group: group, allGroups: marketGroups)
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
    
    var body: some View {
        if MarketManager.shared.isLeafGroup(group, in: allGroups) {
            // 最后一级目录，后续会显示物品列表
            NavigationLink {
                Text("物品列表页面 - 开发中")  // 临时占位
            } label: {
                MarketGroupLabel(group: group)
            }
        } else {
            // 非最后一级目录，显示子目录
            NavigationLink {
                List {
                    ForEach(MarketManager.shared.getSubGroups(allGroups, for: group.id)) { subGroup in
                        MarketGroupRow(group: subGroup, allGroups: allGroups)
                    }
                }
                .navigationTitle(group.name)
            } label: {
                MarketGroupLabel(group: group)
            }
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