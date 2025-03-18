import Foundation

// 联系人数据结构
struct ContactInfo: Codable {
    let contact_id: Int
    let contact_type: String
    let is_blocked: Bool?
    let is_watched: Bool?
    let label_ids: [Int64]?
    let standing: Double
}

// 缓存数据结构
struct CachedContactsData: Codable {
    let contacts: [ContactInfo]
    let timestamp: Date
}

class GetCharContacts {
    static let shared = GetCharContacts()
    private let cacheTimeout: TimeInterval = 8 * 3600  // 8小时缓存有效期

    private init() {}

    // 获取缓存文件路径
    private func getCacheFilePath(characterId: Int) -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let contactsCacheDir = paths[0].appendingPathComponent("ContactsCache", isDirectory: true)

        // 确保目录存在
        if !FileManager.default.fileExists(atPath: contactsCacheDir.path) {
            try? FileManager.default.createDirectory(
                at: contactsCacheDir, withIntermediateDirectories: true
            )
        }

        return contactsCacheDir.appendingPathComponent("\(characterId)_contacts.json")
    }

    // 从缓存加载数据
    private func loadFromCache(characterId: Int) -> [ContactInfo]? {
        let cacheFile = getCacheFilePath(characterId: characterId)

        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cachedData = try decoder.decode(CachedContactsData.self, from: data)

            // 检查缓存是否过期
            if Date().timeIntervalSince(cachedData.timestamp) < cacheTimeout {
                Logger.debug("从缓存加载角色联系人数据成功 - 角色ID: \(characterId)")
                return cachedData.contacts
            } else {
                Logger.debug("角色联系人缓存已过期 - 角色ID: \(characterId)")
                return nil
            }
        } catch {
            Logger.error("读取角色联系人缓存失败 - 角色ID: \(characterId), 错误: \(error)")
            return nil
        }
    }

    // 保存数据到缓存
    private func saveToCache(contacts: [ContactInfo], characterId: Int) {
        let cacheFile = getCacheFilePath(characterId: characterId)
        let cachedData = CachedContactsData(contacts: contacts, timestamp: Date())

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cachedData)
            try data.write(to: cacheFile)
            Logger.debug("保存角色联系人数据到缓存成功 - 角色ID: \(characterId)")
        } catch {
            Logger.error("保存角色联系人缓存失败 - 角色ID: \(characterId), 错误: \(error)")
        }
    }

    // 获取所有联系人数据
    public func fetchContacts(characterId: Int, forceRefresh: Bool = false) async throws
        -> [ContactInfo]
    {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedContacts = loadFromCache(characterId: characterId) {
                return cachedContacts
            }
        }

        let baseUrlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/contacts/?datasource=tranquility"
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
        saveToCache(contacts: contacts, characterId: characterId)

        return contacts
    }

    // 清除缓存
    func clearCache(for characterId: Int) {
        let cacheFile = getCacheFilePath(characterId: characterId)
        try? FileManager.default.removeItem(at: cacheFile)
        Logger.debug("清除角色联系人缓存 - 角色ID: \(characterId)")
    }
}
