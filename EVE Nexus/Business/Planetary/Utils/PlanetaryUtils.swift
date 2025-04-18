import Foundation

// 定义行星相关工具类
enum PlanetaryUtils {
    // 行星类型ID到数据库列名的映射
    static let planetTypeToColumn: [Int: String] = [
        11: "temperate",  // 温和
        12: "ice",  // 冰体
        13: "gas",  // 气体
        2014: "oceanic",  // 海洋
        2015: "lava",  // 熔岩
        2016: "barren",  // 贫瘠
        2017: "storm",  // 风暴
        2063: "plasma",  // 等离子
    ]

    // 数据库列名到行星类型ID的映射
    static let columnToPlanetType: [String: Int] = {
        var result: [String: Int] = [:]
        for (key, value) in planetTypeToColumn {
            result[value] = key
        }
        return result
    }()

    // 根据marketGroupId确定资源等级
    static func determineResourceLevel(marketGroupId: Int) -> Int {
        switch marketGroupId {
        case 1333:  // P0资源
            return 0
        case 1334:  // P1资源
            return 1
        case 1335:  // P2资源
            return 2
        case 1336:  // P3资源
            return 3
        case 1337:  // P4资源
            return 4
        default:
            return -1
        }
    }
}
