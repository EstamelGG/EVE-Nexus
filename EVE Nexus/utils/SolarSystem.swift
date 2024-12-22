//
//  SecurtiyColor.swift
//  EVE Nexus
//
//  Created by GG Estamel on 2024/12/16.
//

import SwiftUI

// 位置信息数据结构
public struct SolarSystemInfo: Codable {
    public let systemId: Int
    public let systemName: String
    public let security: Double
    public let constellationId: Int
    public let constellationName: String
    public let regionId: Int
    public let regionName: String
    
    public init(systemId: Int, systemName: String, security: Double, constellationId: Int, constellationName: String, regionId: Int, regionName: String) {
        self.systemId = systemId
        self.systemName = systemName
        self.security = security
        self.constellationId = constellationId
        self.constellationName = constellationName
        self.regionId = regionId
        self.regionName = regionName
    }
}

// 向下取整安全等级
func truncateSecurity(_ security: Double) -> Double {
    return floor(security * 10) / 10
}

// 格式化安全等级显示
func formatSecurity(_ security: Double) -> String {
    return String(format: "%.1f", truncateSecurity(security))
}

// 获取安全等级对应的颜色
func getSecurityColor(_ security: Double) -> Color {
    let truncatedSecurity = truncateSecurity(security)
    switch truncatedSecurity {
    case ...1.0 where truncatedSecurity > 0.9:
        return Color(red: 65/255, green: 115/255, blue: 212/255)
    case ...0.9 where truncatedSecurity > 0.8:
        return Color(red: 85/255, green: 154/255, blue: 239/255)
    case ...0.8 where truncatedSecurity > 0.7:
        return Color(red: 114/255, green: 204/255, blue: 237/255)
    case ...0.7 where truncatedSecurity > 0.6:
        return Color(red: 129/255, green: 216/255, blue: 169/255)
    case ...0.6 where truncatedSecurity > 0.4:
        return Color(red: 143/255, green: 225/255, blue: 103/255)
    case ...0.4 where truncatedSecurity > 0.0:
        return Color(red: 208/255, green: 113/255, blue: 45/255)
    default:
        return .red
    }
}

// 获取星系位置信息
func getSolarSystemInfo(solarSystemId: Int, databaseManager: DatabaseManager) async -> SolarSystemInfo? {
    let universeQuery = """
            SELECT u.region_id, u.constellation_id, u.system_security,
                   s.solarSystemName, c.constellationName, r.regionName
            FROM universe u
            JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
            JOIN constellations c ON c.constellationID = u.constellation_id
            JOIN regions r ON r.regionID = u.region_id
            WHERE u.solarsystem_id = ?
        """
    
    guard case .success(let rows) = databaseManager.executeQuery(universeQuery, parameters: [solarSystemId]),
          let row = rows.first,
          let security = row["system_security"] as? Double,
          let systemName = row["solarSystemName"] as? String,
          let constellationId = row["constellation_id"] as? Int,
          let constellationName = row["constellationName"] as? String,
          let regionId = row["region_id"] as? Int,
          let regionName = row["regionName"] as? String else {
        return nil
    }
    
    return SolarSystemInfo(
        systemId: solarSystemId,
        systemName: systemName,
        security: security,
        constellationId: constellationId,
        constellationName: constellationName,
        regionId: regionId,
        regionName: regionName
    )
}
