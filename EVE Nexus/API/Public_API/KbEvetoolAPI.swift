import Foundation

// 战斗记录数据处理类
class KbEvetoolAPI {
    static let shared = KbEvetoolAPI()
    private init() {}

    // 格式化时间 为 UTC+0
    private func formatTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // 格式化价值
    private func formatValue(_ value: Int) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.2fB ISK", Double(value) / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM ISK", Double(value) / 1_000_000)
        } else if value >= 1000 {
            return String(format: "%.2fK ISK", Double(value) / 1000)
        } else {
            return "\(value) ISK"
        }
    }

    // 获取角色战斗记录
    func fetchCharacterKillMails(characterId: Int, page: Int = 1, filter: KillMailFilter = .all)
        async throws -> [String: Any]
    {
        Logger.debug("准备获取角色战斗日志 - 角色ID: \(characterId), 页码: \(page)")

        let url = URL(string: "https://kb.evetools.org/api/v1/killmails")!
        let headers = [
            "Accept-Encoding": "gzip",
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]

        // 构造请求体
        var requestBody: [String: Any] = [
            "charID": characterId,
            "page": page,
        ]

        // 添加过滤参数
        switch filter {
        case .kill:
            requestBody["isKills"] = true
        case .loss:
            requestBody["isLosses"] = true
        case .all:
            break
        }

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)

        // 打印请求体内容
        if let jsonString = String(data: bodyData, encoding: .utf8) {
            Logger.debug("请求体内容: \(jsonString)")
        }

        Logger.debug("开始发送网络请求...")
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            method: "POST",
            body: bodyData,
            headers: headers,
            timeouts: [3, 3, 5, 5, 10]
        )
        Logger.debug("收到网络响应，数据大小: \(data.count) 字节")

        // 解析JSON数据
        guard let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "KbEvetoolAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析JSON失败"]
            )
        }

        return jsonData
    }

    // 获取最近的战斗记录
    public func fetchRecentKillMails(characterId: Int, limit: Int = 5) async throws -> [[String:
        Any]]
    {
        let response = try await fetchCharacterKillMails(characterId: characterId, page: 1)
        guard let records = response["data"] as? [[String: Any]] else {
            return []
        }
        return Array(records.prefix(limit))
    }

    // 获取指定类型的战斗记录（击杀/损失）
    public func fetchKillMailsByType(characterId: Int, page: Int = 1, isKill: Bool) async throws
        -> [[String: Any]]
    {
        let response = try await fetchCharacterKillMails(characterId: characterId, page: page)
        guard let records = response["data"] as? [[String: Any]] else {
            return []
        }

        return records.filter { record in
            if let victim = record["vict"] as? [String: Any],
                let char = victim["char"] as? [String: Any],
                let victimId = char["id"] as? Int
            {
                // 如果受害者是当前角色，则是损失记录；否则是击杀记录
                let isLoss = victimId == characterId
                return isKill ? !isLoss : isLoss
            }
            return false
        }
    }

    // 辅助方法：从记录中获取特定信息
    public func getCharacterInfo(_ record: [String: Any], path: String...) -> (
        id: Int?, name: String?
    ) {
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

    public func getSystemInfo(_ record: [String: Any]) -> (
        name: String?, region: String?, security: String?
    ) {
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

    // 通用搜索方法
    func searchEveItems(characterId _: Int, searchText: String) async throws -> [String:
        [ZKBSearchResult]]
    {
        var result: [String: [ZKBSearchResult]] = [
            "alliance": [],
            "character": [],
            "corporation": [],
            "inventory_type": [],
            "solar_system": [],
            "region": [],
        ]

        // 1. 从本地数据库搜索物品
        let query = """
                SELECT type_id, name, icon_filename
                FROM types
                WHERE name LIKE ?1
                AND categoryID IN (6, 65, 87)
                LIMIT 50
            """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query, parameters: ["%\(searchText)%"]
        ) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let name = row["name"] as? String
                {
                    let imageURL = "https://images.evetech.net/types/\(typeId)/icon?size=64"
                    result["inventory_type"]?.append(
                        ZKBSearchResult(
                            id: typeId,
                            name: name,
                            type: "ship",
                            image: imageURL
                        ))
                }
            }
        }

        // 2. 从 zkillboard 获取在线搜索结果
        guard
            let encodedText = searchText.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://zkillboard.com/autocomplete/\(encodedText)/")
        else {
            throw NSError(
                domain: "KbEvetoolAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的搜索URL"]
            )
        }

        // 发送请求
        let headers = [
            "Accept-Encoding": "gzip",
            "Accept": "application/json",
        ]
        Logger.debug("开始发送zkillboard搜索请求...")
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            headers: headers
        )
        Logger.debug("收到zkillboard响应，数据大小: \(data.count) 字节")

        // 解析 JSON 响应
        guard let zkbResults = try? JSONDecoder().decode([ZKBSearchResult].self, from: data) else {
            throw NSError(
                domain: "KbEvetoolAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析JSON失败"]
            )
        }

        // 根据类型分类结果
        for item in zkbResults {
            switch item.type {
            case "alliance":
                result["alliance"]?.append(item)
            case "character":
                result["character"]?.append(item)
            case "corporation":
                result["corporation"]?.append(item)
            case "ship":
                // 检查是否已存在于本地搜索结果中
                if !result["inventory_type"]!.contains(where: { $0.id == item.id }) {
                    result["inventory_type"]?.append(item)
                }
            case "system":
                result["solar_system"]?.append(item)
            case "region":
                result["region"]?.append(item)
            default:
                break
            }
        }

        return result
    }

    // ZKillboard 搜索结果模型
    struct ZKBSearchResult: Codable {
        let id: Int
        let name: String
        let type: String
        let image: String
    }

    // 根据搜索结果获取战斗日志
    func fetchKillMailsBySearchResult(
        result: SearchResult, page: Int = 1, filter: KillMailFilter = .all
    ) async throws -> [String: Any] {
        Logger.debug("准备获取战斗日志列表 - 类型: \(result.category), ID: \(result.id), 页码: \(page)")

        let url = URL(string: "https://kb.evetools.org/api/v1/killmails")!
        let headers = [
            "Accept-Encoding": "gzip",
            "Accept": "application/json",
            "Content-Type": "application/json",
        ]

        // 根据不同类型构造请求体
        var requestBody: [String: Any] = ["page": page]
        switch result.category {
        case .region:
            requestBody["regionID"] = result.id
        case .character:
            requestBody["charID"] = result.id
        case .inventory_type:
            requestBody["shipID"] = result.id
        case .solar_system:
            requestBody["systemID"] = result.id
        case .corporation:
            requestBody["corpID"] = result.id
        case .alliance:
            requestBody["allyID"] = result.id
        }

        // 添加过滤参数
        switch filter {
        case .kill:
            requestBody["isKills"] = true
        case .loss:
            requestBody["isLosses"] = true
        case .all:
            break
        }

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)

        // 打印请求体内容
        if let jsonString = String(data: bodyData, encoding: .utf8) {
            Logger.debug("请求体内容: \(jsonString)")
        }

        Logger.debug("开始发送网络请求...")
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            method: "POST",
            body: bodyData,
            headers: headers
        )
        Logger.debug("收到网络响应，数据大小: \(data.count) 字节")

        // 解析JSON数据
        guard let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "KbEvetoolAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析JSON失败"]
            )
        }

        return jsonData
    }

    // 根据ID获取完整战斗日志
    func fetchKillMailDetail(killMailId: Int) async throws -> [String: Any] {
        Logger.debug("准备获取战斗日志详情 - ID: \(killMailId)")

        // 获取缓存目录路径
        let fileManager = FileManager.default
        let cacheDirectory = try fileManager.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent("BRKillmails", isDirectory: true)

        // 创建缓存目录(如果不存在)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        let cacheFile = cacheDirectory.appendingPathComponent("\(killMailId).json")

        // 检查本地缓存
        if fileManager.fileExists(atPath: cacheFile.path) {
            Logger.debug("发现本地缓存,读取缓存文件: \(cacheFile.path)")
            let data = try Data(contentsOf: cacheFile)
            if let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Logger.debug("成功读取本地缓存")
                return jsonData
            }
        }

        // 如果没有缓存或缓存无效,从网络获取
        Logger.debug("开始从网络获取战斗日志...")
        let url = URL(string: "https://kb.evetools.org/api/v1/killmails/\(killMailId)")!

        // 添加请求头
        let headers = [
            "Accept-Encoding": "gzip",
            "Accept": "application/json",
        ]

        let data = try await NetworkManager.shared.fetchData(
            from: url,
            headers: headers
        )
        Logger.debug("收到网络响应，数据大小: \(data.count) 字节")

        // 解析JSON数据
        guard let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "KbEvetoolAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析JSON失败"]
            )
        }

        // 将数据写入缓存
        Logger.debug("将数据写入缓存: \(cacheFile.path)")
        try data.write(to: cacheFile)

        return jsonData
    }
}
