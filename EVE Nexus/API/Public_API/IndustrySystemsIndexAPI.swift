import Foundation
import SwiftUI

// MARK: - 数据模型

struct IndustrySystem: Codable {
    let cost_indices: [CostIndex]
    let solar_system_id: Int
}

struct CostIndex: Codable {
    let activity: String
    let cost_index: Double
}

// MARK: - 错误类型

enum IndustrySystemsAPIError: LocalizedError {
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

// MARK: - 产业系统API

@globalActor actor IndustrySystemsAPIActor {
    static let shared = IndustrySystemsAPIActor()
}

@IndustrySystemsAPIActor
class IndustrySystemsAPI {
    static let shared = IndustrySystemsAPI()
    private let cacheDuration: TimeInterval = 8 * 60 * 60  // 8小时缓存

    private init() {}

    private struct CachedData: Codable {
        let data: [IndustrySystem]
        let timestamp: Date
    }

    // MARK: - 缓存方法

    private func getCacheDirectory() -> URL? {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent(
            "IndustryJobs", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: nil
        )

        return cacheDirectory
    }

    private func getCacheFilePath() -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("system_index.json")
    }

    private func loadFromCache() -> [IndustrySystem]? {
        guard let cacheFile = getCacheFilePath(),
            let data = try? Data(contentsOf: cacheFile),
            let cached = try? JSONDecoder().decode(CachedData.self, from: data),
            cached.timestamp.addingTimeInterval(cacheDuration) > Date()
        else {
            return nil
        }

        Logger.info("使用缓存的产业系统数据")
        return cached.data
    }

    private func saveToCache(_ systems: [IndustrySystem]) {
        guard let cacheFile = getCacheFilePath() else { return }

        let cachedData = CachedData(data: systems, timestamp: Date())
        do {
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("产业系统数据已缓存到文件")
        } catch {
            Logger.error("保存产业系统缓存失败: \(error)")
        }
    }

    // MARK: - 公共方法

    func fetchIndustrySystems(forceRefresh: Bool = false) async throws -> [IndustrySystem] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache() {
                return cached
            }
        }

        // 构建URL
        let baseURL = "https://esi.evetech.net/industry/systems"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility"),
        ]

        guard let url = components?.url else {
            throw IndustrySystemsAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let systems = try JSONDecoder().decode([IndustrySystem].self, from: data)

        // 保存到缓存
        saveToCache(systems)

        return systems
    }
} 
