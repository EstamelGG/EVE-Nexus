import SwiftUI

/// EVE伤害类型颜色主题
struct DamageColors {
    // MARK: - 常量
    /// 背景色透明度
    private static let backgroundOpacity: Double = 0.3
    
    // MARK: - 前景色
    /// 电磁伤害前景色 - 蓝色
    static let emForeground = Color(red: 74/255, green: 128/255, blue: 192/255)
    /// 热能伤害前景色 - 红色
    static let thermalForeground = Color(red: 176/255, green: 53/255, blue: 50/255)
    /// 动能伤害前景色 - 灰色
    static let kineticForeground = Color(red: 155/255, green: 155/255, blue: 155/255)
    /// 爆炸伤害前景色 - 橙色
    static let explosiveForeground = Color(red: 185/255, green: 138/255, blue: 62/255)
    
    // MARK: - 背景色（半透明）
    /// 电磁伤害背景色
    static let emBackground = emForeground.opacity(backgroundOpacity)
    /// 热能伤害背景色
    static let thermalBackground = thermalForeground.opacity(backgroundOpacity)
    /// 动能伤害背景色
    static let kineticBackground = kineticForeground.opacity(backgroundOpacity)
    /// 爆炸伤害背景色
    static let explosiveBackground = explosiveForeground.opacity(backgroundOpacity)
    
    // MARK: - 获取颜色主题
    /// 获取指定伤害类型的前景色和背景色
    /// - Parameter type: 伤害类型
    /// - Returns: 包含前景色和背景色的元组
    static func getDamageColors(for type: DamageType) -> (foreground: Color, background: Color) {
        switch type {
        case .em:
            return (emForeground, emBackground)
        case .thermal:
            return (thermalForeground, thermalBackground)
        case .kinetic:
            return (kineticForeground, kineticBackground)
        case .explosive:
            return (explosiveForeground, explosiveBackground)
        }
    }
}

/// EVE伤害类型枚举
enum DamageType: String, CaseIterable {
    /// 电磁伤害
    case em
    /// 热能伤害
    case thermal
    /// 动能伤害
    case kinetic
    /// 爆炸伤害
    case explosive
    
    /// 获取伤害类型对应的图标名称
    var iconName: String {
        switch self {
        case .em:
            return "items_22_32_12.png"
        case .thermal:
            return "items_22_32_10.png"
        case .kinetic:
            return "items_22_32_9.png"
        case .explosive:
            return "items_22_32_11.png"
        }
    }
    
    /// 获取抗性类型对应的图标名称
    var resistanceIconName: String {
        switch self {
        case .em:
            return "items_22_32_20.png"
        case .thermal:
            return "items_22_32_18.png"
        case .kinetic:
            return "items_22_32_17.png"
        case .explosive:
            return "items_22_32_19.png"
        }
    }
} 