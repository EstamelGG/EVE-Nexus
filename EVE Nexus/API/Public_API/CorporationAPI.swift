import Foundation
import SwiftUI
import Kingfisher

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
        cache.memoryStorage.config.totalCostLimit = 300 * 1024 * 1024 // 300MB
        cache.diskStorage.config.sizeLimit = 1000 * 1024 * 1024 // 1GB
        cache.diskStorage.config.expiration = .days(7) // 7天过期
        
        // 配置下载器
        let downloader = ImageDownloader.default
        downloader.downloadTimeout = 15.0 // 15秒超时
    }
    
    // 获取军团图标URL
    private func getLogoURL(corporationId: Int, size: Int = 64) -> URL {
        return URL(string: "https://images.evetech.net/corporations/\(corporationId)/logo?size=\(size)")!
    }
    
    // 获取军团图标
    func fetchCorporationLogo(corporationId: Int, size: Int = 64, forceRefresh: Bool = false) async throws -> UIImage {
        let logoURL = getLogoURL(corporationId: corporationId, size: size)
        
        var options: KingfisherOptionsInfo = await [
            .cacheOriginalImage,
            .backgroundDecode,
            .scaleFactor(UIScreen.main.scale),
            .transition(.fade(0.2))
        ]
        
        // 如果需要强制刷新，添加相应的选项
        if forceRefresh {
            options.append(.forceRefresh)
            options.append(.fromMemoryCacheOrRefresh)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: logoURL, options: options) { result in
                switch result {
                case .success(let imageResult):
                    Logger.info("成功获取军团图标 - 军团ID: \(corporationId), 大小: \(size)")
                    continuation.resume(returning: imageResult.image)
                case .failure(let error):
                    Logger.error("获取军团图标失败 - 军团ID: \(corporationId) - URL: \(logoURL), 错误: \(error)")
                    continuation.resume(throwing: NetworkError.invalidImageData)
                }
            }
        }
    }
    
    func fetchCorporationInfo(corporationId: Int, forceRefresh: Bool = false) async throws -> CorporationInfo {
        let cacheKey = "corporation_info_\(corporationId)"
        let cacheTimeKey = "corporation_info_\(corporationId)_time"
        
        // 检查缓存
        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 7 * 24 * 3600 {
            do {
                let info = try JSONDecoder().decode(CorporationInfo.self, from: cachedData)
                Logger.info("使用缓存的军团信息 - 军团ID: \(corporationId)")
                return info
            } catch {
                Logger.error("解析缓存的军团信息失败: \(error)")
            }
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/corporations/\(corporationId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchData(from: url)
        let info = try JSONDecoder().decode(CorporationInfo.self, from: data)
        
        // 更新缓存
        Logger.info("成功缓存军团信息, key: \(cacheKey), 数据大小: \(data.count) bytes")
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
        
        Logger.info("成功获取军团信息 - 军团ID: \(corporationId)")
        return info
    }
} 
