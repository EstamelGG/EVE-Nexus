import Foundation

/// 技能注入器计算结果
public struct InjectorCalculation {
    /// 所需大型技能注入器数量
    public let largeInjectorCount: Int
    /// 所需小型技能注入器数量
    public let smallInjectorCount: Int
    /// 总计所需技能点数
    public let totalSkillPoints: Int
}

/// 技能注入器计算工具类
public enum SkillInjectorCalculator {
    // 技能注入器类型ID
    public static let largeInjectorTypeId = 40520
    public static let smallInjectorTypeId = 45635
    
    /// 计算完成技能队列所需的技能注入器数量
    /// - Parameters:
    ///   - requiredSkillPoints: 所需技能点数
    ///   - characterTotalSP: 角色当前总技能点数
    /// - Returns: 注入器计算结果
    public static func calculate(requiredSkillPoints: Int, characterTotalSP: Int) -> InjectorCalculation {
        // 根据角色总技能点数确定每个注入器提供的技能点数
        let largeInjectorSP: Int
        let smallInjectorSP: Int
        
        switch characterTotalSP {
        case ..<5_000_000:
            largeInjectorSP = 500_000
            smallInjectorSP = 100_000
        case 5_000_000..<50_000_000:
            largeInjectorSP = 400_000
            smallInjectorSP = 80_000
        case 50_000_000..<80_000_000:
            largeInjectorSP = 300_000
            smallInjectorSP = 60_000
        default:
            largeInjectorSP = 150_000
            smallInjectorSP = 30_000
        }
        
        // 计算所需注入器数量
        var largeCount = requiredSkillPoints / largeInjectorSP
        let remainingPoints = requiredSkillPoints % largeInjectorSP
        var smallCount = (remainingPoints + smallInjectorSP - 1) / smallInjectorSP
        
        // 如果小型注入器数量达到5个，转换为1个大型注入器
        if smallCount >= 5 {
            largeCount += 1
            smallCount = 0
        }
        
        Logger.debug("largeCount: \(largeCount), smallCount: \(smallCount), totalSkillPoints: \(requiredSkillPoints)")
        return InjectorCalculation(
            largeInjectorCount: largeCount,
            smallInjectorCount: smallCount,
            totalSkillPoints: requiredSkillPoints
        )
    }
    
    /// 获取技能注入器在指定技能点数下提供的技能点数
    /// - Parameters:
    ///   - isLarge: 是否为大型技能注入器
    ///   - characterTotalSP: 角色当前总技能点数
    /// - Returns: 注入器提供的技能点数
    public static func getInjectorSkillPoints(isLarge: Bool, characterTotalSP: Int) -> Int {
        switch characterTotalSP {
        case ..<5_000_000:
            return isLarge ? 500_000 : 100_000
        case 5_000_000..<50_000_000:
            return isLarge ? 400_000 : 80_000
        case 50_000_000..<80_000_000:
            return isLarge ? 300_000 : 60_000
        default:
            return isLarge ? 150_000 : 30_000
        }
    }
} 