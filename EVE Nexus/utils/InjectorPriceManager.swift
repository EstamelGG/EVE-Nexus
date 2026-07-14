import Foundation

/// 注入器价格管理器
/// 提供技能注入器价格的加载和缓存功能
public class InjectorPriceManager {
    public static let shared = InjectorPriceManager()

    private var cachedPrices: InjectorPrices?

    private init() {}

    /// 注入器价格结构
    public struct InjectorPrices {
        public let large: Double?
        public let small: Double?

        public init(large: Double?, small: Double?) {
            self.large = large
            self.small = small
        }

        var isComplete: Bool {
            large != nil && small != nil
        }
    }

    /// 返回已缓存的完整价格（若有）
    public func cachedPricesIfValid() -> InjectorPrices? {
        guard let cached = cachedPrices, cached.isComplete else { return nil }
        return cached
    }

    /// 加载注入器价格
    /// - Parameter forceRefresh: 为 true 时忽略缓存并重新请求
    /// - Returns: 包含大型和小型注入器价格的结构体
    public func loadInjectorPrices(forceRefresh: Bool = false) async -> InjectorPrices {
        if !forceRefresh, let cached = cachedPricesIfValid() {
            Logger.debug("使用缓存的注入器价格")
            return cached
        }

        Logger.debug(
            "开始加载注入器价格 - 大型注入器ID: \(SkillInjectorCalculator.largeInjectorTypeId), 小型注入器ID: \(SkillInjectorCalculator.smallInjectorTypeId)"
        )

        let prices = await MarketPriceUtil.getJitaOrderPricesFromESI(typeIds: [
            SkillInjectorCalculator.largeInjectorTypeId,
            SkillInjectorCalculator.smallInjectorTypeId,
        ])

        Logger.debug("获取到价格数据: \(prices)")

        let largePrice = prices[SkillInjectorCalculator.largeInjectorTypeId]
        let smallPrice = prices[SkillInjectorCalculator.smallInjectorTypeId]

        if largePrice == nil || smallPrice == nil {
            Logger.debug(
                "价格数据不完整 - large: \(largePrice as Any), small: \(smallPrice as Any)"
            )
        }

        let result = InjectorPrices(large: largePrice, small: smallPrice)
        if result.isComplete {
            cachedPrices = result
        }
        return result
    }

    /// 计算注入器总价值
    /// - Parameters:
    ///   - calculation: 注入器计算结果
    ///   - prices: 注入器价格
    /// - Returns: 总价值，如果价格不完整则返回nil
    public func calculateTotalCost(
        calculation: InjectorCalculation,
        prices: InjectorPrices
    ) -> Double? {
        guard let largePrice = prices.large,
              let smallPrice = prices.small
        else {
            return nil
        }

        return Double(calculation.largeInjectorCount) * largePrice + Double(
            calculation.smallInjectorCount
        ) * smallPrice
    }
}
