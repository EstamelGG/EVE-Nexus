import Foundation

/// 定义行星P0资源信息结构体
struct P0ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var planetTypes: [Int]
    var planetNames: [String]
    var availablePlanetCount: Int
    var iconFileName: String
}

/// 定义P1资源信息结构体
struct P1ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var iconFileName: String
    var requiredP0Resources: [Int] // 需要的P0资源ID列表
    var canProduce: Bool // 是否可以使用当前可用的P0资源生产
}

/// 定义P2资源信息结构体
struct P2ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var iconFileName: String
    var requiredP1Resources: [Int] // 需要的P1资源ID列表
    var canProduce: Bool // 是否可以使用当前可用的P1资源生产
}

/// 定义P3资源信息结构体
struct P3ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var iconFileName: String
    var requiredP2Resources: [Int] // 需要的P2资源ID列表
    var canProduce: Bool // 是否可以使用当前可用的P2资源生产
}

/// 定义P4资源信息结构体
struct P4ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var iconFileName: String
    var requiredP3Resources: [Int] // 需要的P3资源ID列表
    var canProduce: Bool // 是否可以使用当前可用的P3资源生产
}

/// 定义行星资源等级枚举
enum PIResourceLevel: Int, CaseIterable {
    case p0 = 0
    case p1 = 1
    case p2 = 2
    case p3 = 3
    case p4 = 4

    var marketGroupId: Int? {
        switch self {
        case .p0: return 1333
        case .p1: return 1334
        case .p2: return 1335
        case .p3: return 1336
        case .p4: return 1337
        }
    }

    var levelName: String {
        "P\(rawValue)"
    }
}

/// 全局缓存类，用于存储查询结果
class PIResourceCache {
    static let shared = PIResourceCache()

    /// 资源基本信息缓存
    private var resourceInfoCache: [Int: (name: String, iconFileName: String, marketGroupId: Int)] =
        [:]

    /// 资源等级缓存 (P0-P4)
    private var resourceLevelCache: [Int: PIResourceLevel] = [:]

    /// P0资源缓存
    private var p0ResourceCache: [Int: Bool] = [:]

    /// 资源配方缓存
    private var schematicCache: [Int: (outputValue: Int, inputTypeIds: [Int], inputValues: [Int])] =
        [:]

    /// 星系信息缓存
    private var systemInfoCache: [Int: (security: Double, regionId: Int)] = [:]

    /// 加载状态标志，防止重复加载
    private var isPreloaded = false

    /// 私有初始化方法
    private init() {}

    /// 预加载所有资源信息（只加载一次）
    func preloadResourceInfo() {
        // 如果已经加载过，直接返回
        guard !isPreloaded else { return }

        let marketGroups: Set = [1333, 1334, 1335, 1336, 1337]
        for (typeId, info) in SDEMemoryStore.types {
            guard let marketGroupId = info.marketGroupID,
                  marketGroups.contains(marketGroupId)
            else { continue }
            resourceInfoCache[typeId] = (
                name: info.name,
                iconFileName: info.iconFilename.isEmpty ? "not_found" : info.iconFilename,
                marketGroupId: marketGroupId
            )
            if let level = determineResourceLevel(marketGroupId: marketGroupId) {
                resourceLevelCache[typeId] = level
                if level == .p0 {
                    p0ResourceCache[typeId] = true
                }
            }
        }

        // 预加载配方信息
        preloadSchematicInfo()

        // 标记为已加载
        isPreloaded = true
        Logger.info("PIResourceCache: 资源信息预加载完成")
    }

    /// 根据marketGroupId确定资源等级
    private func determineResourceLevel(marketGroupId: Int) -> PIResourceLevel? {
        let level = PlanetaryUtils.determineResourceLevel(marketGroupId: marketGroupId)
        switch level {
        case 0: return .p0
        case 1: return .p1
        case 2: return .p2
        case 3: return .p3
        case 4: return .p4
        default: return nil
        }
    }

    /// 获取资源等级
    func getResourceLevel(for resourceId: Int) -> PIResourceLevel? {
        // 首先检查资源等级缓存
        if let level = resourceLevelCache[resourceId] {
            return level
        }

        // 如果缓存中没有，则说明该物品不是行星资源
        return nil
    }

    /// 获取资源信息
    func getResourceInfo(for resourceId: Int) -> (
        name: String, iconFileName: String, marketGroupId: Int
    )? {
        return resourceInfoCache[resourceId]
    }

    /// 获取所有缓存的资源信息
    func getAllResourceInfo() -> [(Int, (name: String, iconFileName: String, marketGroupId: Int))] {
        return Array(resourceInfoCache)
    }

    /// 获取资源配方
    func getSchematic(for resourceId: Int) -> (
        outputValue: Int, inputTypeIds: [Int], inputValues: [Int]
    )? {
        return schematicCache[resourceId]
    }

    /// 获取星系信息
    func getSystemInfo(for systemId: Int) -> (security: Double, regionId: Int)? {
        if let cachedInfo = systemInfoCache[systemId] {
            return cachedInfo
        }

        let query = """
            SELECT system_security, region_id
            FROM universe
            WHERE solarsystem_id = ?
        """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query, parameters: [systemId]
        ),
            let row = rows.first,
            let security = row["system_security"] as? Double,
            let regionId = row["region_id"] as? Int
        {
            let info = (security: security, regionId: regionId)
            systemInfoCache[systemId] = info
            return info
        }

        return nil
    }

    /// 预加载配方信息（统一将数据库结果转为 Int 类型）
    private func preloadSchematicInfo() {
        let query = """
            SELECT output_typeid, output_value, input_typeid, input_value
            FROM planetSchematics
        """

        guard case let .success(rows) = DatabaseManager.shared.executeQuery(query) else {
            Logger.error("PIResourceCache: 查询 planetSchematics 表失败")
            return
        }

        var tempCache: [Int: (outputValue: Int, inputTypeIds: [Int], inputValues: [Int])] = [:]

        for row in rows {
            // 1. 获取 output_typeid 和 output_value（必须是 Int）
            guard let outputTypeId = row["output_typeid"] as? Int,
                  let outputValue = row["output_value"] as? Int
            else {
                continue
            }

            // 2. 将 input_typeid 统一转为 [Int]（处理 String/Int/NSNumber 类型）
            let inputTypeIds: [Int] = {
                if let str = row["input_typeid"] as? String {
                    // 字符串类型：用逗号分隔
                    return str.components(separatedBy: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } else if let int = row["input_typeid"] as? Int {
                    // Int 类型：单个值
                    return [int]
                } else if let number = row["input_typeid"] as? NSNumber {
                    // NSNumber 类型：单个值
                    return [number.intValue]
                }
                return []
            }()

            // 3. 将 input_value 统一转为 [Int]（处理 String/Int/NSNumber 类型）
            let inputValues: [Int] = {
                if let str = row["input_value"] as? String {
                    // 字符串类型：用逗号分隔
                    return str.components(separatedBy: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } else if let int = row["input_value"] as? Int {
                    // Int 类型：单个值
                    return [int]
                } else if let number = row["input_value"] as? NSNumber {
                    // NSNumber 类型：单个值
                    return [number.intValue]
                }
                return []
            }()

            // 4. 验证数据有效性
            guard inputTypeIds.count == inputValues.count, !inputTypeIds.isEmpty else {
                continue
            }

            // 5. 存储到缓存（key 是 Int 类型的 outputTypeId）
            tempCache[outputTypeId] = (
                outputValue: outputValue,
                inputTypeIds: inputTypeIds,
                inputValues: inputValues
            )
        }

        // 6. 一次性更新缓存（在后台线程完成，后续只读）
        schematicCache = tempCache
        Logger.info("PIResourceCache: 配方缓存加载完成，共 \(tempCache.count) 条记录")
    }
}
