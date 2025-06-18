import Foundation

/// 效果类别枚举
enum EffectCategory: Int {
    case passive = 0  // dgmEffPassive
    case active = 1  // dgmEffActivation
    case target = 2  // dgmEffTarget
    case area = 3  // dgmEffArea
    case online = 4  // dgmEffOnline
    case overload = 5  // dgmEffOverload
    case dungeon = 6  // dgmEffDungeon
    case system = 7  // dgmEffSystem

    /// 获取该效果类别对应的最大状态值
    var maxStatus: Int {
        // 离线 在线 启动 超载 0 1 2 3
        switch self {
        case .passive: return 1  // 离线
        case .active: return 2  // 在线
        case .target: return 1  // 启动
        case .area: return 1  // 启动
        case .online: return 1  // 在线
        case .overload: return 3  // 超载
        case .dungeon: return 1  // 在线
        case .system: return 1  // 在线
        }
    }

    /// 判断该效果类别是否应该被忽略（不影响状态值）
    var shouldIgnore: Bool {
        switch self {
        case .target, .area, .dungeon, .system:
            return true
        default:
            return false
        }
    }
}

/// 根据模块效果获取最大可用状态
/// - Parameters:
///   - itemEffects: 模块的效果ID数组
///   - itemAttributes: 模块的属性键值对字典
///   - databaseManager: 数据库管理器
/// - Returns: 最大可用状态值
func getMaxStatus(itemEffects: [Int], itemAttributes: [Int: Double], databaseManager: DatabaseManager)
    -> Int
{
    // 0 离线
    // 1 在线
    // 2 启动
    // 3 超载

    // 如果没有效果和属性，默认为在线状态
    guard !itemEffects.isEmpty || !itemAttributes.isEmpty else {
        Logger.info("默认最大状态为 在线")
        return 1
    }

    // 构建SQL查询，获取所有效果的类别
    let placeholders = Array(repeating: "?", count: itemEffects.count).joined(separator: ",")
    let query = """
            SELECT effect_id, effect_category
            FROM dogmaEffects
            WHERE effect_id IN (\(placeholders))
        """

    // 执行查询
    let result = databaseManager.executeQuery(query, parameters: itemEffects)

    // 处理查询结果
    if case let .success(rows) = result {
        var maxStatus = 0

        for row in rows {
            if let categoryRaw = row["effect_category"] as? Int
            {
                if let category = EffectCategory(rawValue: categoryRaw) {
                    // 忽略特定的效果类别
                    if !category.shouldIgnore {
                        maxStatus = max(maxStatus, category.maxStatus)
                    }
                }
            }
        }

        // 检查是否有特殊属性ID 6（电容消耗）
        // 如是，其最大状态最少为启动，如有超载效果，则最大状态为超载
        if itemAttributes.keys.contains(6) {
            return max(2, maxStatus)
        }

        return maxStatus
    }

    return 0
}

/// 获取模块的可用状态列表
/// - Parameters:
///   - itemEffects: 模块的效果ID数组
///   - itemAttributes: 模块的属性ID数组
///   - databaseManager: 数据库管理器
/// - Returns: 可用状态值的数组
func getAvailableStatuses(
    itemEffects: [Int], itemAttributes: [Int: Double], databaseManager: DatabaseManager
) -> [Int] {
    let maxStatus = getMaxStatus(
        itemEffects: itemEffects, itemAttributes: itemAttributes, databaseManager: databaseManager)

    // 根据最大状态值生成可用状态列表
    switch maxStatus {
    case 3:  // 有超载效果，包含所有状态
        return [0, 1, 2, 3]
    case 2:  // 有启动效果，包含离线、在线和启动状态
        return [0, 1, 2]
    case 1:  // 有在线效果，包含离线和在线状态
        return [0, 1]
    default:  // 只有离线状态
        return [0]
    }
}
