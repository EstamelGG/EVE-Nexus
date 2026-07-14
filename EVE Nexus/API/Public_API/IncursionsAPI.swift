import Foundation
import SwiftUI

// MARK: - 错误类型

enum IncursionsAPIError: LocalizedError {
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

// MARK: - 入侵API

@globalActor actor IncursionsAPIActor {
    static let shared = IncursionsAPIActor()
}

@IncursionsAPIActor
class IncursionsAPI {
    static let shared = IncursionsAPI()
    private init() {}

    /// 缓存相关常量
    private let cacheDuration: TimeInterval = 30 * 60 // 30 分钟缓存

    struct CachedData: Codable {
        let data: [Incursion]
        let timestamp: Date
    }

    // MARK: - 文件缓存相关方法

    /// 获取入侵信息缓存目录
    private func getCacheDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDirectory = documentsPath.appendingPathComponent("IncursionsCache")

        // 确保缓存目录存在
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: cacheDirectory, withIntermediateDirectories: true
                )
                Logger.info("创建入侵缓存目录: \(cacheDirectory.path)")
            } catch {
                Logger.error("创建入侵缓存目录失败: \(error)")
            }
        }

        return cacheDirectory
    }

    /// 从文件加载入侵信息
    private func loadFromCache() -> [Incursion]? {
        let cacheDirectory = getCacheDirectory()
        let cacheFilePath = cacheDirectory.appendingPathComponent("incursions.json")

        guard FileManager.default.fileExists(atPath: cacheFilePath.path) else {
            Logger.debug("入侵缓存文件不存在")
            return nil
        }

        do {
            // 检查文件修改时间
            let attributes = try FileManager.default.attributesOfItem(atPath: cacheFilePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let timeSinceModification = Date().timeIntervalSince(modificationDate)
                if timeSinceModification > cacheDuration {
                    Logger.info("入侵缓存已过期，已过: \(Int(timeSinceModification / 60))分钟")
                    return nil
                } else {
                    let remainingMinutes = (cacheDuration - timeSinceModification) / 60
                    Logger.info("入侵缓存有效，剩余时间: \(Int(remainingMinutes))分钟")
                }
            }

            let data = try Data(contentsOf: cacheFilePath)
            let cached = try JSONDecoder().decode(CachedData.self, from: data)
            Logger.info("成功从文件加载入侵信息，数量: \(cached.data.count)")
            return cached.data
        } catch {
            Logger.error("加载入侵缓存文件失败: \(error)")
            return nil
        }
    }

    /// 保存入侵信息到文件
    private func saveToCache(_ incursions: [Incursion]) {
        let cacheDirectory = getCacheDirectory()
        let cacheFilePath = cacheDirectory.appendingPathComponent("incursions.json")
        let cachedData = CachedData(data: incursions, timestamp: Date())

        do {
            let data = try JSONEncoder().encode(cachedData)
            try data.write(to: cacheFilePath)
            Logger.info(
                "成功保存入侵信息到文件，数量: \(incursions.count), 大小: \(data.count) bytes"
            )
        } catch {
            Logger.error("保存入侵缓存文件失败: \(error)")
        }
    }

    // MARK: - 公共方法

    /// 获取入侵数据
    /// - Parameter forceRefresh: 是否强制刷新
    /// - Returns: 入侵数据数组
    func fetchIncursions(forceRefresh: Bool = false) async throws -> [Incursion] {
        // 如果不是强制刷新，尝试从缓存获取
        if !forceRefresh {
            if let cached = loadFromCache() {
                return cached
            }
        }

        // 构建URL
        let baseURL = "https://esi.evetech.net/incursions/"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "datasource", value: "tranquility"),
        ]

        guard let url = components?.url else {
            throw IncursionsAPIError.invalidURL
        }

        // 执行请求
        let data = try await NetworkManager.shared.fetchData(from: url)
        let incursions = try JSONDecoder().decode([Incursion].self, from: data)

        // 保存到缓存
        saveToCache(incursions)

        Logger.info("成功获取入侵数据，数量: \(incursions.count)")
        return incursions
    }
}
