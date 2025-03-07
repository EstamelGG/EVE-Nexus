//
//  LocationTypes.swift
//  EVE Nexus
//
//  Created by GG Estamel on 2025/3/4.
//
// 添加位置类型枚举

enum LocationType {
    case solarSystem  // 30000000...39999999
    case station  // 60000000...63999999
    case structure  // >= 100000000
    case unknown

    static func from(id: Int64) -> LocationType {
        let type: LocationType =
            switch id {
            case 30_000_000...39_999_999:
                .solarSystem
            case 60_000_000...63_999_999:
                .station
            case 100_000_000...:
                .structure
            default:
                .unknown
            }
        Logger.debug("位置ID类型判断 - ID: \(id), 类型: \(type)")
        return type
    }
}
