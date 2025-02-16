import Foundation

public struct CharacterMarketOrder: Identifiable, Codable, Hashable {
    public let duration: Int
    public let escrow: Double?
    public let isBuyOrder: Bool?
    public let isCorporation: Bool
    public let issued: String
    public let locationId: Int64
    public let minVolume: Int?
    public let orderId: Int64
    public let price: Double
    public let range: String
    public let regionId: Int64
    public let typeId: Int64
    public let volumeRemain: Int
    public let volumeTotal: Int
    
    public enum CodingKeys: String, CodingKey {
        case duration
        case escrow
        case isBuyOrder = "is_buy_order"
        case isCorporation = "is_corporation"
        case issued
        case locationId = "location_id"
        case minVolume = "min_volume"
        case orderId = "order_id"
        case price
        case range
        case regionId = "region_id"
        case typeId = "type_id"
        case volumeRemain = "volume_remain"
        case volumeTotal = "volume_total"
    }
    
    public var id: Int64 { orderId }
    
    public var isSellOrder: Bool {
        return !(isBuyOrder ?? false)
    }
    
    // 实现 Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(orderId)
    }
    
    public static func == (lhs: CharacterMarketOrder, rhs: CharacterMarketOrder) -> Bool {
        return lhs.orderId == rhs.orderId
    }
} 