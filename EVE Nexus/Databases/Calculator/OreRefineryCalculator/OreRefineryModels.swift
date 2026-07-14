import SwiftUI

/// 精炼结果数据结构
struct RefineryResultData: Identifiable {
    let id = UUID()
    let outputs: [Int: Int]
    let materialNames: [Int: String]
    let remaining: [Int: Int64]
}

extension OreRefineryCalculatorView {
    /// 订单类型枚举
    enum OrderType: String, CaseIterable {
        case buy = "Main_Market_Order_Buy"
        case sell = "Main_Market_Order_Sell"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    /// 星系安等枚举
    enum SystemSecurity: String, CaseIterable {
        case highSec = "Security_HighSec"
        case lowSec = "Security_LowSec"
        case nullSec = "Security_NullSec"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    /// 建筑枚举
    enum Structure: String, CaseIterable {
        case structure1 = "35835" // 精炼建筑1
        case structure2 = "35836" // 精炼建筑2

        var typeID: Int {
            Int(rawValue) ?? 0
        }

        var displayName: String {
            ItemInfoMap.typeName(for: typeID) ?? "Unknown Structure"
        }
    }

    /// 建筑插件枚举
    enum StructureRigs: String, CaseIterable {
        case none = "Ore_Refinery_Rig_None"
        case t1 = "Ore_Refinery_Rig_T1"
        case t2 = "Ore_Refinery_Rig_T2"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    /// 植入体枚举
    enum Implant: String, CaseIterable {
        case none = "0" // 无植入体
        case implant1 = "27175" // 精炼植入体1
        case implant2 = "27169" // 精炼植入体2
        case implant3 = "27174" // 精炼植入体3

        var typeID: Int {
            Int(rawValue) ?? 0
        }

        var displayName: String {
            if self == .none {
                return NSLocalizedString("Ore_Refinery_Implant_None", comment: "")
            }
            return ItemInfoMap.typeName(for: typeID) ?? "Unknown Implant"
        }
    }

    struct RefineryContext {
        let structureID: Int
        let rigLevel: StructureRigs
        let systemSecurity: SystemSecurity
        let characterSkills: [Int: Int]
        let structure: Structure
    }

    enum RefineryStatus {
        case canRefine(ratio: Double) // 可以精炼，显示比例
        case noOutput // 无精炼产出
        case unknown // 未知状态

        var isRefinable: Bool {
            switch self {
            case .canRefine:
                return true
            default:
                return false
            }
        }

        var displayText: String {
            switch self {
            case let .canRefine(ratio):
                return String(format: "%.1f%%", ratio * 100)
            case .noOutput:
                return NSLocalizedString("Ore_Refinery_No_Output", comment: "")
            case .unknown:
                return NSLocalizedString("Ore_Refinery_Unknown", comment: "")
            }
        }
    }

    /// 物品分类枚举
    enum RefineryItemType {
        case oreAndIce // 矿石与冰矿
        case gas // 压缩气云
        case other // 其他
        case noOutput // 没有精炼产出的物品

        var description: String {
            switch self {
            case .oreAndIce:
                return "矿石与冰矿"
            case .gas:
                return "压缩气云"
            case .other:
                return "其他"
            case .noOutput:
                return "无精炼产出"
            }
        }
    }

    /// 物品分类信息结构
    struct ItemCategoryInfo {
        let typeID: Int
        let categoryID: Int
        let groupID: Int
        let itemType: RefineryItemType
        let reprocessingSkillType: Int? // 矿石和冰矿的专业技能ID
    }
}
