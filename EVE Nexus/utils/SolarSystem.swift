//
//  SolarSystem.swift
//  EVE Panel
//
//  Created by GG Estamel on 2024/12/16.
//

import Foundation
import SwiftUI

// 位置信息数据结构
public final class SolarSystemInfo: Codable {
    public let systemId: Int
    public let systemName: String
    public let security: Double
    public let constellationId: Int
    public let constellationName: String
    public let regionId: Int
    public let regionName: String

    public init(
        systemId: Int, systemName: String, security: Double, constellationId: Int,
        constellationName: String, regionId: Int, regionName: String
    ) {
        self.systemId = systemId
        self.systemName = systemName
        self.security = security
        self.constellationId = constellationId
        self.constellationName = constellationName
        self.regionId = regionId
        self.regionName = regionName
    }
}

// 计算显示用的安全等级
func calculateDisplaySecurity(_ trueSec: Double) -> Double {
    if trueSec > 0.0 && trueSec < 0.05 {
        return 0.1  // 0.0到0.05之间向上取整到0.1
    }
    return round(trueSec * 10) / 10  // 其他情况四舍五入到小数点后一位
}

// 格式化安全等级显示
func formatSystemSecurity(_ trueSec: Double) -> String {
    let displaySec = calculateDisplaySecurity(trueSec)
    return String(format: "%.1f", displaySec)
}

// 获取安全等级对应的颜色
func getSecurityColor(_ trueSec: Double) -> Color {
    let displaySec = calculateDisplaySecurity(trueSec)
    switch displaySec {
    case 1.0:
        return Color(red: 65 / 255, green: 115 / 255, blue: 212 / 255)  // 深蓝色
    case 0.9:
        return Color(red: 85 / 255, green: 154 / 255, blue: 239 / 255)  // 中蓝色
    case 0.8:
        return Color(red: 114 / 255, green: 204 / 255, blue: 237 / 255)  // 浅蓝色
    case 0.7:
        return Color(red: 129 / 255, green: 216 / 255, blue: 169 / 255)  // 浅绿色
    case 0.6, 0.5:
        return Color(red: 143 / 255, green: 225 / 255, blue: 103 / 255)  // 绿色
    case 0.4, 0.3, 0.2, 0.1:
        return Color(red: 208 / 255, green: 113 / 255, blue: 45 / 255)  // 橙色
    case ..<0.0:
        return .red  // 负数安全等级显示为红色
    default:
        return .red  // 其他情况显示为红色
    }
}

// 获取星系位置信息
func getSolarSystemInfo(solarSystemId: Int, databaseManager: DatabaseManager) async
    -> SolarSystemInfo?
{
    let useEnglishSystemNames = UserDefaults.standard.bool(forKey: "useEnglishSystemNames")

    // 执行查询
    let universeQuery = """
            SELECT u.region_id, u.constellation_id, u.system_security,
                   s.solarSystemName, s.solarSystemName_en,
                   c.constellationName, c.constellationName_en,
                   r.regionName, r.regionName_en
            FROM universe u
            JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
            JOIN constellations c ON c.constellationID = u.constellation_id
            JOIN regions r ON r.regionID = u.region_id
            WHERE u.solarsystem_id = ?
        """

    guard
        case let .success(rows) = databaseManager.executeQuery(
            universeQuery, parameters: [solarSystemId]
        ),
        let row = rows.first,
        let security = row["system_security"] as? Double,
        let systemNameLocal = row["solarSystemName"] as? String,
        let systemNameEn = row["solarSystemName_en"] as? String,
        let constellationId = row["constellation_id"] as? Int,
        let constellationNameLocal = row["constellationName"] as? String,
        let constellationNameEn = row["constellationName_en"] as? String,
        let regionId = row["region_id"] as? Int,
        let regionNameLocal = row["regionName"] as? String,
        let regionNameEn = row["regionName_en"] as? String
    else {
        return nil
    }

    let systemName = useEnglishSystemNames ? systemNameEn : systemNameLocal
    let constellationName = useEnglishSystemNames ? constellationNameEn : constellationNameLocal
    let regionName = useEnglishSystemNames ? regionNameEn : regionNameLocal

    let solarSystemInfo = SolarSystemInfo(
        systemId: solarSystemId,
        systemName: systemName,
        security: security,
        constellationId: constellationId,
        constellationName: constellationName,
        regionId: regionId,
        regionName: regionName
    )

    return solarSystemInfo
}

// 批量获取星系位置信息
func getBatchSolarSystemInfo(solarSystemIds: [Int], databaseManager: DatabaseManager) async
    -> [Int: SolarSystemInfo]
{
    // 如果传入的数组为空，直接返回空字典
    if solarSystemIds.isEmpty {
        return [:]
    }

    // 去重并排序
    let uniqueSortedIds = Array(Set(solarSystemIds)).sorted()

    let useEnglishSystemNames = UserDefaults.standard.bool(forKey: "useEnglishSystemNames")

    // 构建IN查询的参数字符串
    let placeholders = String(repeating: "?,", count: uniqueSortedIds.count).dropLast()

    // 执行批量查询
    let universeQuery = """
            SELECT u.solarsystem_id, u.region_id, u.constellation_id, u.system_security,
                   s.solarSystemName, s.solarSystemName_en,
                   c.constellationName, c.constellationName_en,
                   r.regionName, r.regionName_en
            FROM universe u
            JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
            JOIN constellations c ON c.constellationID = u.constellation_id
            JOIN regions r ON r.regionID = u.region_id
            WHERE u.solarsystem_id IN (\(placeholders))
        """

    // 将ID数组转换为Any类型数组，以便传递给executeQuery
    let parameters = uniqueSortedIds.map { $0 as Any }

    guard
        case let .success(rows) = databaseManager.executeQuery(
            universeQuery, parameters: parameters
        )
    else {
        return [:]
    }

    // 创建结果字典
    var result: [Int: SolarSystemInfo] = [:]

    // 处理每一行结果
    for row in rows {
        guard
            let systemId = row["solarsystem_id"] as? Int,
            let security = row["system_security"] as? Double,
            let systemNameLocal = row["solarSystemName"] as? String,
            let systemNameEn = row["solarSystemName_en"] as? String,
            let constellationId = row["constellation_id"] as? Int,
            let constellationNameLocal = row["constellationName"] as? String,
            let constellationNameEn = row["constellationName_en"] as? String,
            let regionId = row["region_id"] as? Int,
            let regionNameLocal = row["regionName"] as? String,
            let regionNameEn = row["regionName_en"] as? String
        else {
            continue
        }

        let systemName = useEnglishSystemNames ? systemNameEn : systemNameLocal
        let constellationName = useEnglishSystemNames ? constellationNameEn : constellationNameLocal
        let regionName = useEnglishSystemNames ? regionNameEn : regionNameLocal

        let solarSystemInfo = SolarSystemInfo(
            systemId: systemId,
            systemName: systemName,
            security: security,
            constellationId: constellationId,
            constellationName: constellationName,
            regionId: regionId,
            regionName: regionName
        )

        result[systemId] = solarSystemInfo
    }

    return result
}
