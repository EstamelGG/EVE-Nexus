import Foundation
import SwiftUI

// MARK: - 物品渲染API

@globalActor actor ItemRenderAPIActor {
    static let shared = ItemRenderAPIActor()
}

@ItemRenderAPIActor
class ItemRenderAPI {
    static let shared = ItemRenderAPI()

    private init() {
        // 使用 ImageCacheManager，无需初始化配置
    }

    /// 获取物品渲染图URL
    private func getRenderURL(typeId: Int, size: Int = 64) -> URL {
        var components = URLComponents(string: "https://images.evetech.net/types/\(typeId)/render")!
        components.queryItems = [
            URLQueryItem(name: "size", value: String(size)),
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

        do {
            // 使用 ImageCacheManager
            // backgroundUpdate: true 表示先返回缓存，后台验证ETag并更新
            let image = try await ImageCacheManager.shared.fetchImage(
                from: renderURL,
                forceRefresh: forceRefresh,
                backgroundUpdate: true
            )

            Logger.info("[ItemRenderAPI] 成功获取物品渲染图 - 物品ID: \(typeId), 大小: \(size)")
            return image

        } catch {
            Logger.error("[ItemRenderAPI] 获取物品渲染图失败 - 物品ID: \(typeId), 错误: \(error)")
            throw error
        }
    }
}
