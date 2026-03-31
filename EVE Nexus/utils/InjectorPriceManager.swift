import Foundation

/// 注入器价格管理器
/// 提供技能注入器价格的加载和缓存功能
public class InjectorPriceManager {
    public static let shared = InjectorPriceManager()

    private init() {}

    /// 注入器价格结构
    public struct InjectorPrices {
        public let large: Double?
        public let small: Double?

        public init(large: Double?, small: Double?) {
            self.large = large
            self.small = small
        }
    }

    /// 加载注入器价格
    /// - Returns: 包含大型和小型注入器价格的结构体
    public func loadInjectorPrices() async -> InjectorPrices {
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

        return InjectorPrices(large: largePrice, small: smallPrice)
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
            calculation.smallInjectorCount) * smallPrice
    }
}
