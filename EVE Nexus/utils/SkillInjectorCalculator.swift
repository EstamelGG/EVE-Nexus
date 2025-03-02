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
        var remainingSP = requiredSkillPoints
        var currentTotalSP = characterTotalSP
        var largeCount = 0
        var smallCount = 0
        
        // 优先使用大型注入器
        while remainingSP > 0 {
            // 获取当前技能点下大型注入器的注入量
            let largeInjectorSP = getInjectorSkillPoints(isLarge: true, characterTotalSP: currentTotalSP)
            
            // 如果剩余所需技能点小于大型注入器的注入量，考虑使用小型注入器
            if remainingSP < largeInjectorSP {
                break
            }
            
            // 使用一个大型注入器
            largeCount += 1
            remainingSP -= largeInjectorSP
            currentTotalSP += largeInjectorSP
        }
        
        // 如果还有剩余技能点，使用小型注入器
        if remainingSP > 0 {
            // 获取当前技能点下小型注入器的注入量
            let smallInjectorSP = getInjectorSkillPoints(isLarge: false, characterTotalSP: currentTotalSP)
            
            // 计算需要的小型注入器数量（向上取整）
            smallCount = (remainingSP + smallInjectorSP - 1) / smallInjectorSP
            
            // 如果小型注入器数量达到5个或以上，转换为1个大型注入器可能更划算
            if smallCount >= 5 {
                // 计算使用1个大型注入器的情况
                let largeInjectorSP = getInjectorSkillPoints(isLarge: true, characterTotalSP: currentTotalSP)
                
                // 如果大型注入器的注入量足够，使用大型注入器
                if largeInjectorSP >= remainingSP {
                    largeCount += 1
                    smallCount = 0
                } else {
                    // 否则，需要精确计算小型注入器
                    smallCount = calculateSmallInjectors(remainingSP: remainingSP, startingSP: currentTotalSP)
                }
            } else {
                // 小型注入器数量少于5个，但需要考虑注入过程中技能点变化
                smallCount = calculateSmallInjectors(remainingSP: remainingSP, startingSP: currentTotalSP)
            }
        }
        
        Logger.debug("largeCount: \(largeCount), smallCount: \(smallCount), totalSkillPoints: \(requiredSkillPoints)")
        return InjectorCalculation(
            largeInjectorCount: largeCount,
            smallInjectorCount: smallCount,
            totalSkillPoints: requiredSkillPoints
        )
    }
    
    /// 精确计算所需小型注入器数量，考虑注入过程中技能点变化
    /// - Parameters:
    ///   - remainingSP: 剩余所需技能点
    ///   - startingSP: 起始技能点
    /// - Returns: 所需小型注入器数量
    private static func calculateSmallInjectors(remainingSP: Int, startingSP: Int) -> Int {
        var remaining = remainingSP
        var currentSP = startingSP
        var count = 0
        
        while remaining > 0 {
            let injectorSP = getInjectorSkillPoints(isLarge: false, characterTotalSP: currentSP)
            count += 1
            
            if injectorSP >= remaining {
                break
            }
            
            remaining -= injectorSP
            currentSP += injectorSP
        }
        
        return count
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