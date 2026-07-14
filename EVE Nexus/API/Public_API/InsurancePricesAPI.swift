import Foundation

// MARK: - 保险价格数据模型

struct InsuranceLevel: Codable {
    let cost: Double
    let payout: Double
    let name: String

    /// 获取本地化的保险等级名称
    var localizedName: String {
        // 映射ESI返回的保险等级名称到本地化字符串键（不区分大小写）
        let levelKeyMap: [String: String] = [
            "platinum": "Insurance_Level_Platinum",
            "gold": "Insurance_Level_Gold",
            "silver": "Insurance_Level_Silver",
            "bronze": "Insurance_Level_Bronze",
            "standard": "Insurance_Level_Standard",
            "basic": "Insurance_Level_Basic",
        ]

        // 查找匹配的本地化键，不区分大小写
        let lowercasedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let localizationKey = levelKeyMap[lowercasedName] {
            return NSLocalizedString(localizationKey, comment: name)
        }

        // 如果没有找到匹配项，返回原始名称
        return name
    }
}

struct InsurancePriceItem: Codable {
    let typeId: Int
    let levels: [InsuranceLevel]

    enum CodingKeys: String, CodingKey {
        case typeId = "type_id"
        case levels
    }
}

// MARK: - 保险价格API

actor InsurancePricesAPI {
    static let shared = InsurancePricesAPI()

    private let baseURL = "https://esi.evetech.net/latest/insurance/prices/"
    private let cacheDirectory: URL
    private let cacheFileName = "insurance_prices.json"
    private let cacheValidityDuration: TimeInterval = 3600 * 8 // 8小时

    private var cachedData: [InsurancePriceItem]?
    private var lastFetchTime: Date?

    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsPath.appendingPathComponent("Insurance")

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - 公开方法

    /// 获取保险价格数据
    /// - Parameter forceRefresh: 是否强制刷新缓存
    /// - Returns: 保险价格数据数组
    func fetchInsurancePrices(forceRefresh: Bool = false) async throws -> [InsurancePriceItem] {
        // 检查是否需要刷新
        if !forceRefresh, let cached = cachedData, let lastFetch = lastFetchTime {
            let timeSinceLastFetch = Date().timeIntervalSince(lastFetch)
            if timeSinceLastFetch < cacheValidityDuration {
                Logger.debug("使用内存缓存的保险价格数据")
                return cached
            }
        }

        // 尝试从文件缓存加载
        if !forceRefresh, let fileData = loadFromFileCache() {
            Logger.debug("使用文件缓存的保险价格数据")
            cachedData = fileData
            lastFetchTime = Date()
            return fileData
        }

        // 从网络获取
        Logger.info("开始获取保险价格数据")
        let data = try await fetchFromNetwork()

        // 保存到内存和文件缓存
        cachedData = data
        lastFetchTime = Date()
        saveToFileCache(data)

        Logger.success("保险价格数据获取完成，共\(data.count)种飞船")
        return data
    }

    /// 获取指定飞船的保险价格
    /// - Parameter typeId: 飞船类型ID
    /// - Returns: 保险价格数据，如果不存在则返回nil
    func getInsurancePrice(for typeId: Int) async throws -> InsurancePriceItem? {
        let allPrices = try await fetchInsurancePrices()
        return allPrices.first { $0.typeId == typeId }
    }

    // MARK: - 私有方法

    private func fetchFromNetwork() async throws -> [InsurancePriceItem] {
        guard let url = URL(string: baseURL) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([InsurancePriceItem].self, from: data)
        } catch {
            Logger.error("解析保险价格数据失败: \(error)")
            throw NetworkError.decodingError(error)
        }
    }

    private func loadFromFileCache() -> [InsurancePriceItem]? {
        let cacheFile = cacheDirectory.appendingPathComponent(cacheFileName)

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            return nil
        }

        // 检查文件修改时间
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modificationDate = attributes[.modificationDate] as? Date
        else {
            return nil
        }

        let timeSinceModification = Date().timeIntervalSince(modificationDate)
        if timeSinceModification > cacheValidityDuration {
            Logger.debug("保险价格文件缓存已过期")
            return nil
        }

        // 读取并解析文件
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            return try decoder.decode([InsurancePriceItem].self, from: data)
        } catch {
            Logger.error("读取保险价格缓存文件失败: \(error)")
            return nil
        }
    }

    private func saveToFileCache(_ data: [InsurancePriceItem]) {
        let cacheFile = cacheDirectory.appendingPathComponent(cacheFileName)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: cacheFile)
            Logger.debug("保险价格数据已保存到文件缓存")
        } catch {
            Logger.error("保存保险价格缓存文件失败: \(error)")
        }
    }
}
