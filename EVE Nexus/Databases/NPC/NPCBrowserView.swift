import SwiftUI

enum NPCBrowserLevel {
    case scene
    case faction
    case type
    case items
}

// 基础NPC视图
struct NPCBaseView<Content: View>: View {
    @ObservedObject var databaseManager: DatabaseManager
    let title: String
    let content: Content
    let searchQuery: (String) -> String
    let searchParameters: (String) -> [Any]

    @State private var items: [NPCItem] = []
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var isLoading = false
    @State private var isShowingSearchResults = false
    @StateObject private var searchController = SearchController()

    // 搜索结果分组
    var groupedSearchResults: [(id: Int, name: String, items: [NPCItem])] {
        guard !items.isEmpty else { return [] }

        // 按场景分类
        var groupItems: [String: [NPCItem]] = [:]

        // 获取所有物品的场景信息
        let typeIDs = items.map { String($0.typeID) }.joined(separator: ",")
        let query = "SELECT type_id, npc_ship_scene FROM types WHERE type_id IN (\(typeIDs))"

        if case let .success(rows) = databaseManager.executeQuery(query) {
            // 创建typeID到scene的映射
            var sceneMap: [Int: String] = [:]
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                    let scene = row["npc_ship_scene"] as? String
                {
                    sceneMap[typeID] = scene
                }
            }

            // 按场景分组
            for item in items {
                if let scene = sceneMap[item.typeID] {
                    if groupItems[scene] == nil {
                        groupItems[scene] = []
                    }
                    groupItems[scene]?.append(item)
                }
            }
        }

        // 转换为所需格式
        return groupItems.enumerated().map { index, group in
            (id: index, name: group.key, items: group.value.sorted(by: { $0.name < $1.name }))
        }.sorted(by: { $0.name < $1.name })
    }

    var body: some View {
        List {
            if isShowingSearchResults {
                // 搜索结果视图，按场景分组显示
                ForEach(groupedSearchResults, id: \.id) { group in
                    Section(
                        header: Text(group.name)
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    ) {
                        ForEach(group.items, id: \.typeID) { item in
                            NavigationLink {
                                if let categoryID = databaseManager.getCategoryID(for: item.typeID)
                                {
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
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            } else {
                content
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Database_Search", comment: ""))
        )
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                isShowingSearchResults = false
                isLoading = false
                items = []
            } else {
                isLoading = true
                items = []
                if newValue.count >= 1 {
                    searchController.processSearchInput(newValue)
                }
            }
        }
        .overlay {
            if isLoading {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .overlay {
                        VStack {
                            ProgressView()
                            Text(NSLocalizedString("Main_Database_Searching", comment: ""))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
            } else if items.isEmpty && !searchText.isEmpty {
                ContentUnavailableView {
                    Label("Not Found", systemImage: "magnifyingglass")
                }
            } else if searchText.isEmpty && isSearchActive {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isSearchActive = false
                    }
            }
        }
        .navigationTitle(title)
        .onAppear {
            setupSearch()
        }
    }

    private func setupSearch() {
        searchController.debouncedSearchPublisher
            .receive(on: DispatchQueue.main)
            .sink { query in
                guard !searchText.isEmpty else { return }
                performSearch(with: query)
            }
            .store(in: &searchController.cancellables)
    }

    private func performSearch(with text: String) {
        isLoading = true

        let whereClause = searchQuery(text)
        let parameters = searchParameters(text)

        let query = """
                SELECT t.type_id, t.name, t.icon_filename
                FROM types t
                WHERE \(whereClause)
                ORDER BY t.name
            """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: parameters) {
            items = rows.compactMap { row in
                guard let typeID = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                else {
                    return nil
                }
                return NPCItem(
                    typeID: typeID,
                    name: name,
                    iconFileName: iconFileName.isEmpty
                        ? DatabaseConfig.defaultItemIcon : iconFileName
                )
            }
            isShowingSearchResults = true
        }

        isLoading = false
    }
}

struct NPCBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let level: NPCBrowserLevel
    let scene: String?
    let faction: String?
    let type: String?

    init(
        databaseManager: DatabaseManager, level: NPCBrowserLevel = .scene, scene: String? = nil,
        faction: String? = nil, type: String? = nil
    ) {
        self.databaseManager = databaseManager
        self.level = level
        self.scene = scene
        self.faction = faction
        self.type = type
    }

    var body: some View {
        let content: AnyView = {
            switch level {
            case .scene:
                return AnyView(
                    ForEach(databaseManager.getNPCScenes(), id: \.self) { scene in
                        NavigationLink(
                            destination: NPCBrowserView(
                                databaseManager: databaseManager, level: .faction, scene: scene
                            )
                        ) {
                            HStack {
                                IconManager.shared.loadImage(for: "items_73_16_50.png")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(scene)
                            }
                        }
                    }
                )
            case .faction:
                if let scene = scene {
                    return AnyView(
                        ForEach(databaseManager.getNPCFactions(for: scene), id: \.self) { faction in
                            NavigationLink(
                                destination: NPCBrowserView(
                                    databaseManager: databaseManager, level: .type, scene: scene,
                                    faction: faction
                                )
                            ) {
                                HStack {
                                    if let iconFileName = databaseManager.getNPCFactionIcon(
                                        for: faction)
                                    {
                                        IconManager.shared.loadImage(for: iconFileName)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)
                                    }
                                    Text(faction)
                                }
                            }
                        }
                    )
                } else {
                    return AnyView(EmptyView())
                }
            case .type:
                if let scene = scene, let faction = faction {
                    return AnyView(
                        ForEach(
                            databaseManager.getNPCTypes(for: scene, faction: faction), id: \.self
                        ) { type in
                            NavigationLink(
                                destination: NPCBrowserView(
                                    databaseManager: databaseManager, level: .items, scene: scene,
                                    faction: faction, type: type
                                )
                            ) {
                                HStack {
                                    IconManager.shared.loadImage(for: "items_73_16_50.png")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)
                                    Text(type)
                                }
                            }
                        }
                    )
                } else {
                    return AnyView(EmptyView())
                }
            case .items:
                if let scene = scene, let faction = faction, let type = type {
                    return AnyView(
                        ForEach(
                            databaseManager.getNPCItems(for: scene, faction: faction, type: type),
                            id: \.typeID
                        ) { item in
                            NavigationLink {
                                if let categoryID = databaseManager.getCategoryID(for: item.typeID)
                                {
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
                                }
                            }
                        }
                    )
                } else {
                    return AnyView(EmptyView())
                }
            }
        }()

        NPCBaseView(
            databaseManager: databaseManager,
            title: getNavigationTitle(),
            content: content,
            searchQuery: { _ in
                switch level {
                case .scene:
                    return
                        "t.npc_ship_scene IS NOT NULL AND t.npc_ship_scene IN (SELECT DISTINCT npc_ship_scene FROM types WHERE npc_ship_scene IS NOT NULL) AND (t.name LIKE ? OR t.en_name LIKE ? OR t.type_id = ?)"
                case .faction:
                    return
                        "t.npc_ship_scene = ? AND t.npc_ship_faction IN (SELECT DISTINCT npc_ship_faction FROM types WHERE npc_ship_scene = ?) AND (t.name LIKE ? OR t.en_name LIKE ? OR t.type_id = ?)"
                case .type:
                    return
                        "t.npc_ship_scene = ? AND t.npc_ship_faction = ? AND t.npc_ship_type IN (SELECT DISTINCT npc_ship_type FROM types WHERE npc_ship_scene = ? AND npc_ship_faction = ?) AND (t.name LIKE ? OR t.en_name LIKE ? OR t.type_id = ?)"
                case .items:
                    return
                        "t.npc_ship_scene = ? AND t.npc_ship_faction = ? AND t.npc_ship_type = ? AND (t.name LIKE ? OR t.en_name LIKE ? OR t.type_id = ?)"
                }
            },
            searchParameters: { text in
                switch level {
                case .scene:
                    return ["%\(text)%", "%\(text)%", "\(text)"]
                case .faction:
                    guard let scene = scene else { return [] }
                    return [scene, scene, "%\(text)%", "%\(text)%", "\(text)"]
                case .type:
                    guard let scene = scene, let faction = faction else { return [] }
                    return [scene, faction, scene, faction, "%\(text)%", "%\(text)%", "\(text)"]
                case .items:
                    guard let scene = scene, let faction = faction, let type = type else {
                        return []
                    }
                    return [scene, faction, type, "%\(text)%", "%\(text)%", "\(text)"]
                }
            }
        )
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
