import Foundation
import SwiftUI

/// 部门图标映射
let divisionIcons: [Int: String] = [
    24: "gunnery_turret", // 安全
    23: "miner", // 采矿
    22: "cargo_fit", // 物流
    18: "pg", // 研发
    25: "not_found", // 工业家 - 商业大亨
    26: "not_found", // 探险家
    27: "not_found", // 工业家 - 制造商
    28: "not_found", // 执法者
    29: "not_found", // 自由战士
    37: "not_found", // 星际捷运
]

/// 获取代理人类型名称的函数
func getAgentTypeName(_ agentType: Int) -> String {
    switch agentType {
    case 1: return NSLocalizedString("Agent_Type_NonAgent", comment: "非代理人")
    case 2: return NSLocalizedString("Agent_Type_BasicAgent", comment: "基础代理人")
    case 3: return NSLocalizedString("Agent_Type_TutorialAgent", comment: "教程代理人")
    case 4: return NSLocalizedString("Agent_Type_ResearchAgent", comment: "研究代理人")
    case 5: return NSLocalizedString("Agent_Type_CONCORDAgent", comment: "CONCORD代理人")
    case 6:
        return NSLocalizedString("Agent_Type_GenericStorylineMissionAgent", comment: "通用剧情任务代理人")
    case 7: return NSLocalizedString("Agent_Type_StorylineMissionAgent", comment: "剧情任务代理人")
    case 8: return NSLocalizedString("Agent_Type_EventMissionAgent", comment: "事件任务代理人")
    case 9: return NSLocalizedString("Agent_Type_FactionalWarfareAgent", comment: "势力战争代理人")
    case 10: return NSLocalizedString("Agent_Type_EpicArcAgent", comment: "史诗弧线代理人")
    case 11: return NSLocalizedString("Agent_Type_AuraAgent", comment: "Aura代理人")
    case 12: return NSLocalizedString("Agent_Type_CareerAgent", comment: "职业代理人")
    case 13: return NSLocalizedString("Agent_Type_HeraldryAgent", comment: "纹章代理人")
    default: return NSLocalizedString("Agent_Type_Other", comment: "其他")
    }
}

/// 获取代理人类型简短名称的函数
func getAgentTypeShortName(_ agentType: Int) -> String {
    switch agentType {
    case 1: return NSLocalizedString("Agent_Type_Short_NonAgent", comment: "非代理")
    case 2: return NSLocalizedString("Agent_Type_Short_BasicAgent", comment: "基础")
    case 3: return NSLocalizedString("Agent_Type_Short_TutorialAgent", comment: "教程")
    case 4: return NSLocalizedString("Agent_Type_Short_ResearchAgent", comment: "研究")
    case 5: return NSLocalizedString("Agent_Type_Short_CONCORDAgent", comment: "CONCORD")
    case 6:
        return NSLocalizedString("Agent_Type_Short_GenericStorylineMissionAgent", comment: "故事线")
    case 7: return NSLocalizedString("Agent_Type_Short_StorylineMissionAgent", comment: "剧情")
    case 8: return NSLocalizedString("Agent_Type_Short_EventMissionAgent", comment: "事件")
    case 9: return NSLocalizedString("Agent_Type_Short_FactionalWarfareAgent", comment: "派系战")
    case 10: return NSLocalizedString("Agent_Type_Short_EpicArcAgent", comment: "史诗")
    case 11: return NSLocalizedString("Agent_Type_Short_AuraAgent", comment: "Aura")
    case 12: return NSLocalizedString("Agent_Type_Short_CareerAgent", comment: "职业")
    case 13: return NSLocalizedString("Agent_Type_Short_HeraldryAgent", comment: "徽章")
    default: return NSLocalizedString("Agent_Type_Short_Other", comment: "其他")
    }
}

/// 代理人项目结构体（含一次全表加载时的关联字段，供 Cell / Hierarchy 直接使用）
struct AgentItem: Identifiable {
    let id = UUID()
    let agentID: Int
    let agentType: Int
    let name: String
    let level: Int
    let corporationID: Int
    let divisionID: Int
    let isLocator: Bool
    let locationID: Int
    let locationName: String
    let solarSystemID: Int?
    let solarSystemName: String?
    let security: Double?
    let corporationName: String
    let corporationIcon: String
    let factionID: Int
    let factionName: String
    let factionIcon: String
    let divisionName: String
    let regionID: Int?
    let effectiveSolarSystemID: Int?
    let sortLocation: String
}
