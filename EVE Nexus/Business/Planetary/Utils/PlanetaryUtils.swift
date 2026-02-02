import Foundation

// 定义行星相关工具类
enum PlanetaryUtils {
    // 行星类型ID到数据库列名的映射
    static let planetTypeToColumn: [Int: String] = [
        11: "temperate", // 温和
        12: "ice", // 冰体
        13: "gas", // 气体
        2014: "oceanic", // 海洋
        2015: "lava", // 熔岩
        2016: "barren", // 贫瘠
        2017: "storm", // 风暴
        2063: "plasma", // 等离子
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
        case 1333: // P0资源
            return 0
        case 1334: // P1资源
            return 1
        case 1335: // P2资源
            return 2
        case 1336: // P3资源
            return 3
        case 1337: // P4资源
            return 4
        default:
            return -1
        }
    }

    /// 根据 groupID 和 en_name 获取设施图标文件名
    /// - Parameters:
    ///   - groupId: 设施的 groupID
    ///   - enName: 设施的英文名称（可选，用于 groupID 1028 的细分判断）
    /// - Returns: 图标文件名（从 asset 中获取）
    static func getFacilityIconName(groupId: Int, enName: String? = nil) -> String {
        switch groupId {
        case 1027:
            return "command"
        case 1028:
            // 根据 en_name 判断工厂类型
            guard let enName = enName else {
                return "process"
            }
            if enName.contains(" Advanced ") {
                return "processadvanced"
            } else if enName.contains(" High-Tech ") {
                return "processhightech"
            } else if enName.contains(" Basic ") {
                return "process"
            } else {
                return "process"
            }
        case 1029:
            return "storage"
        case 1030:
            return "spaceport"
        case 1063:
            return "extractor"
        default:
            // 如果 groupID 不在映射范围内，返回空字符串
            // 调用方需要处理这种情况，可能回退到使用 typeid 对应的图标
            return ""
        }
    }
}
