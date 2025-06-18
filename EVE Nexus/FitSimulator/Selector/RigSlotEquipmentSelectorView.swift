import SwiftUI

// 改装槽装备选择器视图
struct RigSlotEquipmentSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var allowedTypeIDs: [Int] = []
    @State private var equipmentInfos: [EquipmentInfo] = []
    @State private var marketGroupTree: [MarketGroupNode] = []
    @State private var lastVisitedGroupID: Int? = nil
    @State private var lastSearchKeyword: String? = nil
    @State private var hasSelectedItem: Bool = false  // 添加标记，跟踪是否已选择物品
    @Environment(\.dismiss) private var dismiss
    
    // 船只ID，用于查询匹配的改装件
    let shipTypeID: Int
    // 添加槽位信息和回调函数
    let slotFlag: FittingFlag
    let onModuleSelected: ((Int) -> Void)?
    
    // 初始化方法
    init(
        databaseManager: DatabaseManager, 
        shipTypeID: Int, 
        slotFlag: FittingFlag,
        onModuleSelected: ((Int) -> Void)? = nil
    ) {
        self.databaseManager = databaseManager
        self.shipTypeID = shipTypeID
        self.slotFlag = slotFlag
        self.onModuleSelected = onModuleSelected
        
        let equipmentData = loadEquipmentData(databaseManager: databaseManager, shipTypeID: shipTypeID)
        self._allowedTypeIDs = State(initialValue: equipmentData.map { $0.typeId })
        self._equipmentInfos = State(initialValue: equipmentData)
        
        // 初始化市场组目录树
        let builder = MarketItemGroupTreeBuilder(
            databaseManager: databaseManager,
            allowedTypeIDs: Set(equipmentData.map { $0.typeId }),
            parentGroupId: 1111  // 使用改装件(ID: 1111)作为父节点
        )
        let tree = builder.buildGroupTree()
        self._marketGroupTree = State(initialValue: tree)
        
        // 尝试从 UserDefaults 加载上次访问的组ID - 使用shipTypeID区分不同飞船
        let rigGroupIDKey = "LastVisitedRigSlotGroupID_\(shipTypeID)"
        if let savedGroupID = UserDefaults.standard.object(forKey: rigGroupIDKey) as? Int {
            Logger.info("从 UserDefaults 加载到之前保存的改装件目录ID: \(savedGroupID), 飞船ID: \(shipTypeID)")
            self._lastVisitedGroupID = State(initialValue: savedGroupID)
        } else {
            Logger.info("未找到保存的改装件目录ID，飞船ID: \(shipTypeID)")
            self._lastVisitedGroupID = State(initialValue: nil)
        }
        
        // 尝试从 UserDefaults 加载上次搜索关键词 - 使用shipTypeID区分不同飞船
        let rigSearchKey = "LastRigSlotSearchKeyword_\(shipTypeID)"
        if let savedKeyword = UserDefaults.standard.string(forKey: rigSearchKey) {
            Logger.info("从 UserDefaults 加载到上次搜索关键词: \(savedKeyword), 飞船ID: \(shipTypeID)")
            self._lastSearchKeyword = State(initialValue: savedKeyword)
        } else {
            Logger.info("未找到保存的搜索关键词，飞船ID: \(shipTypeID)")
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
                    title: NSLocalizedString("Fitting_Select_Item", comment: "选择装备"),
                    marketGroupTree: marketGroupTree,
                    allowTypeIDs: Set(allowedTypeIDs),
                    existingItems: Set(),
                    onItemSelected: { item in
                        hasSelectedItem = true
                        // 仅记录选择的装备
                        Logger.info("用户选择了装备: \(item.name), ID: \(item.id), 飞船ID: \(shipTypeID)")
                        // 保存当前组ID到UserDefaults，使用shipTypeID区分不同飞船
                        if let groupID = item.marketGroupID {
                            self.lastVisitedGroupID = groupID
                            let rigGroupIDKey = "LastVisitedRigSlotGroupID_\(shipTypeID)"
                            Logger.info("保存改装件导航目录ID: \(groupID), 飞船ID: \(shipTypeID)")
                            UserDefaults.standard.set(groupID, forKey: rigGroupIDKey)
                            // 选择装备时清空搜索关键词
                            let rigSearchKey = "LastRigSlotSearchKeyword_\(shipTypeID)"
                            UserDefaults.standard.removeObject(forKey: rigSearchKey)
                            lastSearchKeyword = nil
                        }
                        
                        // 调用回调函数安装改装件
                        Logger.info("用户选择了改装件，槽位标识：\(slotFlag.rawValue)")
                        onModuleSelected?(item.id)
                        
                        dismiss()
                    },
                    onItemDeselected: { _ in
                        // 这里暂时不需要处理
                    },
                    onDismiss: { groupID, searchText in
                        // 使用shipTypeID区分不同飞船的键
                        let rigGroupIDKey = "LastVisitedRigSlotGroupID_\(shipTypeID)"
                        let rigSearchKey = "LastRigSlotSearchKeyword_\(shipTypeID)"
                        
                        // 处理搜索关键词
                        Logger.info("关闭选择器，飞船ID: \(shipTypeID)")
                        if let searchText = searchText, !searchText.isEmpty {
                            Logger.info("保存改装件搜索关键词: \"\(searchText)\", 飞船ID: \(shipTypeID)")
                            UserDefaults.standard.set(searchText, forKey: rigSearchKey)
                            lastSearchKeyword = searchText
                        }
                        
                        // 如果没有选择物品，清空保存的导航目录ID
                        if !hasSelectedItem {
                            Logger.info("用户未选择Rig，清空保存的导航目录ID，飞船ID: \(shipTypeID)")
                            UserDefaults.standard.removeObject(forKey: rigGroupIDKey)
                            self.lastVisitedGroupID = nil
                        }
                        dismiss()
                    },
                    lastVisitedGroupID: lastVisitedGroupID,
                    initialSearchText: lastSearchKeyword,
                    searchItemsByKeyword: searchItemsByKeyword
                )
                .interactiveDismissDisabled()
                .onAppear {
                    Logger.info("改装件选择器显示，飞船ID: \(shipTypeID)")
                    hasSelectedItem = false
                }
            }
        }
    }
    
    // 使用本地数据进行搜索
    private func searchItemsByKeyword(_ keyword: String) -> [DatabaseListItem] {
        Logger.info("开始本地搜索，关键词: \"\(keyword)\"")
        let startTime = Date()
        
        // 过滤符合条件的装备
        let filteredInfos = equipmentInfos.filter { info in
            // 匹配中文名、英文名或ID
            info.name.localizedCaseInsensitiveContains(keyword)
                || info.enName.localizedCaseInsensitiveContains(keyword)
                || String(info.typeId) == keyword
        }
        
        let filteredTypeIDs = filteredInfos.map { $0.typeId }
        
        // 如果没有匹配项，返回空数组
        if filteredTypeIDs.isEmpty {
            Logger.info("本地搜索没有找到匹配项")
            return []
        }
        
        // 使用过滤后的ID列表从数据库加载完整信息
        let typeIDsString = filteredTypeIDs.map { String($0) }.joined(separator: ",")
        let whereClause = "t.type_id IN (\(typeIDsString))"
        
        let results = databaseManager.loadMarketItems(whereClause: whereClause, parameters: [])
        Logger.info("本地搜索找到 \(results.count) 个匹配项，耗时: \(Date().timeIntervalSince(startTime) * 1000)ms")
        
        return results
    }
    
    // 加载改装件装备的type_id及名称信息
    private func loadEquipmentData(databaseManager: DatabaseManager, shipTypeID: Int) -> [EquipmentInfo] {
        // 获取effect_id=2663的改装件装备信息，并确保是已发布的(published=1)
        // 使用单条SQL语句一次性完成查询
        let query = """
                SELECT DISTINCT te.type_id, t.name, t.en_name, t.marketGroupID
                FROM typeEffects te
                JOIN typeAttributes ta1 ON te.type_id = ta1.type_id
                JOIN types t ON te.type_id = t.type_id
                JOIN (
                    SELECT value
                    FROM typeAttributes
                    WHERE attribute_id = 1547 AND type_id = \(shipTypeID)
                ) ship ON ta1.value = ship.value
                WHERE te.effect_id = 2663 --- 属于改装件槽位
                AND ta1.attribute_id = 1547 -- 改装件尺寸
                AND t.published = 1
            """
        
        var equipmentInfos: [EquipmentInfo] = []
        
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let enName = row["en_name"] as? String
                {
                    let marketGroupId = row["marketGroupID"] as? Int
                    
                    let info = EquipmentInfo(
                        typeId: typeId,
                        name: name,
                        enName: enName,
                        marketGroupId: marketGroupId
                    )
                    equipmentInfos.append(info)
                }
            }
            Logger.info("加载了 \(equipmentInfos.count) 个改装件装备，飞船ID: \(shipTypeID)")
        } else {
            Logger.error("加载改装件装备信息失败")
        }
        
        return equipmentInfos
    }
}

// 装备信息结构体
private struct EquipmentInfo: Identifiable {
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
