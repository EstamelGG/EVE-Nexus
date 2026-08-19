import SwiftUI

/// 平面物品列表选择器配置（驱动通用的 FlatItemSelectorView）
struct FlatItemSelectorConfig {
    /// 导航标题
    let title: String
    /// 日志标签（如"增效剂"、"植入体"）
    let logTag: String
    /// 加载物品列表，同时返回物品ID对应的分组ID（如无分组则返回空字典）
    let loadItems: (DatabaseManager) -> (items: [DatabaseListItem], groupIDs: [Int: Int])
    /// 选择回调（第二参数为分组ID，无分组时为nil）
    let onSelect: (DatabaseListItem, Int?) -> Void
    /// “移除现有物品”按钮的文案（为nil时不显示移除按钮）
    let removeLabel: String?
    /// 移除回调
    let onRemove: (() -> Void)?
    /// 分组标题（提供时按 groupIDs 分组展示，无分组ID的物品不显示）
    let groupTitle: ((Int) -> String)?

    init(
        title: String,
        logTag: String,
        loadItems: @escaping (DatabaseManager) -> (items: [DatabaseListItem], groupIDs: [Int: Int]),
        onSelect: @escaping (DatabaseListItem, Int?) -> Void,
        removeLabel: String? = nil,
        onRemove: (() -> Void)? = nil,
        groupTitle: ((Int) -> String)? = nil
    ) {
        self.title = title
        self.logTag = logTag
        self.loadItems = loadItems
        self.onSelect = onSelect
        self.removeLabel = removeLabel
        self.onRemove = onRemove
        self.groupTitle = groupTitle
    }
}

/// 平面物品列表选择器的共享查询辅助
enum FlatItemSelectorQueries {
    /// 按植入体/增效剂槽位属性（typeAttributes）加载物品：槽位值仍查 typeAttributes（该表未预加载进内存），
    /// 物品信息走 SDEMemoryStore 内存索引。
    /// - Parameters:
    ///   - attributeID: 槽位属性 ID（植入体 331 / 增效剂 1087）
    ///   - slotValue: 指定槽位值；nil 表示全部槽位
    /// - Returns: 物品列表及 typeID → 槽位号的映射
    static func loadSlottedItems(
        databaseManager: DatabaseManager,
        attributeID: Int,
        slotValue: Double? = nil,
        logTag: String
    ) -> (items: [DatabaseListItem], groupIDs: [Int: Int]) {
        var query = "SELECT type_id, value FROM typeAttributes WHERE attribute_id = ?"
        var parameters: [Any] = [attributeID]
        if let slotValue {
            query += " AND value = ?"
            parameters.append(slotValue)
        }

        guard case let .success(rows) = databaseManager.executeQuery(query, parameters: parameters)
        else {
            Logger.error("加载\(logTag)槽位信息失败")
            return ([], [:])
        }

        var items: [DatabaseListItem] = []
        var groupIDs: [Int: Int] = [:]
        for row in rows {
            guard let typeID = row["type_id"] as? Int,
                  let value = row["value"] as? Double,
                  let info = SDEMemoryStore.type(for: typeID),
                  info.published,
                  info.marketGroupID != nil,
                  let item = DatabaseListItem(typeID: typeID, databaseManager: databaseManager)
            else { continue }
            groupIDs[typeID] = Int(value)
            items.append(item)
        }
        items.sort { $0.id < $1.id }
        Logger.info("加载了 \(items.count) 个\(logTag)")
        return (items, groupIDs)
    }
}

/// 通用平面物品列表选择器：搜索 + 可选移除按钮 + 可选分组展示
struct FlatItemSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let config: FlatItemSelectorConfig

    @State private var items: [DatabaseListItem] = []
    @State private var groupIDs: [Int: Int] = [:]
    @State private var searchText: String = ""
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                        .padding()
                } else {
                    List {
                        // 移除现有物品按钮
                        if let removeLabel = config.removeLabel {
                            Section {
                                Button(action: {
                                    config.onRemove?()
                                    dismiss()
                                }) {
                                    HStack {
                                        Text(removeLabel)
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
                                        systemImage: "exclamationmark.triangle"
                                    )
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .listRowBackground(Color.clear)
                            }
                        } else if let groupTitle = config.groupTitle {
                            // 分组展示
                            ForEach(groupedItems, id: \.id) { group in
                                Section(header: Text(groupTitle(group.id))) {
                                    ForEach(group.items.sorted { $0.id < $1.id }) { item in
                                        ItemRowWithInfo(item: item, databaseManager: databaseManager) {
                                            config.onSelect(item, group.id)
                                            dismiss()
                                        }
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        } else {
                            Section {
                                ForEach(filteredItems.sorted { $0.id < $1.id }) { item in
                                    ItemRowWithInfo(item: item, databaseManager: databaseManager) {
                                        config.onSelect(item, nil)
                                        dismiss()
                                    }
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            }
                        }
                    }
                    .searchable(
                        text: $searchText,
                        // placement: .navigationBarDrawer(displayMode: .always),
                        prompt: NSLocalizedString("Main_Search", comment: "搜索")
                    )
                }
            }
            .navigationTitle(config.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .onAppear {
            loadItems()
        }
    }

    /// 根据搜索文本过滤物品
    private var filteredItems: [DatabaseListItem] {
        if searchText.isEmpty {
            return items
        } else {
            return items.filter { item in
                SDEMemoryStore.type(for: item.id)?.names.matchesSearch(searchText) == true
            }
        }
    }

    /// 按分组整理过滤后的物品（无分组ID的物品不显示）
    private var groupedItems: [(id: Int, items: [DatabaseListItem])] {
        var grouped: [Int: [DatabaseListItem]] = [:]
        for item in filteredItems {
            if let groupID = groupIDs[item.id] {
                grouped[groupID, default: []].append(item)
            }
        }
        return grouped.keys.sorted().map { (id: $0, items: grouped[$0] ?? []) }
    }

    /// 加载物品
    private func loadItems() {
        isLoading = true
        let result = config.loadItems(databaseManager)
        items = result.items
        groupIDs = result.groupIDs
        isLoading = false
    }
}

/// 带信息按钮的物品行组件
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
