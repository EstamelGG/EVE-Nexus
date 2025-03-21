import Foundation

class GetCorpContacts {
    static let shared = GetCorpContacts()
    private let cacheTimeout: TimeInterval = 8 * 3600  // 8小时缓存有效期

    private init() {}

    // 获取缓存文件路径
    private func getCacheFilePath(corporationId: Int) -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let contactsCacheDir = paths[0].appendingPathComponent("ContactsCache", isDirectory: true)

        // 确保目录存在
        if !FileManager.default.fileExists(atPath: contactsCacheDir.path) {
            try? FileManager.default.createDirectory(
                at: contactsCacheDir, withIntermediateDirectories: true
            )
        }

        return contactsCacheDir.appendingPathComponent("\(corporationId)_contacts.json")
    }

    // 从缓存加载数据
    private func loadFromCache(corporationId: Int) -> [ContactInfo]? {
        let cacheFile = getCacheFilePath(corporationId: corporationId)

        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cachedData = try decoder.decode(CachedContactsData.self, from: data)

            // 检查缓存是否过期
            if Date().timeIntervalSince(cachedData.timestamp) < cacheTimeout {
                Logger.debug("从缓存加载军团联系人数据成功 - 军团ID: \(corporationId)")
                return cachedData.contacts
            } else {
                Logger.debug("军团联系人缓存已过期 - 军团ID: \(corporationId)")
                return nil
            }
        } catch {
            Logger.error("读取军团联系人缓存失败 - 军团ID: \(corporationId), 错误: \(error)")
            return nil
        }
    }

    // 保存数据到缓存
    private func saveToCache(contacts: [ContactInfo], corporationId: Int) {
        let cacheFile = getCacheFilePath(corporationId: corporationId)
        let cachedData = CachedContactsData(contacts: contacts, timestamp: Date())

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cachedData)
            try data.write(to: cacheFile)
            Logger.debug("保存军团联系人数据到缓存成功 - 军团ID: \(corporationId)")
        } catch {
            Logger.error("保存军团联系人缓存失败 - 军团ID: \(corporationId), 错误: \(error)")
        }
    }

    // 获取所有联系人数据
    public func fetchContacts(characterId: Int, corporationId: Int, forceRefresh: Bool = false)
        async throws -> [ContactInfo]
    {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedContacts = loadFromCache(corporationId: corporationId) {
                return cachedContacts
            }
        }

        let baseUrlString =
            "https://esi.evetech.net/latest/corporations/\(corporationId)/contacts/?datasource=tranquility"
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
        saveToCache(contacts: contacts, corporationId: corporationId)

        return contacts
    }

    // 清除缓存
    func clearCache(for corporationId: Int) {
        let cacheFile = getCacheFilePath(corporationId: corporationId)
        try? FileManager.default.removeItem(at: cacheFile)
        Logger.debug("清除军团联系人缓存 - 军团ID: \(corporationId)")
    }
}
