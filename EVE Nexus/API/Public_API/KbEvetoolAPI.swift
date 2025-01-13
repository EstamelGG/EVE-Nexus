import Foundation

// 战斗记录数据模型
struct KbKillMailInfo: Codable, Identifiable {
    let _id: Int
    let time: Int
    let sumV: Int  // 损失价值
    let sys: SystemInfo
    let vict: VictimInfo
    let zkb: KbZkb
    
    var id: Int { _id }
    
    // 格式化时间
    var formattedTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    // 格式化价值
    var formattedValue: String {
        if sumV >= 1_000_000_000 {
            return String(format: "%.1fB ISK", Double(sumV) / 1_000_000_000)
        } else if sumV >= 1_000_000 {
            return String(format: "%.1fM ISK", Double(sumV) / 1_000_000)
        } else if sumV >= 1_000 {
            return String(format: "%.1fK ISK", Double(sumV) / 1_000)
        } else {
            return "\(sumV) ISK"
        }
    }
    
    // 星系信息
    struct SystemInfo: Codable {
        let name: String      // 星系名
        let region: String    // 星域名
        let ss: String       // 安全等级
    }
    
    // 受害者信息
    struct VictimInfo: Codable {
        let char: CharacterInfo
        let ship: ShipInfo
        let ally: AllianceInfo?
    }
    
    // 角色信息
    struct CharacterInfo: Codable {
        let id: Int
        let name: String
    }
    
    // 舰船信息
    struct ShipInfo: Codable {
        let id: Int
        let name: String
    }
    
    // 联盟信息
    struct AllianceInfo: Codable {
        let id: Int
        let name: String
    }
    
    // ZKillboard 相关信息
    struct KbZkb: Codable {
        let npc: Bool    // 是否为 NPC 击杀
        let solo: Bool   // 是否为单人击杀
    }
}

// API响应模型
struct KbKillMailResponse: Codable {
    let data: [KbKillMailInfo]
    let page: Int
    let totalPages: Int
    let totalCount: Int
}

class KbEvetoolAPI {
    static let shared = KbEvetoolAPI()
    private init() {}
    
    // 获取角色战斗记录
    public func fetchCharacterKillMails(characterId: Int, page: Int = 1) async throws -> KbKillMailResponse {
        Logger.debug("准备发送请求 - 角色ID: \(characterId), 页码: \(page)")
        
        let url = URL(string: "https://kb.evetools.org/api/v1/killmails")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 构造请求体
        let requestBody: [String: Any] = ["charID": characterId, "page": page]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        Logger.debug("开始发送网络请求...")
        let data = try await NetworkManager.shared.fetchData(from: url, method: "POST", body: request.httpBody)
        Logger.debug("收到网络响应，数据大小: \(data.count) 字节")
        
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(KbKillMailResponse.self, from: data)
            Logger.info("成功获取战斗记录 - 页码: \(page)/\(response.totalPages), 记录数: \(response.data.count)")
            return response
        } catch {
            Logger.error("解析战斗记录失败: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.error("原始响应数据: \(responseString)")
            }
            throw error
        }
    }
    
    // 获取最近的战斗记录
    public func fetchRecentKillMails(characterId: Int, limit: Int = 5) async throws -> [KbKillMailInfo] {
        let response = try await fetchCharacterKillMails(characterId: characterId, page: 1)
        return Array(response.data.prefix(limit))
    }
    
    // 获取指定类型的战斗记录（击杀/损失）
    public func fetchKillMailsByType(characterId: Int, page: Int = 1, isKill: Bool) async throws -> [KbKillMailInfo] {
        let response = try await fetchCharacterKillMails(characterId: characterId, page: page)
        return response.data.filter { killmail in
            // 如果受害者是当前角色，则是损失记录；否则是击杀记录
            let isLoss = killmail.vict.char.id == characterId
            return isKill ? !isLoss : isLoss
        }
    }
} 
