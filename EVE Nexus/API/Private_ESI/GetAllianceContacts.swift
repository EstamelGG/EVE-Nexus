import Foundation

class GetAllianceContacts {
    static let shared = GetAllianceContacts()
    private let cacheTimeout: TimeInterval = 8 * 3600  // 8小时缓存有效期

    private init() {}

    // 获取缓存文件路径
    private func getCacheFilePath(allianceId: Int) -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let contactsCacheDir = paths[0].appendingPathComponent("ContactsCache", isDirectory: true)

        // 确保目录存在
        if !FileManager.default.fileExists(atPath: contactsCacheDir.path) {
            try? FileManager.default.createDirectory(
                at: contactsCacheDir, withIntermediateDirectories: true
            )
        }

        return contactsCacheDir.appendingPathComponent("\(allianceId)_contacts.json")
    }

    // 从缓存加载数据
    private func loadFromCache(allianceId: Int) -> [ContactInfo]? {
        let cacheFile = getCacheFilePath(allianceId: allianceId)

        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cachedData = try decoder.decode(CachedContactsData.self, from: data)

            // 检查缓存是否过期
            if Date().timeIntervalSince(cachedData.timestamp) < cacheTimeout {
                Logger.debug("从缓存加载联盟联系人数据成功 - 联盟ID: \(allianceId)")
                return cachedData.contacts
            } else {
                Logger.debug("联盟联系人缓存已过期 - 联盟ID: \(allianceId)")
                return nil
            }
        } catch {
            Logger.error("读取联盟联系人缓存失败 - 联盟ID: \(allianceId), 错误: \(error)")
            return nil
        }
    }

    // 保存数据到缓存
    private func saveToCache(contacts: [ContactInfo], allianceId: Int) {
        let cacheFile = getCacheFilePath(allianceId: allianceId)
        let cachedData = CachedContactsData(contacts: contacts, timestamp: Date())

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cachedData)
            try data.write(to: cacheFile)
            Logger.debug("保存联盟联系人数据到缓存成功 - 联盟ID: \(allianceId)")
        } catch {
            Logger.error("保存联盟联系人缓存失败 - 联盟ID: \(allianceId), 错误: \(error)")
        }
    }

    // 获取所有联系人数据
    public func fetchContacts(characterId: Int, allianceId: Int, forceRefresh: Bool = false)
        async throws -> [ContactInfo]
    {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedContacts = loadFromCache(allianceId: allianceId) {
                return cachedContacts
            }
        }

        let baseUrlString =
            "https://esi.evetech.net/latest/alliances/\(allianceId)/contacts/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        let contacts = try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 3,
            decoder: { try JSONDecoder().decode([ContactInfo].self, from: $0) }
        )

        // 保存到缓存
        saveToCache(contacts: contacts, allianceId: allianceId)

        return contacts
    }

    // 清除缓存
    func clearCache(for allianceId: Int) {
        let cacheFile = getCacheFilePath(allianceId: allianceId)
        try? FileManager.default.removeItem(at: cacheFile)
        Logger.debug("清除联盟联系人缓存 - 联盟ID: \(allianceId)")
    }
}
