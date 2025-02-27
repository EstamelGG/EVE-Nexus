import Foundation

/// 殖民地概览
struct ColonyOverview {
    /// 该殖民地生产的最终产品（不被该殖民地消耗的产品）
    let finalProducts: Set<Type>
    
    /// 最终产品存储设施的总容量
    let capacity: Int
    
    /// 最终产品存储设施中其他商品占用的容量
    let otherUsedCapacity: Double
    
    /// 最终产品存储设施中最终产品占用的容量
    let finalProductsUsedCapacity: Double
}

/// 获取殖民地概览
/// - Parameters:
///   - routes: 路由列表
///   - pins: 设施列表
/// - Returns: 殖民地概览
func getColonyOverview(routes: [Route], pins: [Pin]) -> ColonyOverview {
    // 获取最终产品
    let finalProducts = getFinalProducts(pins: pins)
    
    // 获取最终产品目的地ID
    let finalProductDestinationIds = routes
        .filter { finalProducts.contains($0.type) }
        .map { $0.destinationPinId }
        .unique()
    
    // 获取最终产品存储设施
    let finalProductStoragePins = pins.filter { pin in
        finalProductDestinationIds.contains(pin.id)
    }
    
    // 计算总容量
    var totalCapacity = 0
    for pin in finalProductStoragePins {
        if let capacity = getCapacity(for: pin) {
            totalCapacity += capacity
        }
    }
    
    // 计算其他商品占用的容量
    var totalOtherUsedCapacity = 0.0
    for pin in finalProductStoragePins {
        for (type, quantity) in pin.contents {
            if !finalProducts.contains(type) {
                totalOtherUsedCapacity += Double(type.volume) * Double(quantity)
            }
        }
    }
    
    // 计算最终产品占用的容量
    var totalFinalProductsUsedCapacity = 0.0
    for pin in finalProductStoragePins {
        for (type, quantity) in pin.contents {
            if finalProducts.contains(type) {
                totalFinalProductsUsedCapacity += Double(type.volume) * Double(quantity)
            }
        }
    }
    
    return ColonyOverview(
        finalProducts: finalProducts,
        capacity: totalCapacity,
        otherUsedCapacity: totalOtherUsedCapacity,
        finalProductsUsedCapacity: totalFinalProductsUsedCapacity
    )
}

/// 获取最终产品
/// - Parameter pins: 设施列表
/// - Returns: 最终产品集合
private func getFinalProducts(pins: [Pin]) -> Set<Type> {
    let producing = getProducing(pins: pins)
    let extracting = getExtracting(pins: pins)
    let allProduced = producing.union(extracting)
    
    let consuming = getConsuming(pins: pins)
    
    return allProduced.subtracting(consuming)
}

/// 获取生产的产品
/// - Parameter pins: 设施列表
/// - Returns: 生产的产品集合
private func getProducing(pins: [Pin]) -> Set<Type> {
    var producedTypes = Set<Type>()
    
    for pin in pins {
        if let factory = pin as? Pin.Factory, let schematic = factory.schematic {
            producedTypes.insert(schematic.outputType)
        }
    }
    
    return producedTypes
}

/// 获取采集的产品
/// - Parameter pins: 设施列表
/// - Returns: 采集的产品集合
private func getExtracting(pins: [Pin]) -> Set<Type> {
    var extractedTypes = Set<Type>()
    
    for pin in pins {
        if let extractor = pin as? Pin.Extractor, let productType = extractor.productType {
            extractedTypes.insert(productType)
        }
    }
    
    return extractedTypes
}

/// 获取消耗的产品
/// - Parameter pins: 设施列表
/// - Returns: 消耗的产品集合
private func getConsuming(pins: [Pin]) -> Set<Type> {
    var consumedTypes = Set<Type>()
    
    for pin in pins {
        if let factory = pin as? Pin.Factory, let schematic = factory.schematic {
            for (inputType, _) in schematic.inputs {
                consumedTypes.insert(inputType)
            }
        }
    }
    
    return consumedTypes
}

extension Array where Element: Hashable {
    /// 获取唯一元素
    func unique() -> [Element] {
        return Array(Set(self))
    }
} 