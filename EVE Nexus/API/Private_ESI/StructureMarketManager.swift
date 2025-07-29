import Foundation

// 建筑物市场订单数据模型
struct StructureMarketOrder: Codable {
    let duration: Int
    let isBuyOrder: Bool
    let issued: String
    let locationId: Int64
    let minVolume: Int
    let orderId: Int64
    let price: Double
    let range: String
    let typeId: Int
    let volumeRemain: Int
    let volumeTotal: Int
    
    enum CodingKeys: String, CodingKey {
        case duration
        case isBuyOrder = "is_buy_order"
        case issued
        case locationId = "location_id"
        case minVolume = "min_volume"
        case orderId = "order_id"
        case price
        case range
        case typeId = "type_id"
        case volumeRemain = "volume_remain"
        case volumeTotal = "volume_total"
    }
}

// 建筑订单加载进度
public enum StructureOrdersProgress {
    case loading(currentPage: Int, totalPages: Int)
    case completed
}

// 将StructureMarketManager标记为网络管理器Actor
@NetworkManagerActor
// 建筑市场订单管理器
class StructureMarketManager {
    static let shared = StructureMarketManager()
    private let networkManager = NetworkManager.shared
    private init() {}
    
    // 缓存时间：4小时
    private let cacheTimeoutInterval: TimeInterval = 4 * 60 * 60 // 4 小时有效期
    
    // Documents目录路径
    private var documentsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    // Structure_Orders目录路径
    private var structureOrdersDirectory: URL {
        let directory = documentsDirectory.appendingPathComponent("Structure_Orders")
        
        // 确保目录存在
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
                Logger.debug("创建Structure_Orders目录: \(directory.path)")
            } catch {
                Logger.error("创建Structure_Orders目录失败: \(error)")
            }
        }
        
        return directory
    }
    
    // 获取建筑物市场订单文件路径
    private func getOrdersFilePath(structureId: Int64) -> URL {
        return structureOrdersDirectory.appendingPathComponent("structure_orders_\(structureId).json")
    }
    
    // MARK: - 公共API方法
    
    // 获取建筑市场订单（带缓存和进度回调）
    func getStructureOrders(
        structureId: Int64, 
        characterId: Int, 
        forceRefresh: Bool = false,
        progressCallback: ((StructureOrdersProgress) -> Void)? = nil
    ) async throws -> [StructureMarketOrder] {
        // 如果不是强制刷新，尝试读取有效的本地缓存
        if !forceRefresh {
            if let validOrders = await getValidLocalOrders(structureId: structureId) {
                Logger.debug("从有效本地缓存获取建筑 \(structureId) 的订单数据")
                progressCallback?(.completed)
                return validOrders
            }
        }
        
        // 从API获取新数据
        Logger.info("从API获取建筑 \(structureId) 的订单数据")
        let orders = try await fetchStructureMarketOrdersFromAPI(
            structureId: structureId,
            characterId: characterId,
            progressCallback: progressCallback
        )
        
        return orders
    }
    
    // 获取特定物品在建筑中的订单
    func getItemOrdersInStructure(
        structureId: Int64, 
        characterId: Int, 
        typeId: Int, 
        forceRefresh: Bool = false,
        progressCallback: ((StructureOrdersProgress) -> Void)? = nil
    ) async throws -> [MarketOrder] {
        let structureOrders = try await getStructureOrders(
            structureId: structureId,
            characterId: characterId,
            forceRefresh: forceRefresh,
            progressCallback: progressCallback
        )
        
        // 过滤出指定物品的订单
        let itemOrders = structureOrders.filter { $0.typeId == typeId }
        
        // 转换为MarketOrder格式
        return itemOrders.map { structureOrder in
            MarketOrder(
                duration: structureOrder.duration,
                isBuyOrder: structureOrder.isBuyOrder,
                issued: structureOrder.issued,
                locationId: structureOrder.locationId,
                minVolume: structureOrder.minVolume,
                orderId: Int(structureOrder.orderId),
                price: structureOrder.price,
                range: structureOrder.range,
                systemId: 0, // 建筑订单中没有systemId，使用0作为占位符
                typeId: structureOrder.typeId,
                volumeRemain: structureOrder.volumeRemain,
                volumeTotal: structureOrder.volumeTotal
            )
        }
    }
    
    // 批量获取多个物品在建筑中的订单（用于关注列表）
    func getBatchItemOrdersInStructure(
        structureId: Int64, 
        characterId: Int, 
        typeIds: [Int], 
        forceRefresh: Bool = false,
        progressCallback: ((StructureOrdersProgress) -> Void)? = nil
    ) async throws -> [Int: [MarketOrder]] {
        let structureOrders = try await getStructureOrders(
            structureId: structureId,
            characterId: characterId,
            forceRefresh: forceRefresh,
            progressCallback: progressCallback
        )
        
        var result: [Int: [MarketOrder]] = [:]
        
        for typeId in typeIds {
            let itemOrders = structureOrders.filter { $0.typeId == typeId }
            
            result[typeId] = itemOrders.map { structureOrder in
                MarketOrder(
                    duration: structureOrder.duration,
                    isBuyOrder: structureOrder.isBuyOrder,
                    issued: structureOrder.issued,
                    locationId: structureOrder.locationId,
                    minVolume: structureOrder.minVolume,
                    orderId: Int(structureOrder.orderId),
                    price: structureOrder.price,
                    range: structureOrder.range,
                    systemId: 0, // 建筑订单中没有systemId，使用0作为占位符
                    typeId: structureOrder.typeId,
                    volumeRemain: structureOrder.volumeRemain,
                    volumeTotal: structureOrder.volumeTotal
                )
            }
        }
        
        return result
    }
    
    // 获取订单统计信息
    func getOrdersStatistics(orders: [StructureMarketOrder]) -> (buyOrders: Int, sellOrders: Int, totalVolume: Int64) {
        let buyOrders = orders.filter { $0.isBuyOrder }.count
        let sellOrders = orders.filter { !$0.isBuyOrder }.count
        let totalVolume = orders.reduce(0) { $0 + Int64($1.volumeRemain) }
        
        return (buyOrders: buyOrders, sellOrders: sellOrders, totalVolume: totalVolume)
    }
    
    // 检查本地文件是否存在
    func hasLocalOrders(structureId: Int64) -> Bool {
        let filePath = getOrdersFilePath(structureId: structureId)
        return FileManager.default.fileExists(atPath: filePath.path)
    }
    
    // 获取本地文件的修改时间
    func getLocalOrdersModificationDate(structureId: Int64) -> Date? {
        let filePath = getOrdersFilePath(structureId: structureId)
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            return attributes[.modificationDate] as? Date
        } catch {
            return nil
        }
    }
    
    // 尝试读取有效的本地缓存订单数据
    // 返回nil表示没有有效缓存，需要联网加载
    // 返回数据表示有有效缓存，无需联网加载
    func getValidLocalOrders(structureId: Int64) async -> [StructureMarketOrder]? {
        // 检查本地文件是否存在
        guard hasLocalOrders(structureId: structureId) else {
            return nil
        }
        
        // 检查缓存是否在有效期内
        guard let modificationDate = getLocalOrdersModificationDate(structureId: structureId),
              Date().timeIntervalSince(modificationDate) < cacheTimeoutInterval else {
            return nil
        }
        
        // 尝试加载缓存数据
        do {
            let orders = try await loadOrdersFromFile(structureId: structureId)
            Logger.debug("成功读取建筑 \(structureId) 的有效本地缓存，共 \(orders.count) 条订单")
            return orders
        } catch {
            Logger.error("读取建筑 \(structureId) 的本地缓存失败: \(error)")
            return nil
        }
    }
    
    // 缓存状态枚举
    enum CacheStatus {
        case valid      // 有有效缓存
        case expired    // 有缓存但已过期
        case noData     // 无缓存数据
    }
    
    // 检查建筑订单的缓存状态（静态方法，用于UI显示）
    nonisolated static func getCacheStatus(structureId: Int64) -> CacheStatus {
        // 获取Documents目录路径
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let structureOrdersDirectory = documentsDirectory.appendingPathComponent("Structure_Orders")
        let filePath = structureOrdersDirectory.appendingPathComponent("structure_orders_\(structureId).json")
        
        // 检查本地文件是否存在
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return .noData
        }
        
        // 检查缓存是否在有效期内
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let cacheTimeout: TimeInterval = 3600 // 1小时，与 cacheTimeoutInterval 保持一致
                let isValid = Date().timeIntervalSince(modificationDate) < cacheTimeout
                return isValid ? .valid : .expired
            } else {
                return .noData
            }
        } catch {
            return .noData
        }
    }
    
    // MARK: - 私有网络请求方法
    
    // 从API获取建筑物市场订单数据（支持进度回调）
    private func fetchStructureMarketOrdersFromAPI(
        structureId: Int64, 
        characterId: Int,
        progressCallback: ((StructureOrdersProgress) -> Void)? = nil
    ) async throws -> [StructureMarketOrder] {
        Logger.info("开始获取建筑物市场订单 - 建筑ID: \(structureId), 角色ID: \(characterId)")
        
        // 构建API URL
        guard let url = URL(string: "https://esi.evetech.net/markets/structures/\(structureId)/") else {
            throw NetworkError.invalidURL
        }
        
        // 使用NetworkManager的fetchPaginatedData方法，支持进度回调
        do {
            let allOrders = try await networkManager.fetchPaginatedData(
                from: url,
                characterId: characterId,
                maxConcurrentPages: 10,
                decoder: { data in
                    try JSONDecoder().decode([StructureMarketOrder].self, from: data)
                },
                progressCallback: { currentPage, totalPages in
                    progressCallback?(.loading(currentPage: currentPage, totalPages: totalPages))
                }
            )
            
            Logger.info("成功获取建筑物市场订单 \(allOrders.count) 条")
            
            // 保存数据到文件
            try await saveOrdersToFile(orders: allOrders, structureId: structureId)
            
            progressCallback?(.completed)
            return allOrders
            
        } catch {
            Logger.error("获取建筑物市场订单失败: \(error)")
            
            // 如果网络请求失败，尝试从本地缓存加载（无论是否过期）
            if let localOrders = try? await loadOrdersFromFile(structureId: structureId) {
                Logger.info("网络请求失败，从本地文件加载建筑物市场订单 \(localOrders.count) 条")
                progressCallback?(.completed)
                return localOrders
            }
            
            throw error
        }
    }

    
    // MARK: - 私有文件操作方法
    
    // 保存订单数据到文件
    private func saveOrdersToFile(orders: [StructureMarketOrder], structureId: Int64) async throws {
        let filePath = getOrdersFilePath(structureId: structureId)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            
            let data = try encoder.encode(orders)
            try data.write(to: filePath)
            
            Logger.debug("建筑物市场订单数据已保存到: \(filePath.lastPathComponent)")
        } catch {
            Logger.error("保存建筑物市场订单数据失败: \(error)")
            throw error
        }
    }
    
    // 从文件加载订单数据
    private func loadOrdersFromFile(structureId: Int64) async throws -> [StructureMarketOrder] {
        let filePath = getOrdersFilePath(structureId: structureId)
        
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            throw NSError(domain: "StructureMarketManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "本地订单文件不存在"])
        }
        
        let data = try Data(contentsOf: filePath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let orders = try decoder.decode([StructureMarketOrder].self, from: data)
        Logger.debug("从本地文件加载建筑物市场订单 \(orders.count) 条")
        
        return orders
    }
}

// 用于根据地区ID判断是星域还是建筑
extension StructureMarketManager {
    
    // 判断是否是建筑ID（负数表示建筑）
    nonisolated static func isStructureId(_ regionId: Int) -> Bool {
        return regionId < 0
    }
    
    // 从地区ID获取建筑ID
    nonisolated static func getStructureId(from regionId: Int) -> Int64? {
        guard isStructureId(regionId) else { return nil }
        return Int64(-regionId)
    }
} 
