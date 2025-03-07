import Foundation

public struct CharacterMedal: Codable {
    public let date: String
    public let description: String
    public let reason: String?
    public let title: String
}

public class CharacterMedalsAPI {
    public static let shared = CharacterMedalsAPI()

    private let cachePrefix = "character_medals_"
    private let cacheTimeout: TimeInterval = 3600  // 1小时缓存

    private init() {}

    public func fetchCharacterMedals(characterId: Int) async throws -> [CharacterMedal]? {
        // 检查缓存
        if let cached = getCachedMedals(characterId: characterId) {
            Logger.info("使用缓存的奖章数据 - 角色ID: \(characterId)")
            return cached
        }

        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/medals/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        let medals = try? JSONDecoder().decode([CharacterMedal].self, from: data)

        // 保存到缓存
        if let medals = medals {
            saveMedalsToCache(medals: medals, characterId: characterId)
        }

        return medals
    }

    private func getCachedMedals(characterId: Int) -> [CharacterMedal]? {
        let key = cachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
            let cache = try? JSONDecoder().decode(CacheEntry.self, from: data),
            Date().timeIntervalSince(cache.timestamp) < cacheTimeout
        else {
            return nil
        }
        return cache.medals
    }

    private func saveMedalsToCache(medals: [CharacterMedal], characterId: Int) {
        let key = cachePrefix + String(characterId)
        let cache = CacheEntry(medals: medals, timestamp: Date())
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
            Logger.info("保存奖章数据到缓存 - 角色ID: \(characterId), 数量: \(medals.count)")
        }
    }

    private struct CacheEntry: Codable {
        let medals: [CharacterMedal]
        let timestamp: Date
    }
}
