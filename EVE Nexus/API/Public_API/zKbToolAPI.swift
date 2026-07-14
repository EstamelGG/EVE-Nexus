import Foundation

/// 战斗记录数据处理类
class zKbToolAPI {
    static let shared = zKbToolAPI()
    private init() {}

    /// 通用搜索方法
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
            FROM types t
            WHERE \(LocalizedText.typeLangNameLikeSQL)
            AND published = 1
            AND categoryID IN (6, 65, 87)
            order by categoryID
            LIMIT 20
        """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            query, parameters: LocalizedText.typeLangNameLikeParams(searchText)
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
                        )
                    )
                }
            }
        }

        // 2. zkillboard 在线自动补全（至少 3 个字符才请求；短关键词仍可使用上方本地舰船搜索）
        if searchText.count >= 3 {
            guard
                let encodedText = searchText.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed
                ),
                let url = URL(string: "https://zkillboard.com/autocomplete/\(encodedText)/")
            else {
                throw NSError(
                    domain: "zkillboard", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "无效的搜索URL"]
                )
            }

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

            guard let zkbResults = try? JSONDecoder().decode([ZKBSearchResult].self, from: data) else {
                throw NSError(
                    domain: "zkillboard", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "解析JSON失败: \(data)"]
                )
            }

            for item in zkbResults {
                switch item.type {
                case "alliance":
                    result["alliance"]?.append(item)
                case "character":
                    result["character"]?.append(item)
                case "corporation":
                    result["corporation"]?.append(item)
                case "ship":
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
        }

        return result
    }

    /// ZKillboard 搜索结果模型
    struct ZKBSearchResult: Codable {
        let id: Int
        let name: String
        let type: String
        let image: String
    }

    /// 从 zkillboard 获取角色战斗记录列表
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

        // 解析 JSON 数据（过滤掉缺少必需字段的条目）
        do {
            // 先解析为 JSON 数组
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NSError(
                    domain: "zkillboard", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "JSON 格式错误：不是数组"]
                )
            }

            // 逐个解码并过滤掉无效条目
            var validEntries: [ZKBKillMailEntry] = []
            for (index, jsonDict) in jsonArray.enumerated() {
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
                    let entry = try JSONDecoder().decode(ZKBKillMailEntry.self, from: jsonData)
                    validEntries.append(entry)
                } catch {
                    Logger.warning("跳过无效的 killmail 条目（索引 \(index)）: \(error.localizedDescription)")
                    continue
                }
            }

            Logger.debug("成功解析 \(validEntries.count) 个有效 killmail 条目（原始 \(jsonArray.count) 个）")
            return validEntries
        } catch {
            Logger.error("解析 zkillboard JSON 失败: \(error)")
            throw NSError(
                domain: "zkillboard", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "解析JSON失败: \(error.localizedDescription)"]
            )
        }
    }

    /// 根据搜索结果从 zkillboard 获取战斗日志列表
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

        // 解析 JSON 数据（过滤掉缺少必需字段的条目）
        do {
            // 先解析为 JSON 数组
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NSError(
                    domain: "zkillboard", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "JSON 格式错误：不是数组"]
                )
            }

            // 逐个解码并过滤掉无效条目
            var validEntries: [ZKBKillMailEntry] = []
            for (index, jsonDict) in jsonArray.enumerated() {
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
                    let entry = try JSONDecoder().decode(ZKBKillMailEntry.self, from: jsonData)
                    validEntries.append(entry)
                } catch {
                    Logger.warning("跳过无效的 killmail 条目（索引 \(index)）: \(error.localizedDescription)")
                    continue
                }
            }

            Logger.debug("成功解析 \(validEntries.count) 个有效 killmail 条目（原始 \(jsonArray.count) 个）")
            return validEntries
        } catch {
            Logger.error("解析 zkillboard JSON 失败: \(error)")
            throw NSError(
                domain: "zkillboard", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "解析JSON失败: \(error.localizedDescription)"]
            )
        }
    }

    /// 根据 killmail ID 从 zkillboard 获取单个战斗日志信息（包含 hash）
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

/// ZKillboard API 响应数据结构（与 KillMailDataConverter 中的定义保持一致）
struct ZKBKillMailEntry: Codable {
    let killmail_id: Int
    let zkb: ZKBInfo

    /// 自定义解码，确保 killmail_id 和 zkb.hash 存在
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // killmail_id 必须存在
        guard let killmailId = try? container.decode(Int.self, forKey: .killmail_id) else {
            throw DecodingError.keyNotFound(
                CodingKeys.killmail_id,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "killmail_id 字段缺失"
                )
            )
        }
        killmail_id = killmailId

        // zkb 必须存在
        let zkbContainer = try container.nestedContainer(keyedBy: ZKBInfoCodingKeys.self, forKey: .zkb)

        // hash 必须存在且不为空
        guard let hash = try? zkbContainer.decode(String.self, forKey: .hash), !hash.isEmpty else {
            throw DecodingError.keyNotFound(
                ZKBInfoCodingKeys.hash,
                DecodingError.Context(
                    codingPath: decoder.codingPath + [CodingKeys.zkb],
                    debugDescription: "zkb.hash 字段缺失或为空"
                )
            )
        }

        // 解码其他可选字段
        zkb = ZKBInfo(
            locationID: try? zkbContainer.decode(Int.self, forKey: .locationID),
            hash: hash,
            fittedValue: try? zkbContainer.decode(Double.self, forKey: .fittedValue),
            droppedValue: try? zkbContainer.decode(Double.self, forKey: .droppedValue),
            destroyedValue: try? zkbContainer.decode(Double.self, forKey: .destroyedValue),
            totalValue: try? zkbContainer.decode(Double.self, forKey: .totalValue),
            points: try? zkbContainer.decode(Int.self, forKey: .points),
            npc: try? zkbContainer.decode(Bool.self, forKey: .npc),
            solo: try? zkbContainer.decode(Bool.self, forKey: .solo),
            awox: try? zkbContainer.decode(Bool.self, forKey: .awox),
            labels: try? zkbContainer.decode([String].self, forKey: .labels)
        )
    }

    /// 定义 CodingKeys
    enum CodingKeys: String, CodingKey {
        case killmail_id
        case zkb
    }

    /// 定义 ZKBInfo 的 CodingKeys（用于嵌套解码）
    enum ZKBInfoCodingKeys: String, CodingKey {
        case locationID
        case hash
        case fittedValue
        case droppedValue
        case destroyedValue
        case totalValue
        case points
        case npc
        case solo
        case awox
        case labels
    }
}

struct ZKBInfo: Codable {
    let locationID: Int?
    let hash: String
    let fittedValue: Double?
    let droppedValue: Double?
    let destroyedValue: Double?
    let totalValue: Double?
    let points: Int?
    let npc: Bool?
    let solo: Bool?
    let awox: Bool?
    let labels: [String]?

    /// 初始化方法（用于自定义解码）
    init(
        locationID: Int? = nil,
        hash: String,
        fittedValue: Double? = nil,
        droppedValue: Double? = nil,
        destroyedValue: Double? = nil,
        totalValue: Double? = nil,
        points: Int? = nil,
        npc: Bool? = nil,
        solo: Bool? = nil,
        awox: Bool? = nil,
        labels: [String]? = nil
    ) {
        self.locationID = locationID
        self.hash = hash
        self.fittedValue = fittedValue
        self.droppedValue = droppedValue
        self.destroyedValue = destroyedValue
        self.totalValue = totalValue
        self.points = points
        self.npc = npc
        self.solo = solo
        self.awox = awox
        self.labels = labels
    }

    /// 提供默认值的计算属性，用于 UI 展示
    var fittedValueValue: Double {
        fittedValue ?? 0
    }

    var droppedValueValue: Double {
        droppedValue ?? 0
    }

    var destroyedValueValue: Double {
        destroyedValue ?? 0
    }

    var totalValueValue: Double {
        totalValue ?? 0
    }
}

extension ZKBKillMailEntry {
    /// 本地已有 ESI 所需的 killmail hash 时构造条目，无需先请求 zkillboard 全量 JSON。
    /// - Parameter storedTotalValue: 收藏等场景下已缓存的 zkill 总价；有值则列表侧可不请求总价。
    /// - Parameter storedDroppedValue / storedDestroyedValue: 收藏缓存的掉落/摧毁估价，供详情等使用。
    init(
        killmailId: Int,
        storedHash: String,
        storedTotalValue: Double? = nil,
        storedDroppedValue: Double? = nil,
        storedDestroyedValue: Double? = nil
    ) {
        killmail_id = killmailId
        zkb = ZKBInfo(
            hash: storedHash,
            droppedValue: storedDroppedValue,
            destroyedValue: storedDestroyedValue,
            totalValue: storedTotalValue
        )
    }
}
