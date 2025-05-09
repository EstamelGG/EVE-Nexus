import Foundation

// 定义行星P0资源信息结构体
struct P0ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var planetTypes: [Int]
    var planetNames: [String]
    var availablePlanetCount: Int
    var iconFileName: String
}

// 定义P1资源信息结构体
struct P1ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var iconFileName: String
    var requiredP0Resources: [Int]  // 需要的P0资源ID列表
    var canProduce: Bool  // 是否可以使用当前可用的P0资源生产
}

// 定义P2资源信息结构体
struct P2ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var iconFileName: String
    var requiredP1Resources: [Int]  // 需要的P1资源ID列表
    var canProduce: Bool  // 是否可以使用当前可用的P1资源生产
}

// 定义P3资源信息结构体
struct P3ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var iconFileName: String
    var requiredP2Resources: [Int]  // 需要的P2资源ID列表
    var canProduce: Bool  // 是否可以使用当前可用的P2资源生产
}

// 定义P4资源信息结构体
struct P4ResourceInfo: Identifiable {
    var id = UUID()
    var resourceId: Int
    var resourceName: String
    var iconFileName: String
    var requiredP3Resources: [Int]  // 需要的P3资源ID列表
    var canProduce: Bool  // 是否可以使用当前可用的P3资源生产
}

// 定义行星资源等级枚举
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
        "P\(self.rawValue)"
    }
}

// 全局缓存类，用于存储查询结果
class PIResourceCache {
    static let shared = PIResourceCache()

    // 资源基本信息缓存
    private var resourceInfoCache: [Int: (name: String, iconFileName: String, marketGroupId: Int)] =
        [:]

    // 资源等级缓存 (P0-P4)
    private var resourceLevelCache: [Int: PIResourceLevel] = [:]

    // P0资源缓存
    private var p0ResourceCache: [Int: Bool] = [:]

    // 资源配方缓存
    private var schematicCache: [Int: (outputValue: Int, inputTypeIds: [Int], inputValues: [Int])] =
        [:]

    // 星系信息缓存
    private var systemInfoCache: [Int: (name: String, security: Double, region: String)] = [:]

    // 私有初始化方法
    private init() {}

    // 预加载所有资源信息
    func preloadResourceInfo() {
        DispatchQueue.global(qos: .userInitiated).async {
            // 预加载所有P0-P4资源信息
            let query = """
                    SELECT type_id, name, icon_filename, marketGroupID
                    FROM types
                    WHERE marketGroupID IN (1333, 1334, 1335, 1336, 1337)
                """

            if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                        let name = row["name"] as? String,
                        let iconFileName = row["icon_filename"] as? String,
                        let marketGroupId = row["marketGroupID"] as? Int
                    {

                        // 缓存资源基本信息
                        self.resourceInfoCache[typeId] = (
                            name: name,
                            iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName,
                            marketGroupId: marketGroupId
                        )

                        // 缓存资源等级
                        if let level = self.determineResourceLevel(marketGroupId: marketGroupId) {
                            self.resourceLevelCache[typeId] = level

                            // 同时更新P0资源缓存
                            if level == .p0 {
                                self.p0ResourceCache[typeId] = true
                            }
                        }
                    }
                }
            }

            // 预加载配方信息
            self.preloadSchematicInfo()
        }
    }

    // 根据marketGroupId确定资源等级
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

    // 获取资源等级
    func getResourceLevel(for resourceId: Int) -> PIResourceLevel? {
        // 首先检查资源等级缓存
        if let level = resourceLevelCache[resourceId] {
            return level
        }

        // 如果缓存中没有，则说明该物品不是行星资源
        return nil
    }

    // 获取资源信息
    func getResourceInfo(for resourceId: Int) -> (
        name: String, iconFileName: String, marketGroupId: Int
    )? {
        return resourceInfoCache[resourceId]
    }

    // 获取所有缓存的资源信息
    func getAllResourceInfo() -> [(Int, (name: String, iconFileName: String, marketGroupId: Int))] {
        return Array(resourceInfoCache)
    }

    // 获取资源配方
    func getSchematic(for resourceId: Int) -> (
        outputValue: Int, inputTypeIds: [Int], inputValues: [Int]
    )? {
        return schematicCache[resourceId]
    }

    // 获取星系信息
    func getSystemInfo(for systemId: Int) -> (name: String, security: Double, region: String)? {
        if let cachedInfo = systemInfoCache[systemId] {
            return cachedInfo
        }

        let query = """
                SELECT s.solarSystemName, u.system_security, r.regionName
                FROM solarsystems s
                JOIN universe u ON s.solarSystemID = u.solarsystem_id
                JOIN regions r ON r.regionID = u.region_id
                WHERE s.solarSystemID = ?
            """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query, parameters: [systemId]),
            let row = rows.first,
            let name = row["solarSystemName"] as? String,
            let security = row["system_security"] as? Double,
            let region = row["regionName"] as? String
        {
            let info = (name: name, security: security, region: region)
            systemInfoCache[systemId] = info
            return info
        }

        return nil
    }

    // 预加载配方信息
    private func preloadSchematicInfo() {
        let query = """
                SELECT output_typeid, output_value, input_typeid, input_value
                FROM planetSchematics
            """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
            for row in rows {
                if let outputTypeId = row["output_typeid"] as? Int,
                    let outputValue = row["output_value"] as? Int,
                    let inputTypeIdStr = row["input_typeid"] as? String,
                    let inputValueStr = row["input_value"] as? String
                {

                    // 解析输入资源ID和值
                    let inputTypeIds = inputTypeIdStr.components(separatedBy: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespaces))
                    }
                    let inputValues = inputValueStr.components(separatedBy: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespaces))
                    }

                    self.schematicCache[outputTypeId] = (
                        outputValue: outputValue,
                        inputTypeIds: inputTypeIds,
                        inputValues: inputValues
                    )
                }
            }
        }
    }
}
