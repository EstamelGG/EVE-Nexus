import Foundation
import Kingfisher
import SwiftUI

// MARK: - 错误类型

enum ItemRenderAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case httpError(Int)
    case rateLimitExceeded

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
        }
    }
}

// MARK: - 物品渲染API

@globalActor actor ItemRenderAPIActor {
    static let shared = ItemRenderAPIActor()
}

@ItemRenderAPIActor
class ItemRenderAPI {
    static let shared = ItemRenderAPI()

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

    // 获取物品渲染图URL
    private func getRenderURL(typeId: Int, size: Int = 64) -> URL {
        var components = URLComponents(string: "https://images.evetech.net/types/\(typeId)/render")!
        components.queryItems = [
            URLQueryItem(name: "size", value: String(size))
        ]
        return components.url!
    }

    // MARK: - 公共方法

    /// 获取物品渲染图
    /// - Parameters:
    ///   - typeId: 物品ID
    ///   - size: 图片尺寸
    ///   - forceRefresh: 是否强制刷新
    /// - Returns: 图片
    func fetchItemRender(typeId: Int, size: Int = 512, forceRefresh: Bool = false) async throws
        -> UIImage
    {
        let renderURL = getRenderURL(typeId: typeId, size: size)

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

        return try await withCheckedThrowingContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: renderURL, options: options) { result in
                switch result {
                case let .success(imageResult):
                    Logger.info("成功获取物品渲染图 - 物品ID: \(typeId), 大小: \(size)")
                    continuation.resume(returning: imageResult.image)
                case let .failure(error):
                    Logger.error("获取物品渲染图失败 - 物品ID: \(typeId), 错误: \(error)")
                    continuation.resume(throwing: NetworkError.invalidImageData)
                }
            }
        }
    }
}
