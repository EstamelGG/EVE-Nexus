import Foundation

/// 市场价格数据结构体
/// // 包含CCP官方提供的两种价格估算：
/// - adjustedPrice: 调整价格，用于工业税费、合同抵押等游戏机制计算
/// - averagePrice: 平均价格，用于一般价值估算
struct MarketPriceData {
    let adjustedPrice: Double // 调整价格（用于税费计算）
    let averagePrice: Double // 平均价格（用于价值估算）
}

/// 市场价格工具类 - 提供EIV价格和便捷的市场价格查询
/// // 价格数据来源：
/// - EIV价格：来自 https://esi.evetech.net/markets/prices/（CCP官方统计数据）
/// - Jita 订单价：`getJitaOrderPricesFromGitHubList` 仅使用 GitHub Release 清单；`getJitaOrderPricesFromESI` 按 type 拉 Forge 订单算 Jita 4-4（装配、属性对比等）
/// // 使用场景：
/// - 精炼税费计算：使用 adjustedPrice
/// - 合同估价：使用实时订单价格
/// - 技能注入器价格：使用Jita卖价
enum MarketPriceUtil {
    // 获取多个物品的EIV价格数据（CCP官方估价）
    //     // 使用场景：
    // - 精炼税费计算：使用 adjustedPrice 计算税额
    // - 工业成本估算：使用 adjustedPrice 作为基础成本
    // - 合同抵押计算：使用 adjustedPrice
    //     // 示例：
    // ```swift
    // // 获取精炼产出材料的EIV价格，用于计算税费
    // let eivPrices = await MarketPriceUtil.getMarketPrices(
    //     typeIds: [34, 35, 36]  // 三钛合金、类晶体胶矿、类银超金属
    // )
    //     // // 计算税额
    // var totalEIV = 0.0
    // for (materialID, quantity) in refineryOutputs {
    //     if let priceData = eivPrices[materialID] {
    //         totalEIV += priceData.adjustedPrice * Double(quantity)
    //     }
    // }
    // let taxAmount = totalEIV * (taxRate / 100.0)
    // ```
    //     // 数据特点：
    // - 数据来源：CCP官方统计，每日更新
    // - 缓存时间：8小时
    // - 覆盖范围：几乎所有可交易物品
    //     // - Parameters:
    //   - typeIds: 物品ID数组
    //   - forceRefresh: 是否强制刷新缓存，默认false（使用8小时缓存）
    // - Returns: [物品ID: 价格数据]，如果某个物品没有价格数据则不会包含在结果中
    static func getMarketPrices(typeIds: [Int], forceRefresh: Bool = false) async -> [Int:
        MarketPriceData]
    {
        do {
            // 先尝试从缓存获取价格
            let prices = try await MarketPricesAPI.shared.fetchMarketPrices(
                forceRefresh: forceRefresh
            )
            Logger.debug("从缓存获取市场价格数据，总条目数: \(prices.count)")

            // 创建结果字典
            var result: [Int: MarketPriceData] = [:]

            // 从缓存中查找价格
            for price in prices {
                if typeIds.contains(price.type_id) {
                    // 如果adjusted_price不存在则设为0，如果average_price不存在则设为0
                    let adjustedPrice = price.adjusted_price ?? 0.0
                    let averagePrice = price.average_price ?? 0.0

                    result[price.type_id] = MarketPriceData(
                        adjustedPrice: adjustedPrice,
                        averagePrice: averagePrice
                    )
                }
            }

            return result
        } catch {
            Logger.error("获取市场价格失败: \(error)")
            return [:]
        }
    }

    /// 使用 GitHub 预加载的 Jita 聚合清单取价（LP 商店、建筑溢价等）。
    /// 预加载数据可用时直接使用；不可用时（预加载失败或尚未完成）回退到 ESI 调用。
    /// - Returns: [物品ID: Jita价格]；清单中无数据的 type 不会出现在结果字典里
    static func getJitaOrderPricesFromGitHubList(
        typeIds: [Int],
        orderType: OrderType = .sell,
        forceRefresh: Bool = false
    ) async -> [Int: Double] {
        guard !typeIds.isEmpty else { return [:] }

        // 检查预加载数据是否可用
        if let aggregates = GitHubMarketPriceAPI.shared.preloadedPrices(typeIds: typeIds) {
            let result = aggregates.compactMapValues { (buy: Double, sell: Double) -> Double? in
                let price = orderType == .buy ? buy : sell
                return price > 0 ? price : nil
            }
            Logger.debug("使用 GitHub 预加载数据获取 \(result.count)/\(typeIds.count) 个物品的\(orderType == .buy ? "买" : "卖")价")
            return result
        }

        // 预加载数据不可用，回退到 ESI
        Logger.info("GitHub 预加载数据不可用，使用 ESI 获取 Jita 价格")
        return await getJitaOrderPricesFromESI(
            typeIds: typeIds,
            orderType: orderType,
            forceRefresh: forceRefresh
        )
    }

    /// 按物品从 ESI 拉 Forge 订单，计算 Jita 4-4 价（装配价格、属性对比、技能注入器等）。**不使用** GitHub 清单。
    ///     // - Returns: [物品ID: Jita价格]，无订单的物品不会包含在结果中
    static func getJitaOrderPricesFromESI(
        typeIds: [Int],
        orderType: OrderType = .sell,
        forceRefresh: Bool = false
    ) async -> [Int: Double] {
        guard !typeIds.isEmpty else { return [:] }

        let regionID = MarketManager.theForgeRegionID // The Forge (Jita所在星域)
        let systemID = 30_000_142 // Jita星系ID
        let stationID = 60_003_760 // Jita 4-4 空间站 ID

        // 使用通用工具类并发获取市场订单
        let marketOrders = await MarketOrdersUtil.loadRegionOrders(
            typeIds: typeIds,
            regionID: regionID,
            forceRefresh: forceRefresh
        )

        // 使用函数式编程批量计算价格
        return marketOrders.compactMapValues { orders in
            let price = MarketOrdersUtil.calculatePrice(
                from: orders,
                orderType: orderType,
                quantity: nil,
                systemId: systemID,
                stationID: stationID
            ).price
            return (price ?? 0) > 0 ? price : nil
        }
    }
}
