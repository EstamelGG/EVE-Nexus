import SwiftUI

// MARK: - 缓存刷新状态枚举

enum CacheRefreshStatus {
    case validNotRefreshable // 缓存有效，不可更新（距离上次更新不足20分钟）
    case validRefreshable // 缓存有效，可更新（距离上次更新超过20分钟）
    case invalidRefreshable // 缓存无效，可更新（缓存已过期或不存在）
}

// MARK: - 市场订单类型枚举

enum MarketOrderType: Equatable {
    case buy
    case sell
}

// MARK: - 物品订单信息数据模型

struct ItemOrderInfo: Identifiable, Hashable {
    let id: Int // typeId
    let typeId: Int
    let name: String
    let iconFileName: String
    let orderCount: Int
    let orderType: MarketOrderType // 订单类型：buy 或 sell

    /// Hashable 实现
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(orderType)
    }

    /// Equatable 实现
    static func == (lhs: ItemOrderInfo, rhs: ItemOrderInfo) -> Bool {
        return lhs.id == rhs.id && lhs.orderType == rhs.orderType
    }
}

// MARK: - 目录订单数据模型

struct CategoryOrderData: Identifiable {
    let id: Int // categoryID
    let name: String
    let orderCount: Int
    let iconFileName: String

    init(id: Int, name: String, orderCount: Int, iconFileName: String = IconManager.defaultIcon) {
        self.id = id
        self.name = name
        self.orderCount = orderCount
        self.iconFileName = iconFileName
    }
}

// MARK: - 组订单数据模型

struct GroupOrderData: Identifiable {
    let id: Int // groupID
    let name: String
    let orderCount: Int
    let iconFileName: String
}

// MARK: - 分组物品数据模型

struct GroupItemInfo: Identifiable {
    var id: Int {
        typeId
    } // typeId
    let typeId: Int
    let name: String
    let iconFileName: String
    let orderCount: Int
    let totalVolume: Int
    let structurePrice: Double? // 建筑价格（卖单最低价，买单最高价）
    var jitaPrice: Double? // Jita价格
    var structureId: Int64? // 建筑ID，用于导航到建筑市场
}

// MARK: - 目录饼图切片数据模型

struct CategoryPieSlice: Identifiable {
    let id: Int
    let name: String
    let orderCount: Int
    let percentage: Double
    let startAngle: Double
    let endAngle: Double
    let color: Color
}

// MARK: - 分组饼图切片数据模型

struct GroupPieSlice: Identifiable {
    let id: Int
    let name: String
    let orderCount: Int
    let percentage: Double
    let startAngle: Double
    let endAngle: Double
    let color: Color
}
