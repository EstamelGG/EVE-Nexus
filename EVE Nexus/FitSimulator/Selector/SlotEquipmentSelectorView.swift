import SwiftUI

/// 槽位装备选择器配置（驱动通用的 SlotEquipmentSelectorView）
struct SlotEquipmentSelectorConfig {
    /// 导航标题
    let title: String
    /// 市场组树的父节点ID（如舰船装备=9、改装件=1111、子系统=1112、无人机=157）
    let parentGroupId: Int
    /// UserDefaults 键：上次访问的市场组ID
    let groupIDKey: String
    /// UserDefaults 键：上次搜索关键词
    let searchKey: String
    /// 日志标签（如"高槽装备"、"无人机"）
    let logTag: String
    /// 加载允许的typeID列表
    let loadAllowedTypeIDs: (DatabaseManager) -> [Int]
    /// 选择物品后的回调
    let onItemSelected: (DatabaseListItem) -> Void
    /// onDismiss 时，已选择物品或未搜索（searchText == nil）的情况下是否清空已保存的搜索关键词（无人机选择器的行为）
    let clearsSavedKeywordWhenDismissedWithoutSearch: Bool

    init(
        title: String,
        parentGroupId: Int,
        groupIDKey: String,
        searchKey: String,
        logTag: String,
        loadAllowedTypeIDs: @escaping (DatabaseManager) -> [Int],
        onItemSelected: @escaping (DatabaseListItem) -> Void,
        clearsSavedKeywordWhenDismissedWithoutSearch: Bool = false
    ) {
        self.title = title
        self.parentGroupId = parentGroupId
        self.groupIDKey = groupIDKey
        self.searchKey = searchKey
        self.logTag = logTag
        self.loadAllowedTypeIDs = loadAllowedTypeIDs
        self.onItemSelected = onItemSelected
        self.clearsSavedKeywordWhenDismissedWithoutSearch = clearsSavedKeywordWhenDismissedWithoutSearch
    }
}

/// 槽位装备选择器的共享查询辅助
enum SlotEquipmentSelectorQueries {
    /// 执行查询并提取type_id列表
    static func loadTypeIDs(databaseManager: DatabaseManager, query: String, logTag: String) -> [Int] {
        var typeIDs: [Int] = []
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int {
                    typeIDs.append(typeId)
                }
            }
            Logger.info("加载了 \(typeIDs.count) 个\(logTag)")
        } else {
            Logger.error("加载\(logTag)信息失败")
        }
        return typeIDs
    }
}

/// 通用槽位装备选择器：市场组树导航 + 上次访问目录/搜索关键词持久化
struct SlotEquipmentSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let config: SlotEquipmentSelectorConfig

    @State private var allowedTypeIDs: [Int] = []
    @State private var marketGroupTree: [MarketGroupNode] = []
    @State private var lastVisitedGroupID: Int? = nil
    @State private var lastSearchKeyword: String? = nil
    @State private var hasSelectedItem: Bool = false // 标记是否已选择物品
    @Environment(\.dismiss) private var dismiss

    init(databaseManager: DatabaseManager, config: SlotEquipmentSelectorConfig) {
        self.databaseManager = databaseManager
        self.config = config

        let typeIDs = config.loadAllowedTypeIDs(databaseManager)
        _allowedTypeIDs = State(initialValue: typeIDs)

        // 初始化市场组目录树
        let builder = MarketItemGroupTreeBuilder(
            databaseManager: databaseManager,
            allowedTypeIDs: Set(typeIDs),
            parentGroupId: config.parentGroupId
        )
        _marketGroupTree = State(initialValue: builder.buildGroupTree())

        // 尝试从 UserDefaults 加载上次访问的组ID
        if let savedGroupID = UserDefaults.standard.object(forKey: config.groupIDKey) as? Int {
            Logger.info("从 UserDefaults 加载到之前保存的\(config.logTag)目录ID: \(savedGroupID)")
            _lastVisitedGroupID = State(initialValue: savedGroupID)
        } else {
            Logger.info("未找到保存的\(config.logTag)目录ID")
        }

        // 尝试从 UserDefaults 加载上次搜索关键词
        if let savedKeyword = UserDefaults.standard.string(forKey: config.searchKey) {
            Logger.info("从 UserDefaults 加载到上次搜索关键词: \(savedKeyword)")
            _lastSearchKeyword = State(initialValue: savedKeyword)
        } else {
            Logger.info("未找到保存的搜索关键词")
        }
    }

    var body: some View {
        NavigationStack {
            if allowedTypeIDs.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            } else {
                MarketItemTreeSelectorView(
                    databaseManager: databaseManager,
                    title: config.title,
                    marketGroupTree: marketGroupTree,
                    allowTypeIDs: Set(allowedTypeIDs),
                    existingItems: Set(),
                    onItemSelected: { item in
                        // 标记已选择物品
                        hasSelectedItem = true
                        Logger.info("用户选择了\(config.logTag): \(item.name), ID: \(item.id)")

                        // 保存当前组ID到UserDefaults
                        if let groupID = item.marketGroupID {
                            lastVisitedGroupID = groupID
                            Logger.info("保存\(config.logTag)导航目录ID: \(groupID)")
                            UserDefaults.standard.set(groupID, forKey: config.groupIDKey)
                            // 选择装备时清空搜索关键词
                            UserDefaults.standard.removeObject(forKey: config.searchKey)
                            lastSearchKeyword = nil
                        }

                        config.onItemSelected(item)

                        dismiss()
                    },
                    onItemDeselected: { _ in
                        // 这里暂时不需要处理
                    },
                    onDismiss: { _, searchText in
                        // 处理搜索关键词
                        if let searchText = searchText, !searchText.isEmpty {
                            Logger.info("保存\(config.logTag)搜索关键词: \"\(searchText)\"")
                            UserDefaults.standard.set(searchText, forKey: config.searchKey)
                            lastSearchKeyword = searchText
                        } else if config.clearsSavedKeywordWhenDismissedWithoutSearch,
                                  hasSelectedItem || searchText == nil
                        {
                            // 用户选择了装备或明确清空搜索
                            UserDefaults.standard.removeObject(forKey: config.searchKey)
                            lastSearchKeyword = nil
                        }

                        // 如果没有选择物品，清空保存的导航目录ID
                        if !hasSelectedItem {
                            Logger.info("用户未选择\(config.logTag)，清空保存的导航目录ID")
                            UserDefaults.standard.removeObject(forKey: config.groupIDKey)
                            lastVisitedGroupID = nil
                        }

                        dismiss()
                    },
                    lastVisitedGroupID: lastVisitedGroupID,
                    initialSearchText: lastSearchKeyword
                )
                .interactiveDismissDisabled()
                .onAppear {
                    // 重置选择状态
                    hasSelectedItem = false
                }
            }
        }
    }
}
