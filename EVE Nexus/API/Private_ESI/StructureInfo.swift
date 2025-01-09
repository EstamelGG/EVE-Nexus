import Foundation

class StructureInfoResponse: Codable {
    let name: String
    let owner_id: Int
    let position: Position
    let solar_system_id: Int
    let type_id: Int
    
    struct Position: Codable {
        let x: Double
        let y: Double
        let z: Double
    }
    
    init(name: String, owner_id: Int, position: Position, solar_system_id: Int, type_id: Int) {
        self.name = name
        self.owner_id = owner_id
        self.position = position
        self.solar_system_id = solar_system_id
        self.type_id = type_id
    }
}

@MainActor
class StructureInfoAPI {
    static let shared = StructureInfoAPI()
    
    private let cache: NSCache<NSNumber, StructureInfoResponse> = {
        let cache = NSCache<NSNumber, StructureInfoResponse>()
        cache.name = "com.eve.nexus.structureinfo"
        cache.countLimit = 1000 // 最多缓存1000个建筑物信息
        return cache
    }()
    
    private init() {}
    
    func fetchStructureInfo(structureId: Int, characterId: Int) async throws -> StructureInfoResponse {
        // 检查缓存
        if let cachedInfo = cache.object(forKey: NSNumber(value: structureId)) {
            Logger.debug("使用缓存的建筑物信息 - 建筑物ID: \(structureId)")
            return cachedInfo
        }
        
        // 构建URL
        let urlString = "https://esi.evetech.net/latest/universe/structures/\(structureId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的URL"])
        }
        
        Logger.debug("开始获取建筑物信息 - 建筑物ID: \(structureId)")
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        // 解析响应
        let structureInfo = try JSONDecoder().decode(StructureInfoResponse.self, from: data)
        
        // 保存到缓存
        cache.setObject(structureInfo, forKey: NSNumber(value: structureId))
        
        Logger.debug("成功获取建筑物信息 - 建筑物ID: \(structureId), 名称: \(structureInfo.name)")
        return structureInfo
    }
    
    // 清理缓存
    func clearCache() {
        cache.removeAllObjects()
        Logger.debug("已清理建筑物信息缓存")
    }
} 