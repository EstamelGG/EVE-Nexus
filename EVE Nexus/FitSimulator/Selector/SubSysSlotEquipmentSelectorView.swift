import SwiftUI

// 子系统槽装备选择器视图
struct SubSysSlotEquipmentSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var allowedTypeIDs: [Int] = []
    @State private var equipmentInfos: [EquipmentInfo] = []
    @State private var marketGroupTree: [MarketGroupNode] = []
    @State private var lastVisitedGroupID: Int? = nil
    @State private var lastSearchKeyword: String? = nil
    @State private var hasSelectedItem: Bool = false  // 添加标记，跟踪是否已选择物品
    @Environment(\.dismiss) private var dismiss
    
    // 船只ID，用于查询匹配的子系统
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
            parentGroupId: 1112  // 使用子系统(ID: 1112)作为父节点
        )
        let tree = builder.buildGroupTree()
        self._marketGroupTree = State(initialValue: tree)
        
        // 尝试从 UserDefaults 加载上次访问的组ID - 使用shipTypeID区分不同飞船
        let subsysGroupIDKey = "LastVisitedSubSysSlotGroupID_\(shipTypeID)"
        if let savedGroupID = UserDefaults.standard.object(forKey: subsysGroupIDKey) as? Int {
            Logger.info("从 UserDefaults 加载到之前保存的子系统目录ID: \(savedGroupID), 飞船ID: \(shipTypeID)")
            self._lastVisitedGroupID = State(initialValue: savedGroupID)
        } else {
            Logger.info("未找到保存的子系统目录ID，飞船ID: \(shipTypeID)")
            self._lastVisitedGroupID = State(initialValue: nil)
        }
        
        // 尝试从 UserDefaults 加载上次搜索关键词 - 使用shipTypeID区分不同飞船
        let subsysSearchKey = "LastSubSysSlotSearchKeyword_\(shipTypeID)"
        if let savedKeyword = UserDefaults.standard.string(forKey: subsysSearchKey) {
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
                        // 标记已选择物品
                        hasSelectedItem = true
                        // 仅记录选择的装备
                        Logger.info("用户选择了装备: \(item.name), ID: \(item.id), 飞船ID: \(shipTypeID)")
                        // 保存当前组ID到UserDefaults，使用shipTypeID区分不同飞船
                        if let groupID = item.marketGroupID {
                            self.lastVisitedGroupID = groupID
                            let subsysGroupIDKey = "LastVisitedSubSysSlotGroupID_\(shipTypeID)"
                            Logger.info("保存子系统导航目录ID: \(groupID), 飞船ID: \(shipTypeID)")
                            UserDefaults.standard.set(groupID, forKey: subsysGroupIDKey)
                            // 选择装备时清空搜索关键词
                            let subsysSearchKey = "LastSubSysSlotSearchKeyword_\(shipTypeID)"
                            UserDefaults.standard.removeObject(forKey: subsysSearchKey)
                            lastSearchKeyword = nil
                        }
                        
                        // 调用回调函数安装子系统
                        Logger.info("用户选择了子系统，槽位标识：\(slotFlag.rawValue)")
                        onModuleSelected?(item.id)
                        
                        dismiss()
                    },
                    onItemDeselected: { _ in
                        // 这里暂时不需要处理
                    },
                    onDismiss: { groupID, searchText in
                        // 使用shipTypeID区分不同飞船的键
                        let subsysGroupIDKey = "LastVisitedSubSysSlotGroupID_\(shipTypeID)"
                        let subsysSearchKey = "LastSubSysSlotSearchKeyword_\(shipTypeID)"
                        
                        // 处理搜索关键词
                        Logger.info("关闭选择器，飞船ID: \(shipTypeID)")
                        if let searchText = searchText, !searchText.isEmpty {
                            Logger.info("保存子系统搜索关键词: \"\(searchText)\", 飞船ID: \(shipTypeID)")
                            UserDefaults.standard.set(searchText, forKey: subsysSearchKey)
                            lastSearchKeyword = searchText
                        }
                        
                        // 如果没有选择物品，清空保存的导航目录ID
                        if !hasSelectedItem {
                            Logger.info("用户未选择子系统，清空保存的导航目录ID，飞船ID: \(shipTypeID)")
                            UserDefaults.standard.removeObject(forKey: subsysGroupIDKey)
                            self.lastVisitedGroupID = nil
                        }
                        
                        dismiss()
                    },
                    lastVisitedGroupID: lastVisitedGroupID,
                    initialSearchText: lastSearchKeyword
                )
                .interactiveDismissDisabled()
                .onAppear {
                    Logger.info("子系统选择器显示，飞船ID: \(shipTypeID)")
                    // 重置选择状态
                    hasSelectedItem = false
                }
            }
        }
    }
    

    
    // 加载子系统装备的type_id及名称信息
    private func loadEquipmentData(databaseManager: DatabaseManager, shipTypeID: Int) -> [EquipmentInfo] {
        // 获取effect_id=3772的子系统装备信息，并确保是已发布的(published=1)
        let query = """
                SELECT DISTINCT te.type_id, t.name, t.en_name, t.marketGroupID
                FROM typeEffects te
                INNER JOIN typeAttributes ta ON te.type_id = ta.type_id
                JOIN types t ON te.type_id = t.type_id
                WHERE te.effect_id = 3772
                AND ta.attribute_id = 1380 
                AND ta.value = \(shipTypeID)
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
            Logger.info("加载了 \(equipmentInfos.count) 个子系统装备，飞船ID: \(shipTypeID)")
        } else {
            Logger.error("加载子系统装备信息失败")
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
