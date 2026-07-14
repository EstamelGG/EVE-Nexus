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
    /// 从查询结果行解析 DatabaseListItem 的基本字段
    static func parseItemRow(_ row: [String: Any]) -> DatabaseListItem? {
        guard let id = row["id"] as? Int,
              let name = row["name"] as? String,
              let enName = row["en_name"] as? String,
              let categoryId = row["categoryID"] as? Int
        else {
            return nil
        }

        let iconFileName = (row["iconFileName"] as? String) ?? "not_found"
        let published = (row["published"] as? Int) ?? 0
        let groupID = row["groupID"] as? Int
        let groupName = row["groupName"] as? String

        return DatabaseListItem(
            id: id,
            name: name,
            enName: enName,
            iconFileName: iconFileName,
            published: published == 1,
            categoryID: categoryId,
            groupID: groupID,
            groupName: groupName
        )
    }

    /// 执行查询并解析物品列表
    static func loadItems(
        databaseManager: DatabaseManager, query: String, parameters: [Any] = [], logTag: String
    ) -> [DatabaseListItem] {
        guard case let .success(rows) = databaseManager.executeQuery(query, parameters: parameters)
        else {
            Logger.error("加载\(logTag)信息失败")
            return []
        }

        let items = rows.compactMap { parseItemRow($0) }
        Logger.info("加载了 \(items.count) 个\(logTag)")
        return items
    }

    /// 执行查询并解析物品列表及其槽位号（slotNumber列）
    static func loadItemsWithGroup(
        databaseManager: DatabaseManager, query: String, logTag: String
    ) -> (items: [DatabaseListItem], groupIDs: [Int: Int]) {
        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            Logger.error("加载\(logTag)信息失败")
            return ([], [:])
        }

        var items: [DatabaseListItem] = []
        var groupIDs: [Int: Int] = [:]

        for row in rows {
            guard let item = parseItemRow(row),
                  let slotNumber = row["slotNumber"] as? Double
            else {
                continue
            }
            groupIDs[item.id] = Int(slotNumber)
            items.append(item)
        }

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
                            .frame(width: 30, height: 30)
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
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
