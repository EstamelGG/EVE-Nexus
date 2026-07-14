import Foundation

// MARK: - EVE物品Flag映射

// 用于替代数据库查询，提供flagID到名称的静态映射

enum FlagMapping {
    /// 静态的flagID到名称映射
    private static let flagNames: [Int: String] = [
        0: "None",
        1: "Wallet",
        2: "Offices",
        3: "Wardrobe",
        4: "Hangar",
        5: "Cargo",
        6: "OfficeImpound",
        7: "Skill",
        8: "Reward",
        11: "LoSlot0",
        12: "LoSlot1",
        13: "LoSlot2",
        14: "LoSlot3",
        15: "LoSlot4",
        16: "LoSlot5",
        17: "LoSlot6",
        18: "LoSlot7",
        19: "MedSlot0",
        20: "MedSlot1",
        21: "MedSlot2",
        22: "MedSlot3",
        23: "MedSlot4",
        24: "MedSlot5",
        25: "MedSlot6",
        26: "MedSlot7",
        27: "HiSlot0",
        28: "HiSlot1",
        29: "HiSlot2",
        30: "HiSlot3",
        31: "HiSlot4",
        32: "HiSlot5",
        33: "HiSlot6",
        34: "HiSlot7",
        35: "Fixed Slot",
        36: "AssetSafety",
        56: "Capsule",
        57: "Pilot",
        61: "Skill In Training",
        62: "CorpMarket",
        63: "Locked",
        64: "Unlocked",
        70: "Office Slot 1",
        71: "Office Slot 2",
        72: "Office Slot 3",
        73: "Office Slot 4",
        74: "Office Slot 5",
        75: "Office Slot 6",
        76: "Office Slot 7",
        77: "Office Slot 8",
        78: "Office Slot 9",
        79: "Office Slot 10",
        80: "Office Slot 11",
        81: "Office Slot 12",
        82: "Office Slot 13",
        83: "Office Slot 14",
        84: "Office Slot 15",
        85: "Office Slot 16",
        86: "Bonus",
        87: "DroneBay",
        88: "Booster",
        89: "Implant",
        90: "ShipHangar",
        91: "ShipOffline",
        92: "RigSlot0",
        93: "RigSlot1",
        94: "RigSlot2",
        95: "RigSlot3",
        96: "RigSlot4",
        97: "RigSlot5",
        98: "RigSlot6",
        99: "RigSlot7",
        115: "CorpSAG1",
        116: "CorpSAG2",
        117: "CorpSAG3",
        118: "CorpSAG4",
        119: "CorpSAG5",
        120: "CorpSAG6",
        121: "CorpSAG7",
        122: "SecondaryStorage",
        125: "SubSystem0",
        126: "SubSystem1",
        127: "SubSystem2",
        128: "SubSystem3",
        129: "SubSystem4",
        130: "SubSystem5",
        131: "SubSystem6",
        132: "SubSystem7",
        133: "SpecializedFuelBay",
        134: "SpecializedAsteroidHold",
        135: "SpecializedGasHold",
        136: "SpecializedMineralHold",
        137: "SpecializedSalvageHold",
        138: "SpecializedShipHold",
        139: "SpecializedSmallShipHold",
        140: "SpecializedMediumShipHold",
        141: "SpecializedLargeShipHold",
        142: "SpecializedIndustrialShipHold",
        143: "SpecializedAmmoHold",
        144: "StructureActive",
        145: "StructureInactive",
        146: "JunkyardReprocessed",
        147: "JunkyardTrashed",
        148: "SpecializedCommandCenterHold",
        149: "SpecializedPlanetaryCommoditiesHold",
        150: "PlanetSurface",
        151: "SpecializedMaterialBay",
        152: "DustCharacterDatabank",
        153: "DustCharacterBattle",
        154: "QuafeBay",
        155: "FleetHangar",
        156: "HiddenModifiers",
        157: "StructureOffline",
        158: "FighterBay",
        159: "FighterTube0",
        160: "FighterTube1",
        161: "FighterTube2",
        162: "FighterTube3",
        163: "FighterTube4",
        164: "StructureServiceSlot0",
        165: "StructureServiceSlot1",
        166: "StructureServiceSlot2",
        167: "StructureServiceSlot3",
        168: "StructureServiceSlot4",
        169: "StructureServiceSlot5",
        170: "StructureServiceSlot6",
        171: "StructureServiceSlot7",
        172: "StructureFuel",
        173: "Deliveries",
        174: "CrateLoot",
        176: "BoosterBay",
        177: "SubsystemBay",
        178: "Raffles",
        179: "FrigateEscapeBay",
        180: "StructureDeedBay",
        181: "SpecializedIceHold",
        182: "SpecializedAsteroidHold",
        183: "MobileDepot",
        184: "CorpProjectsHangar",
        185: "ColonyResourcesHold",
        186: "MoonMaterialBay",
        187: "CapsuleerDeliveries",
    ]

    /// 获取flag名称，支持本地化
    /// - Parameter flagID: flag ID
    /// - Returns: 本地化后的flag名称
    static func getFlagName(for flagID: Int) -> String {
        guard flagNames[flagID] != nil else {
            return NSLocalizedString("Unknown Flag", comment: "未知舱室")
        }

        // 对于常用的flag，复用现有的本地化字符串
        switch flagID {
        // 装配槽位
        case 11 ... 18: // 低槽
            return NSLocalizedString("Main_KM_Low_Slots", comment: "低槽")
        case 19 ... 26: // 中槽
            return NSLocalizedString("Main_KM_Medium_Slots", comment: "中槽")
        case 27 ... 34: // 高槽
            return NSLocalizedString("Main_KM_High_Slots", comment: "高槽")
        case 92 ... 99: // 改装槽
            return NSLocalizedString("Main_KM_Rig_Slots", comment: "改装槽")
        case 125 ... 132: // 子系统槽
            return NSLocalizedString("Main_KM_Subsystem_Slots", comment: "子系统")
        case 159 ... 163: // 战斗机发射管
            return NSLocalizedString("Main_KM_Fighter_Tubes", comment: "战斗机发射管")
        // 常用舱室 - 直接使用flagName作为本地化key
        case 4: // Hangar
            return NSLocalizedString("Location_Flag_Hangar", comment: "机库")
        case 5: // Cargo
            return NSLocalizedString("Cargo", comment: "货舱")
        case 87: // DroneBay
            return NSLocalizedString("DroneBay", comment: "无人机舱")
        case 90: // ShipHangar
            return NSLocalizedString("ShipHangar", comment: "舰船机库")
        case 155: // FleetHangar
            return NSLocalizedString("FleetHangar", comment: "舰队机库")
        case 158: // FighterBay
            return NSLocalizedString("FighterBay", comment: "战斗机舱")
        case 179: // FrigateEscapeBay
            return NSLocalizedString("FrigateEscapeBay", comment: "护卫舰逃生舱")
        case 89: // Implant
            return NSLocalizedString("Main_KM_Implants", comment: "植入体")
        // 公司机库
        case 115: // CorpSAG1
            return NSLocalizedString("Location_Flag_CorpSAG1", comment: "公司机库 1")
        case 116: // CorpSAG2
            return NSLocalizedString("Location_Flag_CorpSAG2", comment: "公司机库 2")
        case 117: // CorpSAG3
            return NSLocalizedString("Location_Flag_CorpSAG3", comment: "公司机库 3")
        case 118: // CorpSAG4
            return NSLocalizedString("Location_Flag_CorpSAG4", comment: "公司机库 4")
        case 119: // CorpSAG5
            return NSLocalizedString("Location_Flag_CorpSAG5", comment: "公司机库 5")
        case 120: // CorpSAG6
            return NSLocalizedString("Location_Flag_CorpSAG6", comment: "公司机库 6")
        case 121: // CorpSAG7
            return NSLocalizedString("Location_Flag_CorpSAG7", comment: "公司机库 7")
        // 特殊货舱 - 使用具体的本地化key
        case 133: // SpecializedFuelBay
            return NSLocalizedString("SpecializedFuelBay", comment: "燃料舱")
        case 134: // SpecializedAsteroidHold
            return NSLocalizedString("SpecializedAsteroidHold", comment: "小行星舱")
        case 135: // SpecializedGasHold
            return NSLocalizedString("SpecializedGasHold", comment: "气云舱")
        case 136: // SpecializedMineralHold
            return NSLocalizedString("SpecializedMineralHold", comment: "矿物舱")
        case 137: // SpecializedSalvageHold
            return NSLocalizedString("SpecializedSalvageHold", comment: "残骸舱")
        case 138: // SpecializedShipHold
            return NSLocalizedString("SpecializedShipHold", comment: "舰船舱")
        case 139: // SpecializedSmallShipHold
            return NSLocalizedString("SpecializedSmallShipHold", comment: "小型舰船舱")
        case 140: // SpecializedMediumShipHold
            return NSLocalizedString("SpecializedMediumShipHold", comment: "中型舰船舱")
        case 141: // SpecializedLargeShipHold
            return NSLocalizedString("SpecializedLargeShipHold", comment: "大型舰船舱")
        case 142: // SpecializedIndustrialShipHold
            return NSLocalizedString("SpecializedIndustrialShipHold", comment: "工业舰船舱")
        case 143: // SpecializedAmmoHold
            return NSLocalizedString("SpecializedAmmoHold", comment: "弹药舱")
        case 148: // SpecializedCommandCenterHold
            return NSLocalizedString("SpecializedCommandCenterHold", comment: "指挥中心舱")
        case 149: // SpecializedPlanetaryCommoditiesHold
            return NSLocalizedString("SpecializedPlanetaryCommoditiesHold", comment: "行星商品舱")
        case 151: // SpecializedMaterialBay
            return NSLocalizedString("SpecializedMaterialBay", comment: "材料舱")
        case 181: // SpecializedIceHold
            return NSLocalizedString("SpecializedIceHold", comment: "冰矿舱")
        case 182: // SpecializedAsteroidHold (重复的ID，使用相同处理)
            return NSLocalizedString("SpecializedAsteroidHold", comment: "小行星舱")
        // 其他舱室
        case 177: // SubsystemBay
            return NSLocalizedString("Location_Flag_SubSystemBay", comment: "子系统舱")
        // 其他未映射的flag，统一使用"其他"
        default:
            return NSLocalizedString("Flag_Other", comment: "其他")
        }
    }
}
