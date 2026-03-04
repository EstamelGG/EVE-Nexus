import SwiftUI

/// 共享的技能数据管理器
@MainActor
class SharedSkillsManager: ObservableObject {
    static let shared = SharedSkillsManager()

    @Published var characterSkills: [Int: Int] = [:]
    @Published var isLoading = false

    // 跟踪当前加载的角色ID，用于检测角色切换
    private var loadedCharacterId: Int = 0

    private var currentCharacterId: Int {
        UserDefaults.standard.integer(forKey: "currentCharacterId")
    }

    private init() {}

    /// 预加载技能数据
    func preloadSkills() {
        guard currentCharacterId != 0 else {
            characterSkills = [:]
            loadedCharacterId = 0
            isLoading = false
            return
        }

        // 检测角色切换：如果当前角色ID与已加载的不同，清空数据重新加载
        if loadedCharacterId != currentCharacterId {
            Logger.debug("检测到角色切换: \(loadedCharacterId) -> \(currentCharacterId)")
            characterSkills = [:]
            loadedCharacterId = 0
            isLoading = false
        }

        // 如果已经有当前角色的数据且不在加载中，直接返回
        if !characterSkills.isEmpty, !isLoading, loadedCharacterId == currentCharacterId {
            return
        }

        // 防止重复加载
        if isLoading {
            return
        }

        isLoading = true
        Logger.debug("SharedSkillsManager开始预加载技能数据 - 角色ID: \(currentCharacterId)")

        Task {
            do {
                let (skillsResponse, queue) = try await CharacterSkillsAPI.shared.fetchCharacterSkillsAndQueue(
                    characterId: currentCharacterId,
                    forceRefresh: false
                )

                // 从技能映射中提取技能ID到等级的字典，并合并队列中已完成的部分
                let baseSkills = Dictionary(uniqueKeysWithValues: skillsResponse.skillsMap.map { ($0.key, $0.value.trained_skill_level) })
                let skillsDict = CharacterSkillsUtils.mergeCompletedQueueIntoSkills(
                    baseSkills: baseSkills,
                    queue: queue
                )

                await MainActor.run {
                    self.characterSkills = skillsDict
                    self.loadedCharacterId = currentCharacterId
                    self.isLoading = false
                    Logger.debug(
                        "SharedSkillsManager技能数据预加载完成 - 角色ID: \(currentCharacterId), 技能数量: \(skillsDict.count)"
                    )
                }
            } catch {
                Logger.error("SharedSkillsManager预加载技能数据失败: \(error)")
                await MainActor.run {
                    self.characterSkills = [:]
                    self.loadedCharacterId = 0
                    self.isLoading = false
                }
            }
        }
    }

    /// 获取技能等级
    /// - Returns: nil表示正在加载，-1表示角色未拥有该技能，-2表示无角色登录
    func getSkillLevel(for skillID: Int) -> Int? {
        if currentCharacterId == 0 {
            return -2 // 特殊值表示无角色登录
        }

        if isLoading {
            return nil // 正在加载
        }

        return characterSkills[skillID] ?? -1 // 角色未拥有该技能
    }

    /// 清除技能数据（角色切换或登出时调用）
    func clearSkillData() {
        Logger.debug("SharedSkillsManager清除技能数据")
        characterSkills = [:]
        loadedCharacterId = 0
        isLoading = false
    }
}

enum ItemInfoMap {
    // 缓存结构，存储物品ID对应的分类信息
    private static var categoryCache: [Int: (categoryID: Int, groupID: Int?)] = [:]

    /// 初始化缓存，加载所有物品的分类信息
    static func initializeCache(databaseManager: DatabaseManager) {
        let query = """
        SELECT type_id, categoryID, groupID
        FROM types
        """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let categoryID = row["categoryID"] as? Int
                {
                    let groupID = row["groupID"] as? Int
                    categoryCache[typeID] = (categoryID: categoryID, groupID: groupID)
                }
            }
        }
    }

    /// 根据物品ID返回对应的详情视图
    /// - Parameters:
    ///   - itemID: 物品ID
    ///   - databaseManager: 数据库管理器
    ///   - modifiedAttributes: 可选的修改后属性值
    /// - Returns: 对应的详情视图类型
    static func getItemInfoView(
        itemID: Int,
        databaseManager: DatabaseManager,
        modifiedAttributes: [Int: Double]? = nil
    ) -> AnyView {
        // 从缓存中获取分类信息
        guard let itemCategory = categoryCache[itemID] else {
            Logger.error("ItemInfoMap - 无法获取物品分类信息，itemID: \(itemID)")
            return AnyView(Text(NSLocalizedString("Item_load_error", comment: "")))
        }

        let categoryID = itemCategory.categoryID
        let groupID = itemCategory.groupID

//        Logger.debug(
//            "ItemInfoMap - 选择视图类型，itemID: \(itemID), categoryID: \(String(describing: categoryID)), groupID: \(String(describing: groupID))"
//        )

        // 首先检查特定的categoryID和groupID组合
        if categoryID == 17 && groupID == 1964 { // 突变质体
            return AnyView(ShowMutationInfo(itemID: itemID, databaseManager: databaseManager))
        }

        // 然后根据分类选择合适的视图类型
        switch categoryID {
        case 9, 34: // 蓝图和冬眠者蓝图
            return AnyView(ShowBluePrintInfo(blueprintID: itemID, databaseManager: databaseManager))

        case 42, 43: // 行星开发相关
            return AnyView(ShowPlanetaryInfo(itemID: itemID, databaseManager: databaseManager))

        default: // 普通物品
            return AnyView(
                ShowItemInfo(
                    databaseManager: databaseManager, itemID: itemID,
                    modifiedAttributes: modifiedAttributes
                ))
        }
    }
}
