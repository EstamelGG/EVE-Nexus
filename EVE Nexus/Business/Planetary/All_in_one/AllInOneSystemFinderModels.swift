import Foundation

// 选中的产品信息
struct SelectedProduct: Identifiable, Hashable {
    let id: Int
    let name: String
    let iconFileName: String
    let productLevel: Int
    let compatiblePlanetTypes: [AllInOnePlanetTypeInfo]
    
    init(from result: AllInOneSinglePlanetProductResult) {
        self.id = result.productId
        self.name = result.productName
        self.iconFileName = result.iconFileName
        self.productLevel = result.productLevel
        self.compatiblePlanetTypes = result.compatiblePlanetTypes
    }
    
    // 实现 Equatable
    static func == (lhs: SelectedProduct, rhs: SelectedProduct) -> Bool {
        return lhs.id == rhs.id
    }
    
    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// 星系结果
struct AllInOneSystemResult: Identifiable {
    let id: Int
    let systemId: Int
    let systemName: String
    let regionId: Int
    let regionName: String
    let security: Double
    let score: Double
    let productSupport: [Int: ProductSupportInfo] // [productId: support info]
    let planetTypeSummary: [PlanetTypeSummary]
}

// 产品支持信息
struct ProductSupportInfo {
    let productId: Int
    let productName: String
    let canSupport: Bool
    let availablePlanetCount: Int
    let requiredPlanetTypes: [Int] // 该产品需要的行星类型ID
    let supportingPlanetTypes: [Int] // 该星系中支持该产品的行星类型ID
}

// 行星类型汇总
struct PlanetTypeSummary {
    let typeId: Int
    let typeName: String
    let iconFileName: String
    let count: Int
    let usedByProducts: [Int] // 哪些产品会使用这种行星类型
}

// 多产品需求分析结果
struct MultiProductRequirement {
    let selectedProducts: [SelectedProduct]
    let planetTypeRequirements: [Int: Int] // [planetTypeId: minimumCount]
    let conflictResolution: ConflictResolution
}

// 冲突解决方案
struct ConflictResolution {
    let sharedPlanetTypes: [Int] // 可以被多个产品共享的行星类型
    let dedicatedPlanetTypes: [Int: [Int]] // [planetTypeId: [productIds]] 需要专用行星的类型
    let minimumPlanetRequirements: [Int: Int] // [planetTypeId: minimumCount] 最小行星需求
}

// 系统评分计算器的配置
struct SystemScoringConfig {
    let baseScorePerPlanet: Double = 10.0
    let balanceBonus: Double = 50.0
    let allProductsSupportedBonus: Double = 100.0
    let multiPlanetTypeBonus: Double = 25.0
} 
