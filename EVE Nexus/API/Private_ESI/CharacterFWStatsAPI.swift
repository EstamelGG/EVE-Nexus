import Foundation

// MARK: - Data Models

/// 派系战争统计信息
public struct CharacterFWStats: Codable {
    public let current_rank: Int?
    public let enlisted_on: String?
    public let faction_id: Int?
    public let highest_rank: Int?
    public let kills: FWKills
    public let victory_points: FWVictoryPoints
}

/// 击杀统计
public struct FWKills: Codable {
    public let last_week: Int
    public let total: Int
    public let yesterday: Int
}

/// 胜利点数统计
public struct FWVictoryPoints: Codable {
    public let last_week: Int
    public let total: Int
    public let yesterday: Int
}

// 缓存数据结构
private struct FWStatsCacheData: Codable {
    let data: CharacterFWStats
    let timestamp: Date

    var isExpired: Bool {
        // 设置缓存有效期为24小时
        return Date().timeIntervalSince(timestamp) > 24 * 3600
    }
}

// MARK: - API Methods

public class CharacterFWStatsAPI {
    public static let shared = CharacterFWStatsAPI()
    
    private static let cacheDirectory = "fw_stats"
    private static let cacheExpiration: TimeInterval = 24 * 60 * 60  // 24小时

    private init() {}

    /// 获取角色派系战争统计数据
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - forceRefresh: 是否强制刷新
    /// - Returns: 派系战争统计数据
    public func getFWStats(characterId: Int, forceRefresh: Bool = false) async throws -> CharacterFWStats {
        // 如果不是强制刷新，尝试从缓存获取数据
        if !forceRefresh, let cachedData = try? loadFromCache(characterId: characterId) {
            Logger.info("成功从缓存获取派系战争统计数据，角色ID: \(characterId)")
            return cachedData
        }

        Logger.info("缓存未命中或强制刷新，从API获取派系战争统计数据，角色ID: \(characterId)")
        
        // 从API获取数据
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/fw/stats/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("无效的URL: \(urlString)")
            throw APIError.invalidURL
        }

        do {
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url,
                characterId: characterId
            )

            let fwStats = try JSONDecoder().decode(CharacterFWStats.self, from: data)
            Logger.info("成功从API获取派系战争统计数据，角色ID: \(characterId)")

            // 保存到缓存
            try saveToCache(characterId: characterId, fwStats: fwStats)
            return fwStats
        } catch {
            Logger.error("获取派系战争统计数据失败: \(error)")
            throw error
        }
    }

    // MARK: - Cache Management

    /// 获取缓存文件路径
    /// - Parameter characterId: 角色ID
    /// - Returns: 缓存文件路径
    private static func getCacheFilePath(characterId: Int) -> URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = documentsDirectory.appendingPathComponent(cacheDirectory)

        // 确保缓存目录存在
        do {
            try fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            Logger.error("创建缓存目录失败: \(error)")
        }

        return cacheDir.appendingPathComponent("fw_stats_\(characterId).json")
    }

    /// 从缓存加载数据
    /// - Parameter characterId: 角色ID
    /// - Returns: 缓存的派系战争统计数据，如果不存在或过期则返回nil
    private func loadFromCache(characterId: Int) throws -> CharacterFWStats? {
        let fileURL = CharacterFWStatsAPI.getCacheFilePath(characterId: characterId)

        guard let data = try? Data(contentsOf: fileURL) else {
            Logger.info("缓存文件不存在: \(fileURL)")
            return nil
        }

        do {
            let cache = try JSONDecoder().decode(FWStatsCacheData.self, from: data)

            // 检查缓存是否过期
            if cache.isExpired {
                Logger.info("缓存已过期: \(fileURL)")
                // 删除过期的缓存文件
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }

            let remainingTime = CharacterFWStatsAPI.cacheExpiration - Date().timeIntervalSince(cache.timestamp)
            Logger.info("从缓存获取派系战争统计数据: \(fileURL), 剩余有效时间: \(Int(remainingTime / 3600))小时")
            return cache.data
        } catch {
            Logger.error("解析缓存数据失败: \(error)")
            // 删除损坏的缓存文件
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    /// 保存数据到缓存
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - fwStats: 派系战争统计数据
    private func saveToCache(characterId: Int, fwStats: CharacterFWStats) throws {
        let fileURL = CharacterFWStatsAPI.getCacheFilePath(characterId: characterId)

        let cache = FWStatsCacheData(data: fwStats, timestamp: Date())
        let data = try JSONEncoder().encode(cache)

        do {
            try data.write(to: fileURL)
            Logger.info("派系战争统计数据已保存到缓存: \(fileURL)")
        } catch {
            Logger.error("保存派系战争统计数据到缓存失败: \(error)")
            throw error
        }
    }
} 
