import SwiftUI

typealias IndustryJob = CharacterIndustryAPI.IndustryJob

/// 全局函数：获取活动类型对应的图标文件名
func getActivityTypeIcon(for activityId: Int) -> String {
    switch activityId {
    case 1: // 制造
        return "Icon_Manufacturing.png"
    case 3: // 时间效率研究
        return "Icon_ResearchTime.png"
    case 4: // 材料效率研究
        return "Icon_ResearchMaterial.png"
    case 5: // 复制
        return "Icon_Copying.png"
    case 8: // 发明
        return "Icon_Invention.png"
    case 9: // 反应
        return "Icon_reaction.png"
    default:
        return "Icon_Manufacturing.png"
    }
}

/// 扩展IndustryJob来包含角色归属信息
struct IndustryJobWithOwner {
    let job: IndustryJob
    let ownerId: Int // 该工业项目归属的角色ID（人物工业为主号；军团工业为 installer_id）
    let isFromCorporation: Bool
}

/// 进度更新 Actor（用于线程安全地更新进度）
actor IndustryProgressActor {
    private var current: Int = 0
    private let total: Int
    private let onUpdate: (Int, Int) -> Void

    init(total: Int, onUpdate: @escaping (Int, Int) -> Void) {
        self.total = total
        self.onUpdate = onUpdate
    }

    func increment() {
        current += 1
        onUpdate(current, total)
    }
}

/// 技能加载进度更新 Actor（用于线程安全地更新技能加载进度）
actor SkillProgressActor {
    private var current: Int = 0
    private let total: Int
    private let onUpdate: (Int, Int) -> Void

    init(total: Int, onUpdate: @escaping (Int, Int) -> Void) {
        self.total = total
        self.onUpdate = onUpdate
    }

    func increment() {
        current += 1
        onUpdate(current, total)
    }
}

struct CharacterSlotDetail {
    let characterId: Int
    let characterName: String
    let manufacturingSlots: Int
    let researchSlots: Int
    let reactionSlots: Int
    let manufacturingRange: Int
    let researchRange: Int
    let reactionRange: Int
    let manufacturingUsed: Int
    let researchUsed: Int
    let reactionUsed: Int
}
