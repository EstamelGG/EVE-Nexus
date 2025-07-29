import Foundation

// MARK: - Data Models

public struct CharacterFitting: Codable {
    var description: String?
    var fitting_id: Int
    var items: [FittingItem]
    var name: String
    var ship_type_id: Int
}

// 缓存数据结构
private struct FittingCache: Codable {
    let update_time: Int64
    let data: [CharacterFitting]
}

// MARK: - API Methods

public class CharacterFittingAPI {
    private static let cacheDirectory = "Fitting"
    private static let cacheExpiration: TimeInterval = 8 * 60 * 60  // 8小时

    public static func getCharacterFittings(characterID: Int, forceRefresh: Bool = false) async throws -> [CharacterFitting] {
        // 如果不是强制刷新，尝试从缓存获取数据
        if !forceRefresh, let cachedData = try? loadFromCache(characterID: characterID) {
            Logger.info("成功从缓存获取装配数据，数量: \(cachedData.count)")
            return cachedData
        }

        Logger.info("缓存未命中或强制刷新，从API获取数据")
        // 从API获取数据
        let urlString =
            "https://esi.evetech.net/characters/\(characterID)/fittings/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("无效的URL: \(urlString)")
            throw APIError.invalidURL
        }

        do {
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url,
                characterId: characterID
            )

            let fittings = try JSONDecoder().decode([CharacterFitting].self, from: data)
            Logger.info("成功从API获取装配数据，数量: \(fittings.count)")

            // 保存到缓存
            try saveToCache(characterID: characterID, fittings: fittings)
            return fittings
        } catch {
            Logger.error("获取装配数据失败: \(error)")
            throw error
        }
    }

    /// 上传装配配置到EVE服务器
    /// - Parameters:
    ///   - characterID: 角色ID
    ///   - fitting: 要上传的装配配置
    /// - Returns: 上传成功后返回的装配ID
    public static func uploadCharacterFitting(characterID: Int, fitting: CharacterFitting) async throws -> Int {
        Logger.info("开始上传装配配置 - 角色ID: \(characterID), 装配名称: \(fitting.name)")
        
        // 构建URL
        let urlString = "https://esi.evetech.net/characters/\(characterID)/fittings/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("无效的URL: \(urlString)")
            throw APIError.invalidURL
        }

        do {
            // 确保description有值，如果为nil则使用默认值
            var fittingToUpload = fitting
            if fittingToUpload.description == nil || fittingToUpload.description?.isEmpty == true {
                fittingToUpload.description = "Uploaded from Tritanium"
            }
            
            // 将装配配置编码为JSON
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(fittingToUpload)
            
            // 打印请求体内容用于调试
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Logger.debug("上传装配配置请求体: \(jsonString)")
            }

            // 发送POST请求
            let responseData = try await NetworkManager.shared.postDataWithToken(
                to: url,
                body: jsonData,
                characterId: characterID,
                timeouts: [10]  // POST 请求只发送一次，免得重复创建配置
            )

            // 解析响应，获取装配ID
            if let responseString = String(data: responseData, encoding: .utf8) {
                Logger.debug("上传装配配置响应: \(responseString)")
            }
            
            // ESI API返回的是一个包含fitting_id的JSON对象
            struct FittingUploadResponse: Codable {
                let fitting_id: Int
            }
            
            let response = try JSONDecoder().decode(FittingUploadResponse.self, from: responseData)
            Logger.info("成功上传装配配置 - 装配ID: \(response.fitting_id)")
            
            return response.fitting_id
        } catch {
            Logger.error("上传装配配置失败: \(error)")
            throw error
        }
    }

    /// 删除EVE服务器上的装配配置
    /// - Parameters:
    ///   - characterID: 角色ID
    ///   - fittingID: 要删除的装配配置ID
    public static func deleteCharacterFitting(characterID: Int, fittingID: Int) async throws {
        Logger.info("开始删除装配配置 - 角色ID: \(characterID), 装配ID: \(fittingID)")
        
        // 构建URL
        let urlString = "https://esi.evetech.net/characters/\(characterID)/fittings/\(fittingID)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("无效的URL: \(urlString)")
            throw APIError.invalidURL
        }

        do {
            // 发送DELETE请求
            _ = try await NetworkManager.shared.deleteDataWithToken(
                from: url,
                characterId: characterID,
                noRetryKeywords: ["Unhandled internal error encountered"]  // 说明已经删除了
            )
            
            Logger.info("成功删除装配配置 - 角色ID: \(characterID), 装配ID: \(fittingID)")
        } catch {
            Logger.error("删除装配配置失败: \(error)")
            throw error
        }
    }

    // MARK: - Cache Methods

    private static func getCacheFilePath(characterID: Int) -> URL {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDir = documentsDirectory.appendingPathComponent(cacheDirectory)

        // 确保缓存目录存在
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        return cacheDir.appendingPathComponent("fittings_\(characterID).json")
    }

    private static func loadFromCache(characterID: Int) throws -> [CharacterFitting]? {
        let fileURL = getCacheFilePath(characterID: characterID)

        guard let data = try? Data(contentsOf: fileURL) else {
            Logger.info("缓存文件不存在: \(fileURL)")
            return nil
        }

        do {
            let cache = try JSONDecoder().decode(FittingCache.self, from: data)

            // 检查缓存是否过期
            let currentTime = Int64(Date().timeIntervalSince1970)
            if currentTime - cache.update_time > Int64(cacheExpiration) {
                Logger.info(
                    "缓存已过期: \(fileURL), 更新时间: \(cache.update_time), 当前时间: \(currentTime), 过期时间: \(cacheExpiration)"
                )
                return nil
            }
            Logger.info(
                "从缓存获取数据:\(fileURL), 超时剩余时间:\(Int64(cacheExpiration) - (currentTime - cache.update_time)), 数据数量:\(cache.data.count)"
            )
            return cache.data
        } catch {
            Logger.error("解析缓存数据失败: \(error)")
            return nil
        }
    }

    private static func saveToCache(characterID: Int, fittings: [CharacterFitting]) throws {
        let cache = FittingCache(
            update_time: Int64(Date().timeIntervalSince1970),
            data: fittings
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(cache)

        let fileURL = getCacheFilePath(characterID: characterID)
        try data.write(to: fileURL)
    }
}

// MARK: - Error Handling

enum APIError: Error {
    case invalidURL
}
