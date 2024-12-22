import Foundation
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
}

@globalActor actor CorporationAPIActor {
    static let shared = CorporationAPIActor()
}

@CorporationAPIActor
class CorporationAPI {
    static let shared = CorporationAPI()
    
    private init() {}
    
    // 获取军团信息
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
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
        
        Logger.info("成功获取军团信息 - 军团ID: \(corporationId)")
        return info
    }
    
    // 获取军团图标
    func fetchCorporationLogo(corporationId: Int) async throws -> UIImage {
        let urlString = "https://images.evetech.net/corporations/\(corporationId)/logo?size=64"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let cacheKey = "corporation_\(corporationId)"
        let filename = "corporation_\(corporationId).png"
        
        // 检查内存缓存
        if let cached = UserDefaults.standard.data(forKey: cacheKey),
           let image = UIImage(data: cached) {
            Logger.info("使用内存缓存的军团图标 - 军团ID: \(corporationId)")
            return image
        }
        
        // 检查文件缓存
        let fileURL = StaticResourceManager.shared.getStaticDataSetPath()
            .appendingPathComponent("CorporationIcons")
            .appendingPathComponent(filename)
        
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // 更新内存缓存
            UserDefaults.standard.set(data, forKey: cacheKey)
            Logger.info("使用文件缓存的军团图标 - 军团ID: \(corporationId)")
            return image
        }
        
        // 从网络获取
        Logger.info("从网络获取军团图标 - 军团ID: \(corporationId)")
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
        
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidImageData
        }
        
        // 更新内存缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        
        // 异步保存到文件
        Task {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL)
                Logger.info("军团图标已保存到文件 - 军团ID: \(corporationId)")
            } catch {
                Logger.error("保存军团图标到文件失败 - 军团ID: \(corporationId), error: \(error)")
            }
        }
        
        return image
    }
} 