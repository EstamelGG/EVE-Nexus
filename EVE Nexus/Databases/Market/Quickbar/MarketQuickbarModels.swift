import Foundation

/// 市场关注列表项目
struct MarketQuickbar: Identifiable, Codable {
    let id: UUID
    var name: String
    var items: [QuickbarItem] // 存储物品的 typeID 和数量
    var lastUpdated: Date
    var location: MarketLocation // 市场位置（星域或玩家建筑）

    /// 市场地点 ID（正数=星域或星系，负数=建筑虚拟 ID）
    /// JSON 序列化仍使用 "regionID" key 以保持向后兼容
    var locationID: Int {
        get { location.virtualRegionID }
        set { location = MarketLocation(virtualRegionID: newValue) }
    }

    init(
        id: UUID = UUID(), name: String, items: [QuickbarItem] = [],
        locationID: Int = MarketManager.theForgeRegionID // 默认使用 The Forge 星域
    ) {
        self.id = id
        self.name = name
        self.items = items
        lastUpdated = Date()
        location = MarketLocation(virtualRegionID: locationID)
    }

    /// 自定义编码：仅保存 marketLocation 整数（locationID）
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(locationID, forKey: .marketLocation)
    }

    /// 自定义解码：兼容三种历史格式
    /// 1. 新格式：marketLocation 为整数（locationID）
    /// 2. 旧格式：regionID 为整数 + marketLocation 为字符串
    /// 3. 更早格式：仅 marketLocation 为字符串 "region_id:..." / "structure_id:..."
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        items = try container.decode([QuickbarItem].self, forKey: .items)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)

        if let locationID = try? container.decode(Int.self, forKey: .marketLocation) {
            // 新格式：marketLocation 为整数
            location = MarketLocation(virtualRegionID: locationID)
        } else if let regionID = try? container.decode(Int.self, forKey: .regionID) {
            // 旧格式：regionID 为整数
            location = MarketLocation(virtualRegionID: regionID)
        } else if let persisted = try? container.decode(String.self, forKey: .marketLocation),
                  let parsed = MarketLocation(persistedString: persisted)
        {
            // 更早格式：marketLocation 为字符串
            location = parsed
        } else {
            location = .region(MarketManager.theForgeRegionID) // 默认值
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, items, lastUpdated, regionID, marketLocation
    }
}

extension MarketQuickbar {
    /// 与 `MarketQuickbarView` 首页、`MarketQuickbarDestinationPickerView` 共用：先按 `lastUpdated` 升序，相同时按名称、再按 `id`，避免仅依赖目录遍历顺序。
    static func sortedForWatchListHome(_ quickbars: [MarketQuickbar]) -> [MarketQuickbar] {
        quickbars.sorted {
            if $0.lastUpdated != $1.lastUpdated {
                return $0.lastUpdated < $1.lastUpdated
            }
            let nameCmp = $0.name.localizedStandardCompare($1.name)
            if nameCmp != .orderedSame {
                return nameCmp == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

struct QuickbarItem: Codable, Equatable {
    let typeID: Int
    var quantity: Int64 // 使用 Int64 来存储更大的数值

    init(typeID: Int, quantity: Int64 = 1) {
        self.typeID = typeID
        self.quantity = max(1, min(quantity, 999_999_999)) // 限制最大数量为 9.99 亿
    }
}

/// 管理市场关注列表的文件存储
class MarketQuickbarManager {
    static let shared = MarketQuickbarManager()

    private init() {
        createQuickbarDirectory()
    }

    private var quickbarDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("MarketQuickbars", isDirectory: true)
    }

    private func createQuickbarDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: quickbarDirectory, withIntermediateDirectories: true
            )
        } catch {
            Logger.error("创建市场关注列表目录失败: \(error)")
        }
    }

    func saveQuickbar(_ quickbar: MarketQuickbar) {
        let fileName = "market_quickbar_\(quickbar.id).json"
        let fileURL = quickbarDirectory.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
            let data = try encoder.encode(quickbar)
            try data.write(to: fileURL)
            Logger.debug("保存市场关注列表成功: \(fileName)")
        } catch {
            Logger.error("保存市场关注列表失败: \(error)")
        }
    }

    func loadQuickbars() -> [MarketQuickbar] {
        let fileManager = FileManager.default

        do {
            Logger.debug("开始加载市场关注列表")
            let files = try fileManager.contentsOfDirectory(
                at: quickbarDirectory, includingPropertiesForKeys: nil
            )
            Logger.debug("找到文件数量: \(files.count)")

            let quickbars = files.filter { url in
                url.lastPathComponent.hasPrefix("market_quickbar_") && url.pathExtension == "json"
            }.compactMap { url -> MarketQuickbar? in
                do {
                    Logger.debug("尝试解析文件: \(url.lastPathComponent)")
                    let data = try Data(contentsOf: url)

                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                    return try decoder.decode(MarketQuickbar.self, from: data)
                } catch {
                    Logger.error("读取市场关注列表失败: \(error)")
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
            }

            let ordered = MarketQuickbar.sortedForWatchListHome(quickbars)
            Logger.success("成功加载市场关注列表数量: \(ordered.count)")
            return ordered

        } catch {
            Logger.error("读取市场关注列表目录失败: \(error)")
            return []
        }
    }

    func deleteQuickbar(_ quickbar: MarketQuickbar) {
        let fileName = "market_quickbar_\(quickbar.id).json"
        let fileURL = quickbarDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.removeItem(at: fileURL)
            Logger.debug("删除市场关注列表成功: \(fileName)")
        } catch {
            Logger.error("删除市场关注列表失败: \(error)")
        }
    }
}
