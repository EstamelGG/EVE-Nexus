import Foundation

// 战斗记录数据模型
struct KbKillMailInfo: Codable {
    let _id: Int
    let sys: SystemInfo
    let time: Int
    let sumV: Int
    let zkb: KbZkb
    let vict: VictimInfo
    let atts: AttackersInfo
    
    struct SystemInfo: Codable {
        let name: String
        let region: String
        let ss: String
        let id: Int
        let regionId: Int
    }
    
    struct KbZkb: Codable {
        let npc: Bool
        let solo: Bool
    }
    
    struct EntityInfo: Codable {
        let id: Int
        let name: String
    }
    
    struct VictimInfo: Codable {
        let ally: EntityInfo?
        let corp: EntityInfo
        let char: EntityInfo
        let ship: EntityInfo
        let fctn: Int
    }
    
    struct AttackerInfo: Codable {
        let ally: EntityInfo?
        let corp: EntityInfo
        let char: EntityInfo
        let ship: EntityInfo
        let weap: EntityInfo
        let fctn: Int
        let dmg: Int
        let blow: Bool
    }
    
    struct AttackersInfo: Codable {
        let blow: AttackerInfo
        let count: Int
    }
}

// API响应模型
struct KbKillMailResponse: Codable {
    let data: [KbKillMailInfo]
}

class KbEvetoolAPI {
    static let shared = KbEvetoolAPI()
    private init() {}
    
    // 获取角色战斗记录
    public func fetchCharacterKillMails(characterId: Int, page: Int = 1) async throws -> [KbKillMailInfo] {
        let url = URL(string: "https://kb.evetools.org/api/v1/killmails")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 构造请求体
        let requestBody: [String: Any] = ["charID": characterId, "page": page]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        Logger.debug("开始获取第 \(page) 页数据")
        let data = try await NetworkManager.shared.fetchData(from: url, method: "POST", body: request.httpBody)
        
        do {
            let response = try JSONDecoder().decode(KbKillMailResponse.self, from: data)
            Logger.info("成功获取战斗记录 - 角色ID: \(characterId), 页码: \(page), 记录数量: \(response.data.count)")
            
            // 如果是第一页，且有数据，显示第一条记录的信息
            if page == 1 && !response.data.isEmpty {
                let firstRecord = response.data[0]
                Logger.debug("最新战斗记录 - 时间: \(firstRecord.time), 星系: \(firstRecord.sys.name), 受害者: \(firstRecord.vict.char.name), 舰船: \(firstRecord.vict.ship.name)")
            }
            
            return response.data
        } catch {
            Logger.error("解析战斗记录失败: \(error)")
            throw error
        }
    }
    
    // 获取最近的战斗记录
    public func fetchRecentKillMails(characterId: Int, limit: Int = 5) async throws -> [KbKillMailInfo] {
        Logger.debug("开始获取最近\(limit)条战斗记录")
        let killmails = try await fetchCharacterKillMails(characterId: characterId, page: 1)
        return Array(killmails.prefix(limit))
    }
} 