import Foundation
import SwiftUI

// 联盟信息数据模型
struct AllianceInfo: Codable {
    let name: String
    let ticker: String
    let creator_corporation_id: Int
    let creator_id: Int
    let date_founded: String
    let executor_corporation_id: Int
}

@globalActor actor AllianceAPIActor {
    static let shared = AllianceAPIActor()
}

@AllianceAPIActor
class AllianceAPI {
    static let shared = AllianceAPI()
    
    private init() {}
    
    // 获取联盟信息
    func fetchAllianceInfo(allianceId: Int, forceRefresh: Bool = false) async throws -> AllianceInfo {
        let cacheKey = "alliance_info_\(allianceId)"
        let cacheTimeKey = "alliance_info_\(allianceId)_time"
        
        // 检查缓存
        if !forceRefresh,
           let cachedData = UserDefaults.standard.data(forKey: cacheKey),
           let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
           Date().timeIntervalSince(lastUpdateTime) < 7 * 24 * 3600 {
            do {
                let info = try JSONDecoder().decode(AllianceInfo.self, from: cachedData)
                Logger.info("使用缓存的联盟信息 - 联盟ID: \(allianceId)")
                return info
            } catch {
                Logger.error("解析缓存的联盟信息失败: \(error)")
            }
        }
        
        // 从网络获取数据
        let urlString = "https://esi.evetech.net/latest/alliances/\(allianceId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchData(from: url)
        let info = try JSONDecoder().decode(AllianceInfo.self, from: data)
        
        // 更新缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)
        
        Logger.info("成功获取联盟信息 - 联盟ID: \(allianceId)")
        return info
    }
    
    // 获取联盟图标
    func fetchAllianceLogo(allianceID: Int) async throws -> UIImage {
        let urlString = "https://images.evetech.net/alliances/\(allianceID)/logo?size=64"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let cacheKey = "alliance_\(allianceID)"
        let filename = "alliance_\(allianceID).png"
        
        // 检查内存缓存
        if let cached = UserDefaults.standard.data(forKey: cacheKey),
           let image = UIImage(data: cached) {
            Logger.info("使用内存缓存的联盟图标 - 联盟ID: \(allianceID)")
            return image
        }
        
        // 检查文件缓存
        let fileURL = StaticResourceManager.shared.getStaticDataSetPath()
            .appendingPathComponent("AllianceIcons")
            .appendingPathComponent(filename)
        
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // 更新内存缓存
            UserDefaults.standard.set(data, forKey: cacheKey)
            Logger.info("使用文件缓存的联盟图标 - 联盟ID: \(allianceID)")
            return image
        }
        
        // 从网络获取
        Logger.info("从网络获取联盟图标 - 联盟ID: \(allianceID)")
        let data = try await NetworkManager.shared.fetchData(from: url)
        
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
                Logger.info("联盟图标已保存到文件 - 联盟ID: \(allianceID)")
            } catch {
                Logger.error("保存联盟图标到文件失败 - 联盟ID: \(allianceID), error: \(error)")
            }
        }
        
        return image
    }
} 