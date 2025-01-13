import Foundation

// 战斗记录数据模型
struct KbKillMailInfo: Codable, Identifiable {
    let _id: Int
    let sys: SystemInfo
    let time: Int
    let sumV: Int
    let zkb: KbZkb
    let vict: VictimInfo
    let atts: AttackersInfo
    
    // 添加 Identifiable 协议所需的 id 属性
    var id: Int { _id }
    
    // 添加便利属性
    var formattedTime: String {
        let date = Date(timeIntervalSince1970: TimeInterval(time))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
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
        
        // 添加响应数据的日志
        if let responseString = String(data: data, encoding: .utf8) {
            Logger.debug("收到响应数据: \(responseString.prefix(200))")
        }
        
        do {
            let response = try JSONDecoder().decode(KbKillMailResponse.self, from: data)
            Logger.info("成功获取战斗记录 - 角色ID: \(characterId), 页码: \(page), 记录数量: \(response.data.count)")
            
            // 如果是第一页，且有数据，显示第一条记录的信息
            if page == 1 && !response.data.isEmpty {
                let firstRecord = response.data[0]
                Logger.debug("最新战斗记录 - 时间: \(firstRecord.formattedTime), 星系: \(firstRecord.sys.name), 受害者: \(firstRecord.vict.char.name), 舰船: \(firstRecord.vict.ship.name), 价值: \(firstRecord.formattedValue)")
            }
            
            return response.data
        } catch {
            Logger.error("解析战斗记录失败: \(error)")
            // 添加更详细的错误信息
            if let responseString = String(data: data, encoding: .utf8) {
                Logger.error("原始响应数据: \(responseString)")
            }
            throw error
        }
    }
    
    // 获取最近的战斗记录
    public func fetchRecentKillMails(characterId: Int, limit: Int = 5) async throws -> [KbKillMailInfo] {
        Logger.debug("开始获取最近\(limit)条战斗记录")
        let killmails = try await fetchCharacterKillMails(characterId: characterId, page: 1)
        return Array(killmails.prefix(limit))
    }
    
    // 获取指定时间范围内的战斗记录
    public func fetchKillMailsInRange(characterId: Int, startTime: Date, endTime: Date) async throws -> [KbKillMailInfo] {
        var allKillMails: [KbKillMailInfo] = []
        var currentPage = 1
        let startTimestamp = Int(startTime.timeIntervalSince1970)
        let endTimestamp = Int(endTime.timeIntervalSince1970)
        
        while true {
            let killmails = try await fetchCharacterKillMails(characterId: characterId, page: currentPage)
            guard !killmails.isEmpty else { break }
            
            // 过滤时间范围内的记录
            let filteredKillmails = killmails.filter { killmail in
                killmail.time >= startTimestamp && killmail.time <= endTimestamp
            }
            
            // 如果当前页的所有记录都早于开始时间，说明已经没有更多符合条件的记录了
            if killmails.last?.time ?? 0 < startTimestamp {
                break
            }
            
            allKillMails.append(contentsOf: filteredKillmails)
            currentPage += 1
        }
        
        return allKillMails
    }
    
    // 获取指定类型的战斗记录（击杀/损失）
    public func fetchKillMailsByType(characterId: Int, page: Int = 1, isKill: Bool) async throws -> [KbKillMailInfo] {
        let killmails = try await fetchCharacterKillMails(characterId: characterId, page: page)
        return killmails.filter { killmail in
            // 如果受害者是当前角色，则是损失记录；否则是击杀记录
            let isLoss = killmail.vict.char.id == characterId
            return isKill ? !isLoss : isLoss
        }
    }
    
    // 获取统计信息
    public func fetchKillMailStats(characterId: Int) async throws -> (totalKills: Int, totalLosses: Int, totalValue: Double) {
        var totalKills = 0
        var totalLosses = 0
        var totalValue: Double = 0
        
        let killmails = try await fetchCharacterKillMails(characterId: characterId, page: 1)
        for killmail in killmails {
            if killmail.vict.char.id == characterId {
                totalLosses += 1
            } else {
                totalKills += 1
            }
            totalValue += Double(killmail.sumV)
        }
        
        return (totalKills, totalLosses, totalValue)
    }
} 
