import Foundation

struct StructureInfoResponse: Codable {
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
}

@MainActor
class StructureInfoAPI {
    static let shared = StructureInfoAPI()
    private var cache: [Int: StructureInfoResponse] = [:]
    
    private init() {}
    
    func fetchStructureInfo(structureId: Int, characterId: Int) async throws -> StructureInfoResponse {
        // 检查缓存
        if let cachedInfo = cache[structureId] {
            Logger.debug("使用缓存的建筑物信息 - 建筑物ID: \(structureId)")
            return cachedInfo
        }
        
        // 构建URL
        let urlString = "https://esi.evetech.net/latest/universe/structures/\(structureId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            Logger.error("无效的建筑物URL: \(urlString)")
            throw NetworkError.invalidURL
        }
        
        do {
            Logger.debug("开始获取建筑物信息 - 建筑物ID: \(structureId)")
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url,
                characterId: characterId
            )
            let structureInfo = try JSONDecoder().decode(StructureInfoResponse.self, from: data)
            
            // 保存到缓存
            cache[structureId] = structureInfo
            
            Logger.debug("成功获取建筑物信息 - 建筑物ID: \(structureId), 名称: \(structureInfo.name)")
            return structureInfo
            
        } catch {
            Logger.error("获取建筑物信息失败 - 建筑物ID: \(structureId), 错误: \(error)")
            throw error
        }
    }
    
    func clearCache() {
        cache.removeAll()
        Logger.debug("已清除建筑物信息缓存")
    }
} 