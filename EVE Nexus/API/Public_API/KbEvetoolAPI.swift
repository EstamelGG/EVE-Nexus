import Foundation

// 战斗记录数据处理类
class KbEvetoolAPI {
    static let shared = KbEvetoolAPI()
    private init() {}
    
    // 格式化时间
    private func formatTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    // 格式化价值
    private func formatValue(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB ISK", Double(value) / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM ISK", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK ISK", Double(value) / 1_000)
        } else {
            return "\(value) ISK"
        }
    }
    
    // 获取角色战斗记录
    func fetchCharacterKillMails(characterId: Int, page: Int = 1, isKills: Bool = false, isLosses: Bool = false) async throws -> [String: Any] {
        Logger.debug("准备发送请求 - 角色ID: \(characterId), 页码: \(page), 是否击杀: \(isKills), 是否损失: \(isLosses)")
        
        let url = URL(string: "https://kb.evetools.org/api/v1/killmails")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 构造请求体
        var requestBody: [String: Any] = ["charID": characterId, "page": page]
        if isKills {
            requestBody["isKills"] = true
        }
        if isLosses {
            requestBody["isLosses"] = true
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // 打印请求体内容
        if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
            Logger.debug("请求体内容: \(jsonString)")
        }
        
        Logger.debug("开始发送网络请求...")
        let data = try await NetworkManager.shared.fetchData(from: url, method: "POST", body: request.httpBody)
        Logger.debug("收到网络响应，数据大小: \(data.count) 字节")
        
        // 解析JSON数据
        guard let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "KbEvetoolAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析JSON失败"])
        }
        
        return jsonData
    }
    
    // 获取最近的战斗记录
    public func fetchRecentKillMails(characterId: Int, limit: Int = 5) async throws -> [[String: Any]] {
        let response = try await fetchCharacterKillMails(characterId: characterId, page: 1)
        guard let records = response["data"] as? [[String: Any]] else {
            return []
        }
        return Array(records.prefix(limit))
    }
    
    // 获取指定类型的战斗记录（击杀/损失）
    public func fetchKillMailsByType(characterId: Int, page: Int = 1, isKill: Bool) async throws -> [[String: Any]] {
        let response = try await fetchCharacterKillMails(characterId: characterId, page: page)
        guard let records = response["data"] as? [[String: Any]] else {
            return []
        }
        
        return records.filter { record in
            if let victim = record["vict"] as? [String: Any],
               let char = victim["char"] as? [String: Any],
               let victimId = char["id"] as? Int {
                // 如果受害者是当前角色，则是损失记录；否则是击杀记录
                let isLoss = victimId == characterId
                return isKill ? !isLoss : isLoss
            }
            return false
        }
    }
    
    // 辅助方法：从记录中获取特定信息
    public func getCharacterInfo(_ record: [String: Any], path: String...) -> (id: Int?, name: String?) {
        var current: Any? = record
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        
        guard let charInfo = current as? [String: Any] else {
            return (nil, nil)
        }
        
        return (charInfo["id"] as? Int, charInfo["name"] as? String)
    }
    
    public func getShipInfo(_ record: [String: Any], path: String...) -> (id: Int?, name: String?) {
        var current: Any? = record
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        
        guard let shipInfo = current as? [String: Any] else {
            return (nil, nil)
        }
        
        return (shipInfo["id"] as? Int, shipInfo["name"] as? String)
    }
    
    public func getSystemInfo(_ record: [String: Any]) -> (name: String?, region: String?, security: String?) {
        guard let sysInfo = record["sys"] as? [String: Any] else {
            return (nil, nil, nil)
        }
        
        return (
            sysInfo["name"] as? String,
            sysInfo["region"] as? String,
            sysInfo["ss"] as? String
        )
    }
    
    public func getFormattedTime(_ record: [String: Any]) -> String? {
        guard let timestamp = record["time"] as? Int else {
            return nil
        }
        return formatTime(timestamp)
    }
    
    public func getFormattedValue(_ record: [String: Any]) -> String? {
        guard let value = record["sumV"] as? Int else {
            return nil
        }
        return formatValue(value)
    }
} 
