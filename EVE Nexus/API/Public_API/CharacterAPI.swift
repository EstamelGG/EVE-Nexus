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
    
    private init() {}
    
    // 获取角色公开信息
    func fetchCharacterPublicInfo(characterId: Int) async throws -> CharacterPublicInfo {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchData(from: url)
        let info = try JSONDecoder().decode(CharacterPublicInfo.self, from: data)
        
        Logger.info("成功获取角色公开信息 - 角色ID: \(characterId)")
        return info
    }
    
    // 获取角色头像
    func fetchCharacterPortrait(characterId: Int, size: Int = 128, forceRefresh: Bool = false) async throws -> UIImage {
        let urlString = "https://images.evetech.net/characters/\(characterId)/portrait?size=\(size)"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let cacheKey = "character_portrait_\(characterId)_\(size)"
        let filename = "character_portrait_\(characterId)_\(size).png"
        
        // 检查内存缓存
        if !forceRefresh,
           let cached = UserDefaults.standard.data(forKey: cacheKey),
           let image = UIImage(data: cached) {
            Logger.info("使用内存缓存的角色头像 - 角色ID: \(characterId)")
            return image
        }
        
        // 检查文件缓存
        let fileURL = StaticResourceManager.shared.getCharacterPortraitsPath()
            .appendingPathComponent(filename)
        
        if !forceRefresh,
           let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            // 更新内存缓存
            UserDefaults.standard.set(data, forKey: cacheKey)
            Logger.info("使用文件缓存的角色头像 - 角色ID: \(characterId)")
            return image
        }
        
        // 从网络获取
        Logger.info("从网络获取角色头像 - 角色ID: \(characterId)")
        let data = try await NetworkManager.shared.fetchData(from: url)
        
        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidImageData
        }
        
        // 更新内存缓存
        UserDefaults.standard.set(data, forKey: cacheKey)
        
        // 异步保存到文件
        Task {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL)
                Logger.info("角色头像已保存到文件 - 角色ID: \(characterId)")
            } catch {
                Logger.error("保存角色头像到文件失败 - 角色ID: \(characterId), error: \(error)")
            }
        }
        
        return image
    }
} 