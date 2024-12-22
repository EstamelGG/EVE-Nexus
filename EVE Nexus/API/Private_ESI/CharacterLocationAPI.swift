import Foundation

// 角色位置信息模型
struct CharacterLocation: Codable {
    let solar_system_id: Int
    let structure_id: Int?
    let station_id: Int?
    
    var locationStatus: LocationStatus {
        if station_id != nil {
            return .inStation
        } else if structure_id != nil {
            return .inStructure
        } else {
            return .inSpace
        }
    }
    
    enum LocationStatus: String, Codable {
        case inStation
        case inStructure
        case inSpace
        
        var description: String {
            switch self {
            case .inStation:
                return "(\(NSLocalizedString("Character_in_station", comment: "")))"
            case .inStructure:
                return "(\(NSLocalizedString("Character_in_structure", comment: "")))"
            case .inSpace:
                return "(\(NSLocalizedString("Character_in_space", comment: "")))"
            }
        }
    }
}

class CharacterLocationAPI {
    static let shared = CharacterLocationAPI()
    
    private init() {}
    
    // 获取角色位置信息
    func fetchCharacterLocation(characterId: Int) async throws -> CharacterLocation {
        let urlString = "https://esi.evetech.net/latest/characters/\(characterId)/location/"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )
        
        do {
            return try JSONDecoder().decode(CharacterLocation.self, from: data)
        } catch {
            Logger.error("解析角色位置信息失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
    
    // 获取角色完整位置信息（包含星系名称等）
    func fetchCharacterLocationInfo(characterId: Int, databaseManager: DatabaseManager) async throws -> SolarSystemInfo? {
        let location = try await fetchCharacterLocation(characterId: characterId)
        return await getSolarSystemInfo(solarSystemId: location.solar_system_id, databaseManager: databaseManager)
    }
} 
