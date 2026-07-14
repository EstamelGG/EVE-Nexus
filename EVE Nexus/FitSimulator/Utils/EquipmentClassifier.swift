import Foundation

/// 装备类别枚举
enum EquipmentCategory: String, CaseIterable {
    case ship
    case hiSlot
    case medSlot
    case lowSlot
    case rig
    case subsystem
    case drone
    case fighter
    case charge
    case implant
    case unknown
}

/// 装备分类结果
struct EquipmentClassificationResult {
    let typeId: Int
    let category: EquipmentCategory
    let details: String? // 额外信息
}

/// 装备分类器
class EquipmentClassifier {
    private let databaseManager: DatabaseManager

    // 缓存effect数据以提高性能
    private var effectCache: [Int: Set<Int>] = [:]
    private var groupCache: [Int: Int] = [:]
    private var categoryCache: [Int: Int] = [:]
    private var marketGroupCache: [Int: Int?] = [:]

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    /// 分类单个装备
    func classifyEquipment(typeId: Int) -> EquipmentClassificationResult {
        // 获取装备的effects、groupID和categoryID
        let effects = getEffects(for: typeId)
        let groupId = getGroupId(for: typeId)
        let categoryId = getCategoryId(for: typeId)

        // 按优先级进行分类判断

        // 1. 首先检查是否为舰船 (categoryID = 6)
        if categoryId == 6 {
            return EquipmentClassificationResult(
                typeId: typeId,
                category: .ship,
                details: "Category ID: 6 (Ships)"
            )
        }

        // 2. 检查槽位装备 (通过effect_id判断)
        if effects.contains(12) { // 高槽 effect_id = 12
            return EquipmentClassificationResult(
                typeId: typeId,
                category: .hiSlot,
                details: "Effect ID: 12 (High Slot)"
            )
        }

        if effects.contains(13) { // 中槽 effect_id = 13
            return EquipmentClassificationResult(
                typeId: typeId,
                category: .medSlot,
                details: "Effect ID: 13 (Medium Slot)"
            )
        }

        if effects.contains(11) { // 低槽 effect_id = 11
            return EquipmentClassificationResult(
                typeId: typeId,
                category: .lowSlot,
                details: "Effect ID: 11 (Low Slot)"
            )
        }

        // 3. 检查改装件 (effect_id = 2663)
        if effects.contains(2663) {
            return EquipmentClassificationResult(
                typeId: typeId,
                category: .rig,
                details: "Effect ID: 2663 (Rig Slot)"
            )
        }

        // 4. 检查子系统 (effect_id = 3772)
        if effects.contains(3772) {
            return EquipmentClassificationResult(
                typeId: typeId,
                category: .subsystem,
                details: "Effect ID: 3772 (Subsystem)"
            )
        }

        // 5. 检查无人机 (categoryID = 18)
        if categoryId == 18 {
            return EquipmentClassificationResult(
                typeId: typeId,
                category: .drone,
                details: "Category ID: 18 (Drone)"
            )
        }

        if categoryId == 87 {
            return EquipmentClassificationResult(
                typeId: typeId,
                category: .fighter,
                details: "Category ID: 87 (Fighter)"
            )
        }

        // 6. 检查弹药 (categoryID = 8)
        if categoryId == 8 {
            return EquipmentClassificationResult(
                typeId: typeId,
                category: .charge,
                details: "Category ID: 8 (Charge)"
            )
        }

        // 7. 如果都不匹配，返回未知
        return EquipmentClassificationResult(
            typeId: typeId,
            category: .unknown,
            details: "Category ID: \(categoryId), Group ID: \(groupId)"
        )
    }

    /// 批量分类装备
    func classifyEquipments(typeIds: [Int]) -> [Int: EquipmentClassificationResult] {
        var results: [Int: EquipmentClassificationResult] = [:]

        // 预加载所有需要的数据到缓存
        preloadCache(for: typeIds)

        // 分类每个装备
        for typeId in typeIds {
            results[typeId] = classifyEquipment(typeId: typeId)
        }

        return results
    }

    // MARK: - 私有方法

    /// 获取装备的effects
    private func getEffects(for typeId: Int) -> Set<Int> {
        if let cached = effectCache[typeId] {
            return cached
        }
        let effects = Set(SDEMemoryStore.effectIDs(forType: typeId))
        effectCache[typeId] = effects
        return effects
    }

    /// 获取装备的groupID
    private func getGroupId(for typeId: Int) -> Int {
        if let cached = groupCache[typeId] {
            return cached
        }
        let groupId = ItemInfoMap.typeInfo(for: typeId)?.groupID ?? 0
        groupCache[typeId] = groupId
        return groupId
    }

    /// 获取装备的categoryID
    private func getCategoryId(for typeId: Int) -> Int {
        if let cached = categoryCache[typeId] {
            return cached
        }
        let categoryId = ItemInfoMap.typeInfo(for: typeId)?.categoryID ?? 0
        categoryCache[typeId] = categoryId
        return categoryId
    }

    /// 预加载缓存数据
    private func preloadCache(for typeIds: [Int]) {
        guard !typeIds.isEmpty else { return }

        for typeId in typeIds {
            effectCache[typeId] = Set(SDEMemoryStore.effectIDs(forType: typeId))
        }

        for typeId in typeIds {
            guard let info = SDEMemoryStore.type(for: typeId) else { continue }
            if let groupId = info.groupID {
                groupCache[typeId] = groupId
            }
            categoryCache[typeId] = info.categoryID
            marketGroupCache[typeId] = info.marketGroupID
        }

        Logger.info("预加载了 \(typeIds.count) 个装备的分类数据")
    }
}
