import Foundation
import SwiftUI

// 角色公开信息数据模型
struct CharacterPublicInfo: Codable {
    let alliance_id: Int?
    let birthday: String
    let bloodline_id: Int
    let corporation_id: Int
    let description: String?
    let gender: String
    let name: String
    let race_id: Int
    let security_status: Double?
    let title: String?
}

@globalActor actor CharacterAPIActor {
    static let shared = CharacterAPIActor()
}

@CharacterAPIActor
class CharacterAPI {
    static let shared = CharacterAPI()
    
    // 缓存结构
    private struct PublicInfoCacheEntry: Codable {
        let value: CharacterPublicInfo
        let timestamp: Date
    }
    
    private struct PortraitCacheEntry: Codable {
        let imageData: Data
        let timestamp: Date
    }
    
    // 内存缓存
    private var publicInfoMemoryCache: [Int: PublicInfoCacheEntry] = [:]
    private var portraitMemoryCache: [String: PortraitCacheEntry] = [:]  // key: "characterId_size"
    
    // 缓存超时时间
    private let publicInfoCacheTimeout: TimeInterval = 3600 // 1小时
    private let portraitCacheTimeout: TimeInterval = 86400 // 24小时
    
    // UserDefaults键前缀
    private let publicInfoCachePrefix = "character_public_info_"
    private let portraitCachePrefix = "character_portrait_"
    
    private init() {}
    
    // 检查公开信息缓存是否有效
    private func isPublicInfoCacheValid(_ cache: PublicInfoCacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < publicInfoCacheTimeout
    }
    
    // 检查头像缓存是否有效
    private func isPortraitCacheValid(_ cache: PortraitCacheEntry?) -> Bool {
        guard let cache = cache else { return false }
        return Date().timeIntervalSince(cache.timestamp) < portraitCacheTimeout
    }
    
    // 从UserDefaults获取公开信息缓存
    private func getPublicInfoDiskCache(characterId: Int) -> PublicInfoCacheEntry? {
        let key = publicInfoCachePrefix + String(characterId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(PublicInfoCacheEntry.self, from: data) else {
            return nil
        }
        return cache
    }
    
    // 从UserDefaults获取头像缓存
    private func getPortraitDiskCache(characterId: Int, size: Int) -> PortraitCacheEntry? {
        let key = portraitCachePrefix + "\(characterId)_\(size)"
        guard let data = UserDefaults.standard.data(forKey: key),
              let cache = try? JSONDecoder().decode(PortraitCacheEntry.self, from: data) else {
            return nil
        }
        return cache
    }
    
    // 保存公开信息缓存到UserDefaults
    private func savePublicInfoToDiskCache(characterId: Int, cache: PublicInfoCacheEntry) {
        let key = publicInfoCachePrefix + String(characterId)
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // 保存头像缓存到UserDefaults
    private func savePortraitToDiskCache(characterId: Int, size: Int, cache: PortraitCacheEntry) {
        let key = portraitCachePrefix + "\(characterId)_\(size)"
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    // 清除指定角色的所有缓存
    private func clearCache(characterId: Int) {
        // 清除公开信息缓存
        publicInfoMemoryCache.removeValue(forKey: characterId)
        let publicInfoKey = publicInfoCachePrefix + String(characterId)
        UserDefaults.standard.removeObject(forKey: publicInfoKey)
        
        // 清除所有尺寸的头像缓存
        let sizes = [32, 64, 128, 256, 512]
        for size in sizes {
            let portraitKey = portraitCachePrefix + "\(characterId)_\(size)"
            portraitMemoryCache.removeValue(forKey: "\(characterId)_\(size)")
            UserDefaults.standard.removeObject(forKey: portraitKey)
        }
    }
    
    // 获取角色公开信息
    func fetchCharacterPublicInfo(characterId: Int, forceRefresh: Bool = false) async throws -> CharacterPublicInfo {
        // 如果不是强制刷新，先尝试使用缓存
        if !forceRefresh {
            // 1. 先检查内存缓存
            if let memoryCached = publicInfoMemoryCache[characterId],
               isPublicInfoCacheValid(memoryCached) {
                Logger.info("使用内存缓存的角色公开信息 - 角色ID: \(characterId)")
                return memoryCached.value
            }
            
            // 2. 如果内存缓存不可用，检查磁盘缓存
            if let diskCached = getPublicInfoDiskCache(characterId: characterId),
               isPublicInfoCacheValid(diskCached) {
                Logger.info("使用磁盘缓存的角色公开信息 - 角色ID: \(characterId)")
                // 更新内存缓存
                publicInfoMemoryCache[characterId] = diskCached
                return diskCached.value
            }
            
            Logger.info("缓存未命中或已过期,需要从服务器获取角色公开信息 - 角色ID: \(characterId)")
        }
        
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchData(from: url)
        let info = try JSONDecoder().decode(CharacterPublicInfo.self, from: data)
        
        // 创建新的缓存条目
        let cacheEntry = PublicInfoCacheEntry(value: info, timestamp: Date())
        
        // 更新内存缓存
        publicInfoMemoryCache[characterId] = cacheEntry
        
        // 更新磁盘缓存
        savePublicInfoToDiskCache(characterId: characterId, cache: cacheEntry)
        
        Logger.info("成功获取角色公开信息 - 角色ID: \(characterId)")
        return info
    }
    
    // 获取角色头像
    func fetchCharacterPortrait(characterId: Int, size: Int = 128, forceRefresh: Bool = false) async throws -> UIImage {
        let cacheKey = "\(characterId)_\(size)"
        
        // 如果不是强制刷新，先尝试使用缓存
        if !forceRefresh {
            // 1. 先检查内存缓存
            if let memoryCached = portraitMemoryCache[cacheKey],
               isPortraitCacheValid(memoryCached),
               let image = UIImage(data: memoryCached.imageData) {
                Logger.info("使用内存缓存的角色头像 - 角色ID: \(characterId)")
                return image
            }
            
            // 2. 如果内存缓存不可用，检查磁盘缓存
            if let diskCached = getPortraitDiskCache(characterId: characterId, size: size),
               isPortraitCacheValid(diskCached),
               let image = UIImage(data: diskCached.imageData) {
                Logger.info("使用磁盘缓存的角色头像 - 角色ID: \(characterId)")
                // 更新内存缓存
                portraitMemoryCache[cacheKey] = diskCached
                return image
            }
            
            Logger.info("缓存未命中或已过期,需要从服务器获取角色头像 - 角色ID: \(characterId)")
        }
        
        let urlString = "https://images.evetech.net/characters/\(characterId)/portrait?size=\(size)"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchData(from: url)
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidImageData
        }
        
        // 创建新的缓存条目
        let cacheEntry = PortraitCacheEntry(imageData: data, timestamp: Date())
        
        // 更新内存缓存
        portraitMemoryCache[cacheKey] = cacheEntry
        
        // 更新磁盘缓存
        savePortraitToDiskCache(characterId: characterId, size: size, cache: cacheEntry)
        
        Logger.info("成功获取角色头像 - 角色ID: \(characterId)")
        return image
    }
} 