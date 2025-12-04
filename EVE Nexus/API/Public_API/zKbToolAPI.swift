import Foundation

// 战斗记录数据处理类
class zKbToolAPI {
    static let shared = zKbToolAPI()
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

    func getShipInfo(_ record: [String: Any], path: String...) -> (id: Int?, name: String?) {
        var current: Any? = record
        for key in path {
            current = (current as? [String: Any])?[key]
        }

        guard let shipInfo = current as? [String: Any] else {
            return (nil, nil)
        }

        return (shipInfo["id"] as? Int, shipInfo["name"] as? String)
    }

    func getSystemInfo(_ record: [String: Any]) -> (
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

    func getFormattedTime(_ record: [String: Any]) -> String? {
        guard let timestamp = record["time"] as? Int else {
            return nil
        }
        return formatTime(timestamp)
    }

    func getFormattedValue(_ record: [String: Any]) -> String? {
        guard let value = record["sumV"] as? Int else {
            return nil
        }
        return FormatUtil.formatISK(Double(value))
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
            WHERE (name LIKE ?1 OR en_name like ?1)
            AND published = 1
            AND categoryID IN (6, 65, 87)
            order by categoryID
            LIMIT 20
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
                domain: "zkillboard", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的搜索URL"]
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
                domain: "zkillboard", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "解析JSON失败: \(data)"]
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

    // 从 zkillboard 获取角色战斗记录列表
    func fetchZKBCharacterKillMails(characterId: Int, page: Int = 1, filter: KillMailFilter = .all)
        async throws -> [ZKBKillMailEntry]
    {
        Logger.debug("准备从 zkillboard 获取角色战斗日志 - 角色ID: \(characterId), 页码: \(page), 过滤: \(filter)")

        let urlString: String
        switch filter {
        case .kill:
            urlString = "https://zkillboard.com/api/kills/characterID/\(characterId)/page/\(page)/"
        case .loss:
            urlString = "https://zkillboard.com/api/losses/characterID/\(characterId)/page/\(page)/"
        case .all:
            urlString = "https://zkillboard.com/api/characterID/\(characterId)/page/\(page)/"
        }

        guard let url = URL(string: urlString) else {
            throw NSError(
                domain: "zkillboard", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的 URL: \(urlString)"]
            )
        }

        let headers = [
            "Accept-Encoding": "gzip",
            "Accept": "application/json",
            "User-Agent": "Tritanium Maintainer: tritanium_support@icloud.com",
        ]

        Logger.debug("开始发送 zkillboard 网络请求...")
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            headers: headers,
            timeouts: [3, 3, 5, 5, 10]
        )
        Logger.debug("收到 zkillboard 响应，数据大小: \(data.count) 字节")

        // 解析 JSON 数据
        do {
            let entries = try JSONDecoder().decode([ZKBKillMailEntry].self, from: data)
            Logger.debug("成功解析 \(entries.count) 个 killmail 条目")
            return entries
        } catch {
            Logger.error("解析 zkillboard JSON 失败: \(error)")
            throw NSError(
                domain: "zkillboard", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "解析JSON失败: \(error.localizedDescription)"]
            )
        }
    }

    // 根据搜索结果从 zkillboard 获取战斗日志列表
    func fetchZKBKillMailsBySearchResult(
        result: SearchResult, page: Int = 1, filter: KillMailFilter = .all
    ) async throws -> [ZKBKillMailEntry] {
        Logger.debug("准备从 zkillboard 获取战斗日志列表 - 类型: \(result.category), ID: \(result.id), 页码: \(page), 过滤: \(filter)")

        // 根据类别确定 API 路径
        let typePath: String
        switch result.category {
        case .character:
            typePath = "characterID"
        case .corporation:
            typePath = "corporationID"
        case .alliance:
            typePath = "allianceID"
        case .inventory_type:
            typePath = "shipTypeID"
        case .solar_system:
            typePath = "systemID"
        case .region:
            typePath = "regionID"
        }

        // 根据过滤条件构造 URL
        let urlString: String
        switch filter {
        case .kill:
            urlString = "https://zkillboard.com/api/kills/\(typePath)/\(result.id)/page/\(page)/"
        case .loss:
            urlString = "https://zkillboard.com/api/losses/\(typePath)/\(result.id)/page/\(page)/"
        case .all:
            urlString = "https://zkillboard.com/api/\(typePath)/\(result.id)/page/\(page)/"
        }

        guard let url = URL(string: urlString) else {
            throw NSError(
                domain: "zkillboard", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的 URL: \(urlString)"]
            )
        }

        let headers = [
            "Accept-Encoding": "gzip",
            "Accept": "application/json",
            "User-Agent": "Tritanium Maintainer: tritanium_support@icloud.com",
        ]

        Logger.debug("开始发送 zkillboard 搜索请求...")
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            headers: headers,
            timeouts: [3, 3, 5, 5, 10]
        )
        Logger.debug("收到 zkillboard 响应，数据大小: \(data.count) 字节")

        // 解析 JSON 数据
        do {
            let entries = try JSONDecoder().decode([ZKBKillMailEntry].self, from: data)
            Logger.debug("成功解析 \(entries.count) 个 killmail 条目")
            return entries
        } catch {
            Logger.error("解析 zkillboard JSON 失败: \(error)")
            throw NSError(
                domain: "zkillboard", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "解析JSON失败: \(error.localizedDescription)"]
            )
        }
    }

    // 根据 killmail ID 从 zkillboard 获取单个战斗日志信息（包含 hash）
    func fetchZKBKillMailByID(killmailId: Int) async throws -> ZKBKillMailEntry {
        Logger.debug("准备从 zkillboard 获取战斗日志 - killmail_id: \(killmailId)")

        let urlString = "https://zkillboard.com/api/kills/killID/\(killmailId)/"

        guard let url = URL(string: urlString) else {
            throw NSError(
                domain: "zkillboard", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的 URL: \(urlString)"]
            )
        }

        let headers = [
            "Accept-Encoding": "gzip",
            "Accept": "application/json",
            "User-Agent": "Tritanium Maintainer: tritanium_support@icloud.com",
        ]

        Logger.debug("开始发送 zkillboard 网络请求...")
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            headers: headers,
            timeouts: [3, 3, 5, 5, 10]
        )
        Logger.debug("收到 zkillboard 响应，数据大小: \(data.count) 字节")

        // 解析 JSON 数据（返回的是数组，取第一个元素）
        do {
            let entries = try JSONDecoder().decode([ZKBKillMailEntry].self, from: data)
            guard let entry = entries.first else {
                throw NSError(
                    domain: "zkillboard", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "未找到 killmail_id: \(killmailId) 的数据"]
                )
            }
            Logger.debug("成功获取 killmail 信息 - killmail_id: \(killmailId), hash: \(entry.zkb.hash)")
            return entry
        } catch {
            Logger.error("解析 zkillboard JSON 失败: \(error)")
            throw NSError(
                domain: "zkillboard", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "解析JSON失败: \(error.localizedDescription)"]
            )
        }
    }
}

// ZKillboard API 响应数据结构（与 KillMailDataConverter 中的定义保持一致）
struct ZKBKillMailEntry: Codable {
    let killmail_id: Int
    let zkb: ZKBInfo
}

struct ZKBInfo: Codable {
    let locationID: Int
    let hash: String
    let fittedValue: Double
    let droppedValue: Double
    let destroyedValue: Double
    let totalValue: Double
    let points: Int
    let npc: Bool
    let solo: Bool
    let awox: Bool
    let labels: [String]
}
