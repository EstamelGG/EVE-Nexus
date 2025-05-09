//
//  Fw.swift
//  EVE Nexus
//
//  Created by GG on 2025/5/7.
//

import Foundation

// MARK: - 数据模型

struct FWSystem: Codable {
    let contested: String
    let occupier_faction_id: Int
    let owner_faction_id: Int
    let solar_system_id: Int
    let victory_points: Int
    let victory_points_threshold: Int
}

struct FWWar: Codable {
    let against_id: Int
    let faction_id: Int
}

// 叛乱相关数据模型
struct InsurgencySystem: Codable {
    let id: Int
    let name: String
    let occupierFactionId: Int?
    let ownerFactionId: Int
    let security: Double
    let securityBand: String
}

struct originSolarSystem: Codable {
    let id: Int
    let name: String
    let security: Double
    let securityBand: String
}

struct Insurgency: Codable {
    let corruptionDate: String?
    let corruptionPercentage: Double
    let corruptionState: Int
    let suppressionDate: String?
    let suppressionPercentage: Double
    let suppressionState: Int
    let solarSystem: InsurgencySystem
}

struct InsurgencyCampaign: Codable {
    let campaignId: Int
    let pirateFaction: pirateFaction
    let corruptionThresHold: Int
    let endDateTime: String?
    let startDateTime: String
    let state: String
    let suppressionThresHold: Int
    let originSolarSystem: originSolarSystem
    let insurgencies: [Insurgency]
}

struct pirateFaction: Codable {
    let id: Int
}

// 星系邻居数据模型
typealias SystemNeighbours = [String: [Int]]

// MARK: - 错误类型

enum FWAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)
    case rateLimitExceeded
    case neighboursDataError(Error)
    case cacheError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的URL"
        case let .networkError(error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case let .decodingError(error):
            return "数据解码错误: \(error.localizedDescription)"
        case let .httpError(code):
            return "HTTP错误: \(code)"
        case .rateLimitExceeded:
            return "超出请求限制"
        case let .neighboursDataError(error):
            return "星系邻居数据错误: \(error.localizedDescription)"
        case let .cacheError(error):
            return "缓存错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - FW API

@globalActor actor FWAPIActor {
    static let shared = FWAPIActor()
}

@FWAPIActor
class FWAPI {
    static let shared = FWAPI()
    private let cacheDuration: TimeInterval = 15 * 60  // 15分钟缓存
    private let insurgencyCacheDuration: TimeInterval = 5 * 60  // 5分钟缓存
    private var systemNeighbours: SystemNeighbours = [:]
    
    private init() {
        loadNeighboursData()
    }

    // MARK: - 私有方法

    private func loadNeighboursData() {
        guard let url = Bundle.main.url(forResource: "neighbours_data", withExtension: "json") else {
            Logger.error("找不到neighbours_data.json文件")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            systemNeighbours = try decoder.decode(SystemNeighbours.self, from: data)
            Logger.info("成功加载星系邻居数据，共\(systemNeighbours.count)个星系")
        } catch {
            Logger.error("加载星系邻居数据失败: \(error)")
        }
    }

    // 获取所有星系邻居数据
    func getSystemNeighbours() -> SystemNeighbours {
        return systemNeighbours
    }

    // 缓存相关结构体
    struct CachedData<T: Codable>: Codable {
        let data: T
        let timestamp: Date
    }

    private func getCacheKey(for type: String) -> String {
        return "fw_\(type)_data"
    }

    private func loadFromCache<T: Codable>(_ type: String) -> T? {
        let cacheKey = getCacheKey(for: type)
        guard let cachedData = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CachedData<T>.self, from: cachedData),
              cached.timestamp.addingTimeInterval(cacheDuration) > Date()
        else {
            return nil
        }

        let remainingTime = Int((cached.timestamp.addingTimeInterval(cacheDuration).timeIntervalSince(Date())) / 60)
        Logger.info("使用缓存的FW \(type)数据，剩余时间: \(remainingTime)分钟")
        return cached.data
    }

    private func saveToCache<T: Codable>(_ data: T, type: String) {
        let cacheKey = getCacheKey(for: type)
        let cachedData = CachedData(data: data, timestamp: Date())
        
        do {
            let encodedData = try JSONEncoder().encode(cachedData)
            UserDefaults.standard.set(encodedData, forKey: cacheKey)
            Logger.info("FW \(type)数据已缓存，数据大小: \(encodedData.count) bytes")
        } catch {
            Logger.error("保存FW \(type)缓存失败: \(error)")
        }
    }

    // 叛乱数据缓存相关方法
    private func getInsurgencyCachePath() -> URL? {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fwDirectory = documentsPath.appendingPathComponent("fw", isDirectory: true)
        
        // 如果目录不存在，创建它
        if !fileManager.fileExists(atPath: fwDirectory.path) {
            do {
                try fileManager.createDirectory(at: fwDirectory, withIntermediateDirectories: true)
            } catch {
                Logger.error("创建fw缓存目录失败: \(error)")
                return nil
            }
        }
        
        return fwDirectory.appendingPathComponent("insurgency.json")
    }

    private func loadInsurgencyFromCache() -> [InsurgencyCampaign]? {
        guard let cachePath = getInsurgencyCachePath() else { return nil }
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: cachePath.path) else {
            Logger.warning("缓存文件不存在，将在线加载。")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: cachePath)
            let cached = try JSONDecoder().decode(CachedData<[InsurgencyCampaign]>.self, from: data)
            
            if cached.timestamp.addingTimeInterval(insurgencyCacheDuration) > Date() {
                let remainingTime = Int((cached.timestamp.addingTimeInterval(insurgencyCacheDuration).timeIntervalSince(Date())) / 60)
                Logger.info("使用缓存的叛乱数据，剩余时间: \(remainingTime)分钟")
                return cached.data
            }
        } catch {
            Logger.error("读取叛乱缓存失败: \(error)")
        }
        
        return nil
    }

    private func saveInsurgencyToCache(_ campaigns: [InsurgencyCampaign]) {
        guard let cachePath = getInsurgencyCachePath() else { return }
        
        do {
            let cachedData = CachedData(data: campaigns, timestamp: Date())
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cachePath)
            Logger.info("叛乱数据已缓存到文件，数据大小: \(encodedData.count) bytes")
        } catch {
            Logger.error("保存叛乱缓存失败: \(error)")
        }
    }

    // MARK: - 公共方法

    /// 获取叛乱数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 叛乱战役数组
    func fetchInsurgencyData(forceRefresh: Bool = false) async throws -> [InsurgencyCampaign] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadInsurgencyFromCache() {
                return cached
            }
            // 缓存加载失败，记录日志并继续执行网络请求
            Logger.info("缓存加载失败，将进行网络更新")
        }

        Logger.info("从网络获取叛乱数据，强制刷新: \(forceRefresh)")

        // 构建URL
        let urlString = "https://www.eveonline.com/api/warzone/insurgency"
        guard let url = URL(string: urlString) else {
            throw FWAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let campaigns = try JSONDecoder().decode([InsurgencyCampaign].self, from: data)

        // 保存到缓存
        saveInsurgencyToCache(campaigns)

        Logger.info("成功获取叛乱数据，共\(campaigns.count)个战役")

        return campaigns
    }

    /// 同时获取FW星系数据和战争数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 包含星系数据和战争数据的元组
    func fetchFWData(forceRefresh: Bool = false) async throws -> (systems: [FWSystem], wars: [FWWar]) {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cachedSystems: [FWSystem] = loadFromCache("systems"),
               let cachedWars: [FWWar] = loadFromCache("wars") {
                Logger.info("使用缓存的FW数据 - 星系: \(cachedSystems.count)个, 战争: \(cachedWars.count)场")
                return (cachedSystems, cachedWars)
            }
        }

        Logger.info("从网络获取FW数据，强制刷新: \(forceRefresh)")

        // 同时获取两种数据
        async let systemsTask = fetchFWSystems(forceRefresh: true)
        async let warsTask = fetchFWWars(forceRefresh: true)

        // 等待两个任务完成
        let (systems, wars) = try await (systemsTask, warsTask)

        Logger.info("成功获取FW数据 - 星系: \(systems.count)个, 战争: \(wars.count)场")

        return (systems, wars)
    }

    func fetchFWSystems(forceRefresh: Bool = false) async throws -> [FWSystem] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached: [FWSystem] = loadFromCache("systems") {
                Logger.info("使用缓存的FW星系数据，共\(cached.count)个星系")
                return cached
            }
        }

        Logger.info("从网络获取FW星系数据，强制刷新: \(forceRefresh)")

        // 构建URL
        let urlString = "https://esi.evetech.net/latest/fw/systems/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw FWAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let systems = try JSONDecoder().decode([FWSystem].self, from: data)

        // 保存到缓存
        saveToCache(systems, type: "systems")

        Logger.info("成功获取FW星系数据，共\(systems.count)个星系")

        return systems
    }

    func fetchFWWars(forceRefresh: Bool = false) async throws -> [FWWar] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached: [FWWar] = loadFromCache("wars") {
                Logger.info("使用缓存的FW战争数据，共\(cached.count)场战争")
                return cached
            }
        }

        Logger.info("从网络获取FW战争数据，强制刷新: \(forceRefresh)")

        // 构建URL
        let urlString = "https://esi.evetech.net/latest/fw/wars/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw FWAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let wars = try JSONDecoder().decode([FWWar].self, from: data)

        // 保存到缓存
        saveToCache(wars, type: "wars")

        Logger.info("成功获取FW战争数据，共\(wars.count)场战争")

        return wars
    }
}

