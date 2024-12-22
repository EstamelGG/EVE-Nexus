import Foundation
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
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case .decodingError(let error):
            return "数据解码错误: \(error.localizedDescription)"
        case .httpError(let code):
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
    
    private init() {}
    
    // MARK: - 公共方法
    
    /// 获取物品渲染图
    /// - Parameters:
    ///   - typeId: 物品ID
    ///   - size: 图片尺寸
    /// - Returns: 图片数据
    func fetchItemRender(typeId: Int, size: Int = 64) async throws -> Data {
        // 检查本地缓存
        if let cachedData = StaticResourceManager.shared.getNetRender(typeId: typeId) {
            return cachedData
        }
        
        // 构建URL
        let baseURL = "https://images.evetech.net/types/\(typeId)/render"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "size", value: String(size))
        ]
        
        guard let url = components?.url else {
            throw ItemRenderAPIError.invalidURL
        }
        
        // 执行请求
        let imageData = try await NetworkManager.shared.fetchData(from: url)
        
        // 保存到本地缓存
        try StaticResourceManager.shared.saveNetRender(imageData, typeId: typeId)
        
        return imageData
    }
} 