import Foundation

// MARK: - 数据模型

/// 市场价格项数据模型（单个物品的价格信息）
struct MarketPriceValue: Codable {
    let b: Double? // buy 价格（最高买价），可选，缺失时表示0
    let s: Double? // sell 价格（最低卖价），可选，缺失时表示0
}

/// GitHub市场价格数据模型（字典格式，key为typeId字符串）
typealias GitHubMarketPriceData = [String: MarketPriceValue]

// MARK: - GitHub Market Price API

/// GitHub 市场价格数据 API
///
/// 仅从 GitHub Release 获取 Jita 聚合 JSON（及本地文件缓存），**不再**通过 ESI 拉全星域订单在本地构造价表。
/// 数据来源: https://github.com/EstamelGG/EVE_MarketPrice_Fetch
class GitHubMarketPriceAPI {
    static let shared = GitHubMarketPriceAPI()

    /// 供界面提示与错误文案使用（与下载地址一致）
    static let jitaPriceListDownloadURLString =
        "https://github.com/EstamelGG/EVE_MarketPrice_Fetch/releases/download/market-prices/market_prices.json"

    private let cacheTimeoutInterval: TimeInterval = 0.5 * 60 * 60 // 0.5小时缓存有效期（GitHub数据）

    // Documents目录路径
    private var documentsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    // 缓存目录路径
    private var cacheDirectory: URL {
        let directory = documentsDirectory.appendingPathComponent("github_market_cache")

        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                Logger.debug("创建 github_market_cache 目录: \(directory.path)")
            } catch {
                Logger.error("创建 github_market_cache 目录失败: \(error)")
            }
        }

        return directory
    }

    private var cacheFilePath: URL {
        cacheDirectory.appendingPathComponent("market_prices.json")
    }

    private init() {}

    /// 用户可见的失败说明（含清单 URL）
    static func localizedPriceListUnavailableMessage() -> String {
        String(
            format: NSLocalizedString("Error_Jita_Price_List_Unavailable", comment: ""),
            jitaPriceListDownloadURLString
        )
    }

    /// 获取市场价格数据（仅 GitHub Release JSON 或其本地缓存）
    ///
    /// - Parameters:
    ///   - typeIds: 物品ID数组（可选；为 nil 时返回缓存/下载中的全部条目再过滤）
    ///   - forceRefresh: 为 true 时跳过本地缓存，强制重新下载
    /// - Returns: [物品ID: (buy, sell)]
    /// - Throws: 无法从网络或缓存获得有效清单时抛出（`localizedDescription` 已本地化并含 URL）
    func fetchMarketPrices(
        typeIds: [Int]? = nil,
        forceRefresh: Bool = false
    ) async throws -> [Int: (buy: Double, sell: Double)] {
        if !forceRefresh {
            do {
                if let cachedData = try await loadCachedData() {
                    Logger.debug("从GitHub缓存加载市场价格数据，物品数量: \(cachedData.count)")
                    return filterPrices(cachedData, typeIds: typeIds)
                }
            } catch {
                Logger.debug("GitHub缓存不可用: \(error.localizedDescription)")
            }
        }

        Logger.info("开始从 GitHub 获取市场价格数据")
        let startTime = Date()

        do {
            let result = try await fetchFromURL(Self.jitaPriceListDownloadURLString)
            let duration = Date().timeIntervalSince(startTime)
            Logger.success("成功从GitHub获取市场价格数据，物品数量: \(result.count)，耗时: \(String(format: "%.2f", duration))秒")
            return filterPrices(result, typeIds: typeIds)
        } catch {
            Logger.warning("从GitHub获取失败: \(error.localizedDescription)")
            let duration = Date().timeIntervalSince(startTime)
            Logger.error("无法获取 Jita 价格清单，耗时: \(String(format: "%.2f", duration))秒")
            throw NSError(
                domain: "GitHubMarketPriceAPI",
                code: -5,
                userInfo: [
                    NSLocalizedDescriptionKey: Self.localizedPriceListUnavailableMessage(),
                    NSUnderlyingErrorKey: error,
                ]
            )
        }
    }

    private func fetchFromURL(_ urlString: String) async throws -> [Int: (buy: Double, sell: Double)] {
        guard let downloadURL = URL(string: urlString) else {
            throw NSError(
                domain: "GitHubMarketPriceAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无效的下载 URL: \(urlString)"]
            )
        }

        let marketData = try await NetworkManager.shared.fetchData(
            from: downloadURL,
            method: "GET",
            forceRefresh: false,
            timeouts: [5]
        )

        let result = try parseMarketPriceData(from: marketData)
        await saveToCache(data: marketData)
        return result
    }

    private func parseMarketPriceData(from data: Data) throws -> [Int: (buy: Double, sell: Double)] {
        let marketPriceDict = try JSONDecoder().decode(GitHubMarketPriceData.self, from: data)

        var result: [Int: (buy: Double, sell: Double)] = [:]
        for (typeIdString, priceValue) in marketPriceDict {
            guard let typeId = Int(typeIdString) else {
                Logger.warning("无法解析typeId: \(typeIdString)，跳过")
                continue
            }

            let buyPrice = priceValue.b ?? 0.0
            let sellPrice = priceValue.s ?? 0.0

            if buyPrice > 0 || sellPrice > 0 {
                result[typeId] = (buy: buyPrice, sell: sellPrice)
            }
        }

        return result
    }

    private func filterPrices(
        _ prices: [Int: (buy: Double, sell: Double)],
        typeIds: [Int]?
    ) -> [Int: (buy: Double, sell: Double)] {
        guard let typeIds, !typeIds.isEmpty else {
            return prices
        }

        var filtered: [Int: (buy: Double, sell: Double)] = [:]
        for typeId in typeIds {
            if let price = prices[typeId] {
                filtered[typeId] = price
            }
        }
        return filtered
    }

    private func loadCachedData() async throws -> [Int: (buy: Double, sell: Double)]? {
        let filePath = cacheFilePath

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.debug("缓存文件不存在")
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let timeSinceModification = Date().timeIntervalSince(modificationDate)
                if timeSinceModification > cacheTimeoutInterval {
                    Logger.debug("缓存已过期（\(Int(timeSinceModification / 60)) 分钟前），需要重新获取")
                    return nil
                }
            }
        } catch {
            Logger.warning("无法读取缓存文件属性: \(error.localizedDescription)")
            return nil
        }

        let data = try Data(contentsOf: filePath)
        let result = try parseMarketPriceData(from: data)

        Logger.debug("从缓存 \(filePath) 加载了 \(result.count) 个物品的价格数据")
        return result
    }

    private func saveToCache(data: Data) async {
        let filePath = cacheFilePath

        do {
            try data.write(to: filePath)
            Logger.debug("市场价格数据已保存到缓存: \(filePath.path)")
        } catch {
            Logger.error("保存缓存文件失败: \(error.localizedDescription)")
        }
    }
}
