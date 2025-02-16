import Foundation

/// 市场价格工具类
struct MarketPriceUtil {
    /// 获取多个物品的市场预估价格
    /// - Parameter typeIds: 物品ID数组
    /// - Returns: [物品ID: 预估价格] 的字典，如果某个物品没有价格数据则不会包含在结果中
    static func getMarketPrices(typeIds: [Int]) async -> [Int: Double] {
        do {
            // 先尝试从缓存获取价格
            let prices = try await CharacterDataService.shared.getMarketPrices()
            Logger.debug("从缓存获取市场价格数据，总条目数: \(prices.count)")
            
            // 创建结果字典
            var result: [Int: Double] = [:]
            
            // 记录未找到价格的物品ID
            var missingTypeIds: Set<Int> = Set(typeIds)
            
            // 从缓存中查找价格
            for price in prices {
                if typeIds.contains(price.type_id),
                   let averagePrice = price.average_price {
                    result[price.type_id] = averagePrice
                    missingTypeIds.remove(price.type_id)
                }
            }
            
            // 如果有物品未找到价格，尝试重新获取市场数据
            if !missingTypeIds.isEmpty {
                Logger.debug("以下物品未找到价格，尝试重新获取: \(missingTypeIds)")
                do {
                    // 强制刷新市场数据
                    let newPrices = try await MarketPricesAPI.shared.fetchMarketPrices(forceRefresh: true)
                    
                    // 从新数据中查找缺失的价格
                    for price in newPrices {
                        if missingTypeIds.contains(price.type_id),
                           let averagePrice = price.average_price {
                            result[price.type_id] = averagePrice
                            missingTypeIds.remove(price.type_id)
                        }
                    }
                    
                    if !missingTypeIds.isEmpty {
                        Logger.debug("以下物品仍未找到价格: \(missingTypeIds)")
                    }
                } catch {
                    Logger.error("重新获取市场数据失败: \(error)")
                }
            }
            
            return result
        } catch {
            Logger.error("获取市场价格失败: \(error)")
            return [:]
        }
    }
    
    /// 获取单个物品的市场预估价格
    /// - Parameter typeId: 物品ID
    /// - Returns: 预估价格，如果没有价格数据则返回nil
    static func getMarketPrice(typeId: Int) async -> Double? {
        let prices = await getMarketPrices(typeIds: [typeId])
        return prices[typeId]
    }
} 