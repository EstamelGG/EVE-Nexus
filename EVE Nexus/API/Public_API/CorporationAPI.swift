import Foundation
import Kingfisher
import SwiftUI

// 军团信息数据模型
struct CorporationInfo: Codable {
    let name: String
    let ticker: String
    let member_count: Int
    let ceo_id: Int
    let creator_id: Int
    let date_founded: String?
    let description: String
    let home_station_id: Int?
    let shares: Int?
    let tax_rate: Double
    let url: String?
    let alliance_id: Int?
    let faction_id: Int?
}

// 军团联盟历史记录数据模型
struct CorporationAllianceHistory: Codable {
    let alliance_id: Int?
    let record_id: Int
    let start_date: String
}

@globalActor actor CorporationAPIActor {
    static let shared = CorporationAPIActor()
}

@CorporationAPIActor
class CorporationAPI {
    static let shared = CorporationAPI()

    private init() {
        // 配置 Kingfisher 的全局设置
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 300 * 1024 * 1024  // 300MB
        cache.diskStorage.config.sizeLimit = 1000 * 1024 * 1024  // 1GB
        cache.diskStorage.config.expiration = .days(7)  // 7天过期

        // 配置下载器
        let downloader = ImageDownloader.default
        downloader.downloadTimeout = 15.0  // 15秒超时
    }

    // 获取军团图标URL
    private func getLogoURL(corporationId: Int, size: Int = 64) -> URL {
        return URL(
            string: "https://images.evetech.net/corporations/\(corporationId)/logo?size=\(size)")!
    }

    // 获取军团图标
    func fetchCorporationLogo(corporationId: Int, size: Int = 64, forceRefresh: Bool = false)
        async throws -> UIImage
    {
        let logoURL = getLogoURL(corporationId: corporationId, size: size)

        var options: KingfisherOptionsInfo = [
            .cacheOriginalImage,
            .diskCacheExpiration(.days(30)),  // 磁盘缓存30天
            .memoryCacheExpiration(.days(7)),  // 内存缓存7天
        ]

        // 如果需要强制刷新，添加相应的选项
        if forceRefresh {
            options.append(.forceRefresh)
            options.append(.fromMemoryCacheOrRefresh)
        }

        do {
            return try await withCheckedThrowingContinuation { continuation in
                KingfisherManager.shared.retrieveImage(with: logoURL, options: options) { result in
                    switch result {
                    case let .success(imageResult):
                        Logger.info("[CorporationAPI]成功获取军团图标 - 军团ID: \(corporationId), 大小: \(size)")
                        continuation.resume(returning: imageResult.image)
                    case let .failure(error):
                        Logger.error(
                            "[CorporationAPI]获取军团图标失败 - 军团ID: \(corporationId) - URL: \(logoURL), 错误: \(error)")
                        // 尝试获取默认图标
                        if let defaultImage = UIImage(named: "not_found") {
                            Logger.info("[CorporationAPI]使用默认图标替代 - 军团ID: \(corporationId)")
                            continuation.resume(returning: defaultImage)
                        } else {
                            continuation.resume(throwing: NetworkError.invalidImageData)
                        }
                    }
                }
            }
        } catch {
            Logger.error("[CorporationAPI]获取军团图标发生异常 - 军团ID: \(corporationId), 错误: \(error)")
            // 再次尝试获取默认图标
            if let defaultImage = UIImage(named: "not_found") {
                return defaultImage
            }
            throw error
        }
    }

    func fetchCorporationInfo(corporationId: Int, forceRefresh: Bool = false) async throws
        -> CorporationInfo
    {
        // 提前查询本地数据库中的军团名称，整个函数中复用这个结果
        let localCorporationName = getLocalCorporationName(corporationId: corporationId)
        
        // 创建缓存目录
        let cacheDirectory = getCacheDirectory()
        let cacheFilePath = cacheDirectory.appendingPathComponent("\(corporationId).json")
        
        // 检查文件缓存
        if !forceRefresh, var cachedInfo = loadCorporationInfoFromFile(filePath: cacheFilePath) {
            // 如果有本地数据库名称，使用本地名称替换缓存的名称
            if let localName = localCorporationName {
                cachedInfo = updateCorporationInfoName(info: cachedInfo, newName: localName)
                Logger.info("[CorporationAPI]使用文件缓存的军团信息，但名称使用本地数据库: \(localName) - 军团ID: \(corporationId)")
            } else {
                Logger.info("[CorporationAPI]使用文件缓存的军团信息，保持原缓存名称 - 军团ID: \(corporationId)")
            }
            
            return cachedInfo
        }

        // 从网络获取数据
        let urlString =
            "https://esi.evetech.net/corporations/\(corporationId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        var info = try JSONDecoder().decode(CorporationInfo.self, from: data)

        // 如果有本地数据库名称，使用本地名称替换网络返回的名称
        if let localName = localCorporationName {
            info = updateCorporationInfoName(info: info, newName: localName)
            Logger.info("[CorporationAPI]使用本地数据库中的军团名称: \(localName) 替换网络返回的名称")
        }

        // 保存到文件缓存
        saveCorporationInfoToFile(info: info, filePath: cacheFilePath)

        Logger.info("[CorporationAPI]成功获取军团信息 - 军团ID: \(corporationId)")
        return info
    }
    
    // MARK: - 文件缓存相关方法
    
    /// 获取缓存目录
    private func getCacheDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDirectory = documentsPath.appendingPathComponent("CorpCache")
        
        // 确保缓存目录存在
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                Logger.info("[CorporationAPI]创建军团缓存目录: \(cacheDirectory.path)")
            } catch {
                Logger.error("[CorporationAPI]创建军团缓存目录失败: \(error)")
            }
        }
        
        return cacheDirectory
    }
    
    /// 从文件加载军团信息
    private func loadCorporationInfoFromFile(filePath: URL) -> CorporationInfo? {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }
        
        do {
            // 检查文件修改时间，如果超过7天则视为过期
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let daysSinceModification = Date().timeIntervalSince(modificationDate) / (24 * 3600)
                if daysSinceModification > 7 {
                    Logger.info("[CorporationAPI]军团缓存文件已过期 - 军团ID: \(filePath.lastPathComponent)")
                    return nil
                } else {
                    let remainingDays = 7 - daysSinceModification
                    let remainingHours = remainingDays * 24
                    Logger.info("[CorporationAPI]军团缓存文件有效 - 军团ID: \(filePath.lastPathComponent), 剩余时间: \(String(format: "%.1f", remainingDays))天 (\(String(format: "%.1f", remainingHours))小时)")
                }
            }
            
            let data = try Data(contentsOf: filePath)
            let info = try JSONDecoder().decode(CorporationInfo.self, from: data)
            Logger.info("[CorporationAPI]成功从文件加载军团信息 - 文件: \(filePath.lastPathComponent)")
            return info
        } catch {
            Logger.error("[CorporationAPI]加载军团缓存文件失败: \(error) - 文件: \(filePath.lastPathComponent)")
            return nil
        }
    }
    
    /// 保存军团信息到文件
    private func saveCorporationInfoToFile(info: CorporationInfo, filePath: URL) {
        do {
            let data = try JSONEncoder().encode(info)
            try data.write(to: filePath)
            Logger.info("[CorporationAPI]成功保存军团信息到文件 - 文件: \(filePath.lastPathComponent), 大小: \(data.count) bytes")
        } catch {
            Logger.error("[CorporationAPI]保存军团信息到文件失败: \(error) - 文件: \(filePath.lastPathComponent)")
        }
    }
    
    /// 获取本地数据库中的军团名称
    private func getLocalCorporationName(corporationId: Int) -> String? {
        let npcQuery = "SELECT name FROM npcCorporations WHERE corporation_id = \(corporationId)"
        let npcResult = DatabaseManager.shared.executeQuery(npcQuery)
        
        if case let .success(rows) = npcResult,
           let row = rows.first,
           let localName = row["name"] as? String {
            return localName
        }
        
        return nil
    }
    
    /// 更新军团信息中的名称
    private func updateCorporationInfoName(info: CorporationInfo, newName: String) -> CorporationInfo {
        return CorporationInfo(
            name: newName,
            ticker: info.ticker,
            member_count: info.member_count,
            ceo_id: info.ceo_id,
            creator_id: info.creator_id,
            date_founded: info.date_founded,
            description: info.description,
            home_station_id: info.home_station_id,
            shares: info.shares,
            tax_rate: info.tax_rate,
            url: info.url,
            alliance_id: info.alliance_id,
            faction_id: info.faction_id
        )
    }
    
    // MARK: - 军团联盟历史相关方法
    
    /// 获取军团联盟历史
    func fetchAllianceHistory(corporationId: Int, forceRefresh: Bool = false) async throws -> [CorporationAllianceHistory] {
        // 创建缓存目录
        let cacheDirectory = getAllianceHistoryCacheDirectory()
        let cacheFilePath = cacheDirectory.appendingPathComponent("\(corporationId)_alliancehistory.json")
        
        // 检查文件缓存
        if !forceRefresh, let cachedHistory = loadAllianceHistoryFromFile(filePath: cacheFilePath) {
            Logger.info("[CorporationAPI]使用文件缓存的军团联盟历史 - 军团ID: \(corporationId)")
            return cachedHistory
        }

        // 从网络获取数据
        let urlString = "https://esi.evetech.net/corporations/\(corporationId)/alliancehistory/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        let history = try JSONDecoder().decode([CorporationAllianceHistory].self, from: data)

        // 按开始日期降序排序（最新的在前）
        let sortedHistory = history.sorted { $0.start_date > $1.start_date }

        // 保存到文件缓存
        saveAllianceHistoryToFile(history: sortedHistory, filePath: cacheFilePath)

        Logger.info("[CorporationAPI]成功获取军团联盟历史 - 军团ID: \(corporationId), 记录数: \(sortedHistory.count)")
        return sortedHistory
    }
    
    /// 获取联盟历史缓存目录
    private func getAllianceHistoryCacheDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDirectory = documentsPath.appendingPathComponent("CorpAllianceHistory")
        
        // 确保缓存目录存在
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                Logger.info("[CorporationAPI]创建军团联盟历史缓存目录: \(cacheDirectory.path)")
            } catch {
                Logger.error("[CorporationAPI]创建军团联盟历史缓存目录失败: \(error)")
            }
        }
        
        return cacheDirectory
    }
    
    /// 从文件加载联盟历史
    private func loadAllianceHistoryFromFile(filePath: URL) -> [CorporationAllianceHistory]? {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }
        
        do {
            // 检查文件修改时间，如果超过12小时则视为过期
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let hoursSinceModification = Date().timeIntervalSince(modificationDate) / 3600
                if hoursSinceModification > 12 {
                    Logger.info("[CorporationAPI]军团联盟历史缓存文件已过期 - 军团ID: \(filePath.lastPathComponent)")
                    return nil
                } else {
                    let remainingHours = 12 - hoursSinceModification
                    Logger.info("[CorporationAPI]军团联盟历史缓存文件有效 - 军团ID: \(filePath.lastPathComponent), 剩余时间: \(String(format: "%.1f", remainingHours))小时")
                }
            }
            
            let data = try Data(contentsOf: filePath)
            let history = try JSONDecoder().decode([CorporationAllianceHistory].self, from: data)
            Logger.info("[CorporationAPI]成功从文件加载军团联盟历史 - 文件: \(filePath.lastPathComponent)")
            return history
        } catch {
            Logger.error("[CorporationAPI]加载军团联盟历史缓存文件失败: \(error) - 文件: \(filePath.lastPathComponent)")
            return nil
        }
    }
    
    /// 保存联盟历史到文件
    private func saveAllianceHistoryToFile(history: [CorporationAllianceHistory], filePath: URL) {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: filePath)
            Logger.info("[CorporationAPI]成功保存军团联盟历史到文件 - 文件: \(filePath.lastPathComponent), 大小: \(data.count) bytes")
        } catch {
            Logger.error("[CorporationAPI]保存军团联盟历史到文件失败: \(error) - 文件: \(filePath.lastPathComponent)")
        }
    }
}
