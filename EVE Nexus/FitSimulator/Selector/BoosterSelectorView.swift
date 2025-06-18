import SwiftUI

// 增效剂选择器
struct BoosterSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let slotNumber: Int
    let hasExistingItem: Bool
    @State private var boosterItems: [DatabaseListItem] = []
    @State private var searchText: String = ""
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss

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
                                        Text(NSLocalizedString("Remove_Current_Booster", comment: "移除现有增效剂"))
                                            .foregroundColor(.red)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        
                        Section {
                            if filteredItems.isEmpty {
                                ContentUnavailableView {
                                    Label(
                                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                                        systemImage: "exclamationmark.triangle")
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .listRowBackground(Color.clear)
                            } else {
                                ForEach(filteredItems) { item in
                                    ItemRowWithInfo(item: item, databaseManager: databaseManager) {
                                        onSelect(item)
                                        dismiss()
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
            .navigationTitle(String(format: NSLocalizedString("Booster_Slot_Num", comment: "增效剂槽位 %d"), slotNumber))
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
            loadBoosterItems()
        }
    }
    
    // 根据搜索文本过滤物品
    private var filteredItems: [DatabaseListItem] {
        if searchText.isEmpty {
            return boosterItems
        } else {
            return boosterItems.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // 加载增效剂物品
    private func loadBoosterItems() {
        isLoading = true
        
        // 获取指定槽位的增效剂信息
        let query = """
            SELECT t.type_id as id, t.name, t.published, t.icon_filename as iconFileName,
                   t.categoryID, t.groupID, t.group_name as groupName
            FROM types t
            JOIN typeAttributes ta ON t.type_id = ta.type_id
            WHERE ta.attribute_id = 1087
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
                        metaGroupID: nil,
                        marketGroupID: nil,
                        navigationDestination: AnyView(EmptyView())
                    )
                    
                    items.append(item)
                }
            }
            
            boosterItems = items
            Logger.info("加载了 \(boosterItems.count) 个增效剂")
        } else {
            Logger.error("加载增效剂信息失败")
        }
        
        isLoading = false
    }
}
