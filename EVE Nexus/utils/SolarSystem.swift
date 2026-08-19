
//  SolarSystem.swift
//  EVE Panel

//  Created by GG Estamel on 2024/12/16.

import Foundation
import SwiftUI

/// 位置信息数据结构（名称从 SDEMemoryStore 动态解析，跟随语言切换）
public final class SolarSystemInfo: Codable {
    let systemId: Int
    let security: Double
    let constellationId: Int
    let regionId: Int

    var systemName: String {
        SDEMemoryStore.solarSystemName(for: systemId) ?? "System \(systemId)"
    }

    var constellationName: String {
        SDEMemoryStore.constellationName(for: constellationId) ?? "Constellation \(constellationId)"
    }

    var regionName: String {
        SDEMemoryStore.regionName(for: regionId) ?? "Region \(regionId)"
    }

    init(systemId: Int, security: Double, constellationId: Int, regionId: Int) {
        self.systemId = systemId
        self.security = security
        self.constellationId = constellationId
        self.regionId = regionId
    }
}

/// 计算显示用的安全等级
func calculateDisplaySecurity(_ trueSec: Double) -> Double {
    if trueSec > 0.0 && trueSec < 0.05 {
        return 0.1 // 0.0到0.05之间向上取整到0.1
    }
    return round(trueSec * 10) / 10 // 其他情况四舍五入到小数点后一位
}

/// 格式化安全等级显示
func formatSystemSecurity(_ trueSec: Double) -> String {
    let displaySec = calculateDisplaySecurity(trueSec)
    return String(format: "%.1f", displaySec)
}

/// 获取安全等级对应的颜色
func getSecurityColor(_ trueSec: Double) -> Color {
    let displaySec = calculateDisplaySecurity(trueSec)
    switch displaySec {
    case 1.0:
        return Color(red: 65 / 255, green: 115 / 255, blue: 212 / 255) // 深蓝色
    case 0.9:
        return Color(red: 85 / 255, green: 152 / 255, blue: 229 / 255) // 中蓝色
    case 0.8:
        return Color(red: 115 / 255, green: 203 / 255, blue: 244 / 255) // 浅蓝色
    case 0.7:
        return Color(red: 129 / 255, green: 216 / 255, blue: 169 / 255) // 浅绿色
    case 0.6, 0.5:
        return Color(red: 143 / 255, green: 225 / 255, blue: 103 / 255) // 绿色
    case 0.4, 0.3:
        return Color(red: 208 / 255, green: 113 / 255, blue: 45 / 255) // 橙色
    case 0.2, 0.1:
        return Color(red: 188 / 255, green: 17 / 255, blue: 23 / 255) // 深红色
    case ...0.0:
        return Color(red: 130 / 255, green: 55 / 255, blue: 97 / 255) // 负数安全等级显示为紫色
    default:
        return .red // 其他情况显示为红色
    }
}

/// 获取星系位置信息
func getSolarSystemInfo(solarSystemId: Int, databaseManager: DatabaseManager) async
    -> SolarSystemInfo?
{
    let universeQuery = """
        SELECT region_id, constellation_id, system_security
        FROM universe
        WHERE solarsystem_id = ?
    """

    guard
        case let .success(rows) = databaseManager.executeQuery(
            universeQuery, parameters: [solarSystemId]
        ),
        let row = rows.first,
        let security = row["system_security"] as? Double,
        let constellationId = row["constellation_id"] as? Int,
        let regionId = row["region_id"] as? Int
    else {
        return nil
    }

    return SolarSystemInfo(
        systemId: solarSystemId,
        security: security,
        constellationId: constellationId,
        regionId: regionId
    )
}

/// 批量获取星系位置信息
func getBatchSolarSystemInfo(solarSystemIds: [Int], databaseManager: DatabaseManager) async
    -> [Int: SolarSystemInfo]
{
    if solarSystemIds.isEmpty {
        return [:]
    }

    let uniqueSortedIds = Array(Set(solarSystemIds)).sorted()
    let placeholders = String(repeating: "?,", count: uniqueSortedIds.count).dropLast()

    let universeQuery = """
        SELECT solarsystem_id, region_id, constellation_id, system_security
        FROM universe
        WHERE solarsystem_id IN (\(placeholders))
    """

    let parameters = uniqueSortedIds.map { $0 as Any }

    guard
        case let .success(rows) = databaseManager.executeQuery(
            universeQuery, parameters: parameters
        )
    else {
        return [:]
    }

    var result: [Int: SolarSystemInfo] = [:]

    for row in rows {
        guard
            let systemId = row["solarsystem_id"] as? Int,
            let security = row["system_security"] as? Double,
            let constellationId = row["constellation_id"] as? Int,
            let regionId = row["region_id"] as? Int
        else {
            continue
        }

        result[systemId] = SolarSystemInfo(
            systemId: systemId,
            security: security,
            constellationId: constellationId,
            regionId: regionId
        )
    }

    return result
}

/// 简化的星系信息结构，用于快速查询（名称从 SDEMemoryStore 动态解析）
public struct SimpleSystemInfo {
    let systemId: Int
    let security: Double?

    var name: String? {
        SDEMemoryStore.solarSystemName(for: systemId)
    }
}

/// 获取简化的星系信息（同步版本，内存索引）
func getSystemInfo(systemId: Int, databaseManager _: DatabaseManager) -> SimpleSystemInfo {
    let security = SDEMemoryStore.universeSystems[systemId]?.security
    return SimpleSystemInfo(systemId: systemId, security: security)
}

/// 星系安全类别枚举
public enum SecurityClass {
    case highSec // 高安
    case lowSec // 低安
    case nullSecOrWH // 0.0或虫洞
}

/// 根据安全等级判断星系安全类别（0.0 属于 0.0/虫洞，低安为 0.1–0.4）
func getSecurityClass(trueSec: Double) -> SecurityClass {
    let displaySec = calculateDisplaySecurity(trueSec)

    if displaySec >= 0.5 {
        return .highSec
    } else if displaySec >= 0.1 {
        return .lowSec
    } else {
        return .nullSecOrWH
    }
}
