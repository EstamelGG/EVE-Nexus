import Foundation

/// 技能组图标管理器
class SkillGroupIconManager {
    static let shared = SkillGroupIconManager()

    private init() {}

    /// 技能组图标映射
    private let skillGroupIcons: [Int: String] = [
        255: "skill_group_gunnery", // 射击学
        256: "skill_group_missiles", // 导弹
        257: "skill_group_spaceshipcmd", // 飞船操控学
        258: "skill_group_fleetsupport", // 舰队支援
        266: "skill_group_corpmgmt", // 军团管理
        268: "skill_group_production", // 生产
        269: "skill_group_rigging", // 改装件
        270: "skill_group_science", // 科学
        272: "skill_group_electronicsystems", // 电子系统
        273: "skill_group_drones", // 无人机
        274: "skill_group_trade", // 贸易学
        275: "skill_group_navigation", // 导航学
        278: "skill_group_social", // 社会学
        1209: "skill_group_shields", // 护盾
        1210: "skill_group_armor", // 装甲
        1213: "skill_group_targeting", // 锁定系统
        1216: "skill_group_engineering", // 工程学
        1217: "skill_group_scanning", // 扫描
        1218: "skill_group_resourceprocessing", // 资源处理
        1220: "skill_group_neuralenhancement", // 神经增强
        1240: "skill_group_subsystems", // 子系统
        1241: "skill_group_planetmgmt", // 行星管理
        1545: "skill_group_structuremgmt", // 建筑管理
        4734: "skill_group_skinsequencing", // 排序
    ]

    /// 获取技能组图标名称
    /// - Parameter groupId: 技能组ID
    func getIconName(for groupId: Int) -> String {
        return skillGroupIcons[groupId] ?? "skill"
    }
}
