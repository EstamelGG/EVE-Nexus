import SwiftUI

// 无人机选择器
struct DroneSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var allowedTypeIDs: [Int] = []
    @State private var droneInfos: [DroneInfo] = []  // 无人机信息数组
    @State private var marketGroupTree: [MarketGroupNode] = []
    @State private var lastVisitedGroupID: Int? = nil  // 上次访问的组ID状态
    @State private var lastSearchKeyword: String? = nil  // 上次搜索关键词状态
    @State private var hasSelectedItem: Bool = false  // 标记是否已选择物品
    @Environment(\.dismiss) private var dismiss

    let onSelect: (DatabaseListItem) -> Void

    init(databaseManager: DatabaseManager, onSelect: @escaping (DatabaseListItem) -> Void) {
        self.databaseManager = databaseManager
        self.onSelect = onSelect
        let droneData = loadDroneData(databaseManager: databaseManager)
        self._allowedTypeIDs = State(initialValue: droneData.map { $0.typeId })
        self._droneInfos = State(initialValue: droneData)

        // 初始化市场组目录树
        let builder = MarketItemGroupTreeBuilder(
            databaseManager: databaseManager,
            allowedTypeIDs: Set(droneData.map { $0.typeId }),
            parentGroupId: 157  // 使用无人机(ID: 157)作为父节点
        )
        let tree = builder.buildGroupTree()
        self._marketGroupTree = State(initialValue: tree)

        // 尝试从 UserDefaults 加载上次访问的组ID
        if let savedGroupID = UserDefaults.standard.object(forKey: "LastVisitedDroneGroupID")
            as? Int
        {
            Logger.info("从 UserDefaults 加载到之前保存的无人机目录ID: \(savedGroupID)")
            self._lastVisitedGroupID = State(initialValue: savedGroupID)
        } else {
            Logger.info("未找到保存的无人机目录ID")
            self._lastVisitedGroupID = State(initialValue: nil)
        }

        // 尝试从 UserDefaults 加载上次搜索关键词
        if let savedKeyword = UserDefaults.standard.string(forKey: "LastDroneSearchKeyword") {
            Logger.info("从 UserDefaults 加载到上次搜索关键词: \(savedKeyword)")
            self._lastSearchKeyword = State(initialValue: savedKeyword)
        } else {
            Logger.info("未找到保存的搜索关键词")
            self._lastSearchKeyword = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            if self.allowedTypeIDs.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "exclamationmark.triangle")
                }
            } else {
                MarketItemTreeSelectorView(
                    databaseManager: databaseManager,
                    title: NSLocalizedString("Fitting_Select_Drone", comment: "选择无人机"),
                    marketGroupTree: marketGroupTree,
                    allowTypeIDs: Set(allowedTypeIDs),
                    existingItems: Set(),
                    onItemSelected: { item in
                        // 标记已选择物品
                        hasSelectedItem = true
                        // 保存当前组ID到UserDefaults
                        if let groupID = item.marketGroupID {
                            self.lastVisitedGroupID = groupID
                            Logger.info("用户选择无人机，保存无人机导航目录ID: \(groupID)，无人机: \(item.name)")
                            UserDefaults.standard.set(groupID, forKey: "LastVisitedDroneGroupID")
                            // 选择装备时清空搜索关键词
                            UserDefaults.standard.removeObject(forKey: "LastDroneSearchKeyword")
                            lastSearchKeyword = nil
                        }
                        dismiss()
                        onSelect(item)
                    },
                    onItemDeselected: { _ in
                        // 这里不需要处理取消选择的逻辑
                    },
                    onDismiss: { groupID, searchText in
                        // 处理搜索关键词
                        Logger.info(
                            "onDismiss回调收到：groupID=\(groupID != nil ? String(groupID!) : "nil"), searchText=\(searchText != nil ? "\"\(searchText!)\"" : "nil")"
                        )

                        if let searchText = searchText, !searchText.isEmpty {
                            Logger.info("保存无人机搜索关键词到UserDefaults: \"\(searchText)\"")
                            UserDefaults.standard.set(
                                searchText, forKey: "LastDroneSearchKeyword")
                            lastSearchKeyword = searchText
                            // 确保立即写入
                            UserDefaults.standard.synchronize()
                            Logger.info("搜索关键词保存完成")
                        } else if hasSelectedItem || searchText == nil {
                            // 用户选择了装备或明确清空搜索
                            Logger.info(
                                "清空保存的搜索关键词，hasSelectedItem=\(hasSelectedItem), searchText为\(searchText == nil ? "nil" : "空字符串")"
                            )
                            UserDefaults.standard.removeObject(forKey: "LastDroneSearchKeyword")
                            lastSearchKeyword = nil
                            // 确保立即写入
                            UserDefaults.standard.synchronize()
                        }

                        // 如果没有选择物品，清空保存的导航目录ID
                        if !hasSelectedItem {
                            Logger.info("用户未选择无人机，清空保存的导航目录ID")
                            UserDefaults.standard.removeObject(forKey: "LastVisitedDroneGroupID")
                            self.lastVisitedGroupID = nil
                            // 确保立即写入
                            UserDefaults.standard.synchronize()
                        }
                        Logger.info("关闭选择器")
                        dismiss()
                    },
                    lastVisitedGroupID: lastVisitedGroupID,
                    initialSearchText: lastSearchKeyword
                )
                .interactiveDismissDisabled()
                .onAppear {
                    Logger.info(
                        "无人机选择器显示，lastSearchKeyword: \(lastSearchKeyword != nil ? "\"\(lastSearchKeyword!)\"" : "nil")"
                    )
                    // 重置选择状态
                    hasSelectedItem = false
                }
                .onDisappear {
                    // 视图消失时检查最后状态
                    Logger.info(
                        "无人机选择器消失，hasSelectedItem: \(hasSelectedItem), lastSearchKeyword: \(lastSearchKeyword != nil ? "\"\(lastSearchKeyword!)\"" : "nil")"
                    )
                    // 再次检查UserDefaults中保存的值
                    if let savedKeyword = UserDefaults.standard.string(
                        forKey: "LastDroneSearchKeyword")
                    {
                        Logger.info("UserDefaults中保存的搜索关键词: \"\(savedKeyword)\"")
                    } else {
                        Logger.info("UserDefaults中没有保存搜索关键词")
                    }
                }
            }
        }
    }



    // 加载无人机的type_id及名称信息
    private func loadDroneData(databaseManager: DatabaseManager) -> [DroneInfo] {
        // 获取无人机(categoryID=18)的信息，并确保是已发布的(published=1)
        let query = """
                SELECT type_id, name, en_name, marketGroupID
                FROM types
                WHERE categoryID = 18
                AND published = 1
            """

        var droneInfos: [DroneInfo] = []

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String,
                    let enName = row["en_name"] as? String
                {
                    let marketGroupId = row["marketGroupID"] as? Int

                    let info = DroneInfo(
                        typeId: typeId,
                        name: name,
                        enName: enName,
                        marketGroupId: marketGroupId
                    )
                    droneInfos.append(info)
                }
            }
            Logger.info("加载了 \(droneInfos.count) 个无人机")
        } else {
            Logger.error("加载无人机信息失败")
        }

        return droneInfos
    }
}

// 无人机信息结构体
private struct DroneInfo: Identifiable {
    let id: Int
    let typeId: Int
    let name: String
    let enName: String
    let marketGroupId: Int?

    init(typeId: Int, name: String, enName: String, marketGroupId: Int?) {
        self.id = typeId
        self.typeId = typeId
        self.name = name
        self.enName = enName
        self.marketGroupId = marketGroupId
    }
} 