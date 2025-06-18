import SwiftUI

// 植入体选择器
struct ImplantSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let slotNumber: Int
    let hasExistingItem: Bool
    @State private var implantItems: [DatabaseListItem] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    // 存储metaGroup信息的字典
    @State private var metaGroups: [Int: String] = [:]
    // 按metaGroupID分组的植入体
    @State private var groupedImplants: [Int?: [DatabaseListItem]] = [:]

    let onSelect: (DatabaseListItem) -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                        .padding()
                } else {
                    List {
                        if hasExistingItem {
                            Section {
                                Button(action: {
                                    onRemove?()
                                    dismiss()
                                }) {
                                    HStack {
                                        Text(NSLocalizedString("Remove_Current_Implant", comment: "移除现有植入体"))
                                            .foregroundColor(.red)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        
                        if filteredItems.isEmpty {
                            Section {
                                ContentUnavailableView {
                                    Label(
                                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                                        systemImage: "exclamationmark.triangle")
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .listRowBackground(Color.clear)
                            }
                        } else {
                            // 按metaGroupID分组展示
                            ForEach(groupedFilteredItems.keys.sorted { sortMetaGroups($0, $1) }, id: \.self) { metaGroupID in
                                if let items = groupedFilteredItems[metaGroupID] {
                                    Section(header: Text(metaGroupName(for: metaGroupID))) {
                                        ForEach(items) { item in
                                            ItemRowWithInfo(item: item, databaseManager: databaseManager) {
                                                onSelect(item)
                                                dismiss()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: NSLocalizedString("Main_Search", comment: "搜索")
                    )
                }
            }
            .navigationTitle(String(format: NSLocalizedString("Implant_Slot_Num", comment: "植入体槽位 %d"), slotNumber))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .onAppear {
            loadMetaGroups()
            loadImplantItems()
        }
    }
    
    // 根据搜索文本过滤物品
    private var filteredItems: [DatabaseListItem] {
        if searchText.isEmpty {
            return implantItems
        } else {
            return implantItems.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // 按metaGroupID分组的过滤后物品
    private var groupedFilteredItems: [Int?: [DatabaseListItem]] {
        Dictionary(grouping: filteredItems) { $0.metaGroupID }
    }
    
    // 获取metaGroup名称
    private func metaGroupName(for metaGroupID: Int?) -> String {
        if let id = metaGroupID, let name = metaGroups[id] {
            return name
        }
        return NSLocalizedString("Unknown_Meta_Group", comment: "未知衍生等级")
    }
    
    // 排序metaGroup
    private func sortMetaGroups(_ a: Int?, _ b: Int?) -> Bool {
        // 处理nil值
        guard let a = a else { return false }
        guard let b = b else { return true }
        
        // 直接按metaGroupID大小排序
        return a < b
    }
    
    // 加载metaGroups数据
    private func loadMetaGroups() {
        let query = "SELECT metagroup_id, name FROM metaGroups"
        
        if case let .success(rows) = databaseManager.executeQuery(query) {
            var groups: [Int: String] = [:]
            
            for row in rows {
                if let id = row["metagroup_id"] as? Int,
                   let name = row["name"] as? String {
                    groups[id] = name
                }
            }
            
            metaGroups = groups
            Logger.info("加载了 \(metaGroups.count) 个metaGroup")
        } else {
            Logger.error("加载metaGroups信息失败")
        }
    }
    
    // 加载植入体物品
    private func loadImplantItems() {
        isLoading = true
        
        // 获取指定槽位的植入体信息，包含metaGroupID
        let query = """
            SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                   t.categoryID, t.groupID, t.group_name as groupName, t.metaGroupID
            FROM types t
            JOIN typeAttributes ta ON t.type_id = ta.type_id
            WHERE ta.attribute_id = 331
            AND ta.value = ?
            AND t.published = 1
            AND t.marketGroupID IS NOT NULL
            ORDER BY t.name
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [slotNumber]) {
            var items: [DatabaseListItem] = []
            
            for row in rows {
                if let id = row["id"] as? Int,
                   let name = row["name"] as? String,
                   let categoryId = row["categoryID"] as? Int
                {
                    let iconFileName = (row["iconFileName"] as? String) ?? "not_found"
                    let published = (row["published"] as? Int) ?? 0
                    let groupID = row["groupID"] as? Int
                    let groupName = row["groupName"] as? String
                    let metaGroupID = row["metaGroupID"] as? Int
                    
                    let item = DatabaseListItem(
                        id: id,
                        name: name,
                        iconFileName: iconFileName,
                        published: published == 1,
                        categoryID: categoryId,
                        groupID: groupID,
                        groupName: groupName,
                        pgNeed: nil,
                        cpuNeed: nil,
                        rigCost: nil,
                        emDamage: nil,
                        themDamage: nil,
                        kinDamage: nil,
                        expDamage: nil,
                        highSlot: nil,
                        midSlot: nil,
                        lowSlot: nil,
                        rigSlot: nil,
                        gunSlot: nil,
                        missSlot: nil,
                        metaGroupID: metaGroupID,
                        marketGroupID: nil,
                        navigationDestination: AnyView(EmptyView())
                    )
                    
                    items.append(item)
                }
            }
            
            implantItems = items
            Logger.info("加载了 \(implantItems.count) 个植入体")
        } else {
            Logger.error("加载植入体信息失败")
        }
        
        isLoading = false
    }
}

// 带信息按钮的物品行组件
struct ItemRowWithInfo: View {
    let item: DatabaseListItem
    let databaseManager: DatabaseManager
    let onTap: () -> Void
    @State private var showingItemInfo = false
    
    var body: some View {
        HStack {
            ItemNodeRow(item: item) {
                onTap()
            }
            Spacer()
            Button {
                showingItemInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(BorderlessButtonStyle())
            .sheet(isPresented: $showingItemInfo) {
                NavigationStack {
                    ShowItemInfo(databaseManager: databaseManager, itemID: item.id)
                }
                .presentationDragIndicator(.visible)
            }
        }
    }
}
