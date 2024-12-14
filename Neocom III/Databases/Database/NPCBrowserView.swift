import SwiftUI

enum NPCBrowserLevel {
    case scene
    case faction
    case type
    case items
}

struct NPCBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let level: NPCBrowserLevel
    let scene: String?
    let faction: String?
    let type: String?
    
    init(databaseManager: DatabaseManager, level: NPCBrowserLevel = .scene, scene: String? = nil, faction: String? = nil, type: String? = nil) {
        self.databaseManager = databaseManager
        self.level = level
        self.scene = scene
        self.faction = faction
        self.type = type
    }
    
    var body: some View {
        List {
            switch level {
            case .scene:
                // 显示一级目录（场景）列表
                ForEach(databaseManager.getNPCScenes(), id: \.self) { scene in
                    NavigationLink(destination: NPCBrowserView(databaseManager: databaseManager, level: .faction, scene: scene)) {
                        Text(scene)
                    }
                }
            case .faction:
                // 显示二级目录（阵营）列表
                if let scene = scene {
                    ForEach(databaseManager.getNPCFactions(for: scene), id: \.self) { faction in
                        NavigationLink(destination: NPCBrowserView(databaseManager: databaseManager, level: .type, scene: scene, faction: faction)) {
                            Text(faction)
                        }
                    }
                }
            case .type:
                // 显示三级目录（类型）列表
                if let scene = scene, let faction = faction {
                    ForEach(databaseManager.getNPCTypes(for: scene, faction: faction), id: \.self) { type in
                        NavigationLink(destination: NPCBrowserView(databaseManager: databaseManager, level: .items, scene: scene, faction: faction, type: type)) {
                            Text(type)
                        }
                    }
                }
            case .items:
                // 显示物品列表
                if let scene = scene, let faction = faction, let type = type {
                    ForEach(databaseManager.getNPCItems(for: scene, faction: faction, type: type), id: \.typeID) { item in
                        NavigationLink {
                            if let categoryID = databaseManager.getCategoryID(for: item.typeID) {
                                ItemInfoMap.getItemInfoView(itemID: item.typeID, categoryID: categoryID, databaseManager: databaseManager)
                            }
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: item.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(item.name)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(getNavigationTitle())
    }
    
    private func getNavigationTitle() -> String {
        switch level {
        case .scene:
            return NSLocalizedString("Main_Database_NPC_Scene", comment: "")
        case .faction:
            return scene ?? ""
        case .type:
            return faction ?? ""
        case .items:
            return type ?? NSLocalizedString("Main_Database_NPC_Ships", comment: "")
        }
    }
}

#Preview {
    NPCBrowserView(databaseManager: DatabaseManager())
} 