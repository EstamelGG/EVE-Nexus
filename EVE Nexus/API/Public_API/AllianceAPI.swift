import Foundation
import Kingfisher
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

    // 获取联盟图标URL
    private func getLogoURL(allianceId: Int, size: Int = 64) -> URL {
        return URL(string: "https://images.evetech.net/alliances/\(allianceId)/logo?size=\(size)")!
    }

    // 获取联盟图标
    func fetchAllianceLogo(allianceID: Int, size: Int = 64, forceRefresh: Bool = false) async throws
        -> UIImage
    {
        let logoURL = getLogoURL(allianceId: allianceID, size: size)

        var options: KingfisherOptionsInfo = await [
            .cacheOriginalImage,
            .backgroundDecode,
            .scaleFactor(UIScreen.main.scale),
            .transition(.fade(0.2)),
            .cacheSerializer(FormatIndicatedCacheSerializer.png),  // 使用PNG格式缓存
            .diskCacheExpiration(.days(30)),  // 磁盘缓存30天
            .memoryCacheExpiration(.days(7)),  // 内存缓存7天
            .processor(DownsamplingImageProcessor(size: CGSize(width: size, height: size))),  // 下采样处理
            .alsoPrefetchToMemory,  // 预加载到内存
        ]

        // 如果需要强制刷新，添加相应的选项
        if forceRefresh {
            options.append(.forceRefresh)
            options.append(.fromMemoryCacheOrRefresh)
        }

        return try await withCheckedThrowingContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: logoURL, options: options) { result in
                switch result {
                case let .success(imageResult):
                    Logger.info("成功获取联盟图标 - 联盟ID: \(allianceID), 大小: \(size)")
                    continuation.resume(returning: imageResult.image)
                case let .failure(error):
                    Logger.error("获取联盟图标失败 - 联盟ID: \(allianceID), 错误: \(error)")
                    continuation.resume(throwing: NetworkError.invalidImageData)
                }
            }
        }
    }

    func fetchAllianceInfo(allianceId: Int, forceRefresh: Bool = false) async throws -> AllianceInfo
    {
        let cacheKey = "alliance_info_\(allianceId)"
        let cacheTimeKey = "alliance_info_\(allianceId)_time"

        // 检查缓存
        if !forceRefresh,
            let cachedData = UserDefaults.standard.data(forKey: cacheKey),
            let lastUpdateTime = UserDefaults.standard.object(forKey: cacheTimeKey) as? Date,
            Date().timeIntervalSince(lastUpdateTime) < 7 * 24 * 3600
        {
            do {
                let info = try JSONDecoder().decode(AllianceInfo.self, from: cachedData)
                Logger.info("使用缓存的联盟信息 - 联盟ID: \(allianceId)")
                return info
            } catch {
                Logger.error("解析缓存的联盟信息失败: \(error)")
            }
        }

        // 从网络获取数据
        let urlString =
            "https://esi.evetech.net/latest/alliances/\(allianceId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        let info = try JSONDecoder().decode(AllianceInfo.self, from: data)

        // 更新缓存
        Logger.info("保存联盟信息到缓存 - Key: \(cacheKey), 数据大小: \(data.count) bytes")
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheTimeKey)

        Logger.info("成功获取联盟信息 - 联盟ID: \(allianceId)")
        return info
    }
}
