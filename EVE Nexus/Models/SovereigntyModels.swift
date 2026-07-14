import Foundation
import SwiftUI

// MARK: - 主权战役数据模型

public struct SovereigntyCampaign: Codable {
    public let attackers_score: Float?
    public let campaign_id: Int
    public let constellation_id: Int
    public let defender_id: Int
    public let defender_score: Float?
    public let event_type: String
    public let solar_system_id: Int
    public let start_time: String
    public let structure_id: Int64
}

// MARK: - 主权数据模型

public struct SovereigntyData: Codable {
    public let systemId: Int
    public let allianceId: Int?
    public let corporationId: Int?
    public let factionId: Int?

    public enum CodingKeys: String, CodingKey {
        case systemId = "system_id"
        case allianceId = "alliance_id"
        case corporationId = "corporation_id"
        case factionId = "faction_id"
    }
}

// MARK: - 主权势力信息模型

struct SovereigntyInfo: Identifiable {
    let id: Int
    let names: LocalizedText
    let icon: Image?
    let systemCount: Int
    let isAlliance: Bool // true为联盟，false为派系

    var name: String {
        names.resolved()
    }

    func matches(_ query: String) -> Bool {
        names.matchesSearch(query)
    }
}
