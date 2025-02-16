import Foundation

/// 商品类型
struct CommodityType: Hashable {
    /// 商品ID
    let id: Int
    
    /// 商品体积
    let volume: Float
    
    /// 图标ID
    let iconId: Int
    
    // MARK: - Initialization
    
    init(id: Int, volume: Float, iconId: Int? = nil) {
        self.id = id
        self.volume = volume
        self.iconId = iconId ?? id // 如果没有指定图标ID，使用商品ID作为图标ID
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CommodityType, rhs: CommodityType) -> Bool {
        return lhs.id == rhs.id
    }
} 
