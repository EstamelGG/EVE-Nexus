import SwiftUI

enum FittingSlotType: String, CaseIterable {
    case subSystemSlots = "SubSystemSlots"
    case hiSlots = "HiSlots"
    case medSlots = "MedSlots"
    case loSlots = "LoSlots"
    case rigSlots = "RigSlots"
    case t3dModeSlot = "T3DModeSlot"

    var localizedName: String {
        switch self {
        case .subSystemSlots:
            return NSLocalizedString("Location_Flag_SubSystemSlots", comment: "")
        case .hiSlots:
            return NSLocalizedString("Location_Flag_HiSlots", comment: "")
        case .medSlots:
            return NSLocalizedString("Location_Flag_MedSlots", comment: "")
        case .loSlots:
            return NSLocalizedString("Location_Flag_LoSlots", comment: "")
        case .rigSlots:
            return NSLocalizedString("Location_Flag_RigSlots", comment: "")
        case .t3dModeSlot:
            return NSLocalizedString("Location_Flag_T3DModeSlot", comment: "")
        }
    }

    /// 获取指定索引的槽位flag标识
    func getSlotFlag(index: Int) -> FittingFlag {
        switch self {
        case .hiSlots:
            switch index {
            case 0: return .hiSlot0
            case 1: return .hiSlot1
            case 2: return .hiSlot2
            case 3: return .hiSlot3
            case 4: return .hiSlot4
            case 5: return .hiSlot5
            case 6: return .hiSlot6
            case 7: return .hiSlot7
            default: return .invalid
            }
        case .medSlots:
            switch index {
            case 0: return .medSlot0
            case 1: return .medSlot1
            case 2: return .medSlot2
            case 3: return .medSlot3
            case 4: return .medSlot4
            case 5: return .medSlot5
            case 6: return .medSlot6
            case 7: return .medSlot7
            default: return .invalid
            }
        case .loSlots:
            switch index {
            case 0: return .loSlot0
            case 1: return .loSlot1
            case 2: return .loSlot2
            case 3: return .loSlot3
            case 4: return .loSlot4
            case 5: return .loSlot5
            case 6: return .loSlot6
            case 7: return .loSlot7
            default: return .invalid
            }
        case .rigSlots:
            switch index {
            case 0: return .rigSlot0
            case 1: return .rigSlot1
            case 2: return .rigSlot2
            default: return .invalid
            }
        case .subSystemSlots:
            switch index {
            case 0: return .subSystemSlot0
            case 1: return .subSystemSlot1
            case 2: return .subSystemSlot2
            case 3: return .subSystemSlot3
            default: return .invalid
            }
        case .t3dModeSlot:
            return .t3dModeSlot0 // T3D模式的flag
        }
    }
}

/// 装备分组数据结构
struct ModuleGroup: Identifiable {
    /// 稳定标识（用于折叠/展开动画时的行匹配）：模块组为 "typeId-mutationKey"，空槽位组为 "empty"
    let id: String
    let typeId: Int
    let name: String
    let iconFileName: String?
    var modules: [SimModule]
    let emptySlots: [FittingFlag]

    var totalCount: Int {
        return modules.count + emptySlots.count
    }
}

class SlotState: ObservableObject, Identifiable {
    var id: String {
        slotFlag?.rawValue ?? "none"
    }

    @Published var slotFlag: FittingFlag?
}

/// 保留FittingFlag的Identifiable扩展
extension FittingFlag: Identifiable {
    public var id: String {
        rawValue
    }
}
