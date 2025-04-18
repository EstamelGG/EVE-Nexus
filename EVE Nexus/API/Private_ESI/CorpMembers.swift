import Foundation

// 军团成员信息模型
public struct MemberTrackingInfo: Codable {
    public let character_id: Int
    public let location_id: Int?
    public let logoff_date: String?
    public let logon_date: String?
    public let ship_type_id: Int?
    public let start_date: String?
}

// 缓存数据结构
private struct MemberTrackingCacheData: Codable {
    let data: [MemberTrackingInfo]
    let timestamp: Date

    var isExpired: Bool {
        // 设置缓存有效期为2小时
        return Date().timeIntervalSince(timestamp) > 2 * 3600
    }
}

@globalActor public actor CorpMembersActor {
    public static let shared = CorpMembersActor()
    private init() {}
}

@CorpMembersActor
public class CorpMembersAPI {
    public static let shared = CorpMembersAPI()

    private init() {}

    // MARK: - Public Methods

    public func fetchMemberTracking(characterId: Int, forceRefresh: Bool = false) async throws
        -> [MemberTrackingInfo]
    {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 检查缓存
        if !forceRefresh, let cachedData = loadMemberTrackingFromCache(corporationId: corporationId)
        {
            Logger.info("使用缓存的军团成员信息 - 军团ID: \(corporationId)")
            return cachedData
        }

        // 3. 从API获取
        return try await fetchFromAPI(corporationId: corporationId, characterId: characterId)
    }

    private func fetchFromAPI(corporationId: Int, characterId: Int) async throws
        -> [MemberTrackingInfo]
    {
        Logger.info("开始获取军团成员信息 - 军团ID: \(corporationId)")

        let urlString =
            "https://esi.evetech.net/latest/corporations/\(corporationId)/membertracking/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        do {
            let headers = [
                "Accept": "application/json",
                "Content-Type": "application/json",
            ]

            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url,
                characterId: characterId,
                headers: headers
            )

            let members = try JSONDecoder().decode([MemberTrackingInfo].self, from: data)
            Logger.debug("成功获取军团成员信息，共 \(members.count) 条记录")

            // 保存到缓存
            saveMemberTrackingToCache(members, corporationId: corporationId)

            Logger.info("成功获取所有成员信息 - 军团ID: \(corporationId), 总条数: \(members.count)")
            return members

        } catch {
            Logger.error("获取军团成员信息失败 - 军团ID: \(corporationId), 错误: \(error)")
            throw error
        }
    }

    // MARK: - Cache Methods

    private func getCacheDirectory() -> URL? {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent(
            "CorpMembers", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: nil
        )

        return cacheDirectory
    }

    private func getCacheFilePath(corporationId: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("\(corporationId)_membertracking.json")
    }

    private func loadMemberTrackingFromCache(corporationId: Int) -> [MemberTrackingInfo]? {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else {
            Logger.error("获取缓存文件路径失败 - 军团ID: \(corporationId)")
            return nil
        }

        do {
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                Logger.info("缓存文件不存在 - 军团ID: \(corporationId)")
                return nil
            }

            let data = try Data(contentsOf: cacheFile)
            let cached = try JSONDecoder().decode(MemberTrackingCacheData.self, from: data)

            if cached.isExpired {
                Logger.info("缓存已过期 - 军团ID: \(corporationId)")
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }

            Logger.info("成功从缓存加载成员信息 - 军团ID: \(corporationId)")
            return cached.data
        } catch {
            Logger.error("读取缓存文件失败 - 军团ID: \(corporationId), 错误: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }

    private func saveMemberTrackingToCache(_ members: [MemberTrackingInfo], corporationId: Int) {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else {
            Logger.error("获取缓存文件路径失败 - 军团ID: \(corporationId)")
            return
        }

        do {
            let cachedData = MemberTrackingCacheData(data: members, timestamp: Date())
            let encodedData = try JSONEncoder().encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("成员信息已缓存到文件 - 军团ID: \(corporationId)")
        } catch {
            Logger.error("保存成员信息缓存失败: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }
}
