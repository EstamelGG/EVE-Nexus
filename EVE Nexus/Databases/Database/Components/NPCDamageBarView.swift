import SwiftUI

// 导弹伤害信息结构体
struct MissileInfo {
    let ammoID: Int
    let damages: (em: Double, therm: Double, kin: Double, exp: Double)
    let multiplier: Double
    
    var totalDamage: Double {
        damages.em + damages.therm + damages.kin + damages.exp
    }
    
    var actualDamages: (em: Double, therm: Double, kin: Double, exp: Double) {
        (
            em: (damages.em * multiplier).rounded(toDecimalPlaces: 1),
            therm: (damages.therm * multiplier).rounded(toDecimalPlaces: 1),
            kin: (damages.kin * multiplier).rounded(toDecimalPlaces: 1),
            exp: (damages.exp * multiplier).rounded(toDecimalPlaces: 1)
        )
    }
    
    // 计算各个伤害类型的百分比
    func getDamagePercentages() -> (em: Int, therm: Int, kin: Int, exp: Int) {
        if totalDamage <= 0 {
            return (0, 0, 0, 0)  // 如果总伤害为0，所有百分比都为0
        }
        return (
            em: Int(round((damages.em / totalDamage) * 100)),
            therm: Int(round((damages.therm / totalDamage) * 100)),
            kin: Int(round((damages.kin / totalDamage) * 100)),
            exp: Int(round((damages.exp / totalDamage) * 100))
        )
    }
}

// 导弹名称和图标组件
struct MissileNameView: View {
    let ammoID: Int
    @ObservedObject var databaseManager: DatabaseManager
    
    var body: some View {
        NavigationLink(destination: ItemInfoMap.getItemInfoView(
            itemID: ammoID,
            categoryID: 8,
            databaseManager: databaseManager
        )) {
            HStack {
                IconManager.shared.loadImage(for: databaseManager.getItemIconFileName(for: ammoID) ?? DatabaseConfig.defaultItemIcon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                Text(databaseManager.getTypeName(for: ammoID) ?? NSLocalizedString("Main_Database_Unknown", comment: "未知"))
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// 导弹伤害条组件
struct MissileDamageView: View {
    let damages: (em: Double, therm: Double, kin: Double, exp: Double)
    let damageMultiplier: Double
    
    // 缓存计算结果
    private let missileInfo: MissileInfo
    private let percentages: (em: Int, therm: Int, kin: Int, exp: Int)
    private let actualDamages: (em: Double, therm: Double, kin: Double, exp: Double)
    
    init(damages: (em: Double, therm: Double, kin: Double, exp: Double), damageMultiplier: Double) {
        self.damages = damages
        self.damageMultiplier = damageMultiplier
        
        // 在初始化时计算所有值
        self.missileInfo = MissileInfo(ammoID: 0, damages: damages, multiplier: damageMultiplier)
        self.percentages = missileInfo.getDamagePercentages()
        self.actualDamages = missileInfo.actualDamages
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // 电磁伤害
            DamageTypeView(
                iconName: "em",
                percentage: percentages.em,
                value: actualDamages.em,
                color: Color(red: 74/255, green: 128/255, blue: 192/255)
            )
            
            // 热能伤害
            DamageTypeView(
                iconName: "th",
                percentage: percentages.therm,
                value: actualDamages.therm,
                color: Color(red: 176/255, green: 53/255, blue: 50/255)
            )
            
            // 动能伤害
            DamageTypeView(
                iconName: "ki",
                percentage: percentages.kin,
                value: actualDamages.kin,
                color: Color(red: 155/255, green: 155/255, blue: 155/255)
            )
            
            // 爆炸伤害
            DamageTypeView(
                iconName: "ex",
                percentage: percentages.exp,
                value: actualDamages.exp,
                color: Color(red: 185/255, green: 138/255, blue: 62/255)
            )
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .drawingGroup() // 使用 Metal 渲染
    }
}

// 优化单个伤害类型显示组件
private struct DamageTypeView: View {
    let iconName: String
    let percentage: Int
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(iconName)
                    .resizable()
                    .frame(width: 18, height: 18)
                Text("\(percentage)%")
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            DamageBarView(
                percentage: percentage,
                color: color,
                value: value,
                showValue: true
            )
        }
    }
}

// 导弹信息提取扩展
extension AttributeGroupView {
    func getMissileInfo() -> MissileInfo? {
        // 检查是否存在导弹属性和ID
        guard let ammoID = allAttributes[507].map({ Int($0) }),
              let damages = databaseManager.getItemDamages(for: ammoID),
              damages.em + damages.therm + damages.kin + damages.exp > 0 else {
            return nil
        }
        
        // 获取伤害倍增系数
        let multiplier = allAttributes[212] ?? 1.0
        
        return MissileInfo(ammoID: ammoID, damages: damages, multiplier: multiplier)
    }
    
    @ViewBuilder
    func missileInfoView() -> some View {
        if let missileInfo = getMissileInfo() {
            // 导弹名称和图标（第一个单元格）
            MissileNameView(
                ammoID: missileInfo.ammoID,
                databaseManager: databaseManager
            )
            
            // 导弹伤害条（第二个单元格）
            MissileDamageView(
                damages: missileInfo.damages,
                damageMultiplier: missileInfo.multiplier
            )
        }
    }
}

// 武器伤害信息结构体
struct WeaponInfo {
    let damages: (em: Double, therm: Double, kin: Double, exp: Double)
    let multiplier: Double
    
    var totalDamage: Double {
        damages.em + damages.therm + damages.kin + damages.exp
    }
    
    var actualDamages: (em: Double, therm: Double, kin: Double, exp: Double) {
        (
            em: (damages.em * multiplier).rounded(toDecimalPlaces: 1),
            therm: (damages.therm * multiplier).rounded(toDecimalPlaces: 1),
            kin: (damages.kin * multiplier).rounded(toDecimalPlaces: 1),
            exp: (damages.exp * multiplier).rounded(toDecimalPlaces: 1)
        )
    }
    
    // 计算各个伤害类型的百分比
    func getDamagePercentages() -> (em: Int, therm: Int, kin: Int, exp: Int) {
        if totalDamage <= 0 {
            return (0, 0, 0, 0)  // 如果总伤害为0，所有百分比都为0
        }
        return (
            em: Int(round((damages.em / totalDamage) * 100)),
            therm: Int(round((damages.therm / totalDamage) * 100)),
            kin: Int(round((damages.kin / totalDamage) * 100)),
            exp: Int(round((damages.exp / totalDamage) * 100))
        )
    }
}

// 武器伤害显示组件
struct WeaponDamageView: View {
    let damages: (em: Double, therm: Double, kin: Double, exp: Double)
    let damageMultiplier: Double
    
    // 缓存计算结果
    private let weaponInfo: WeaponInfo
    private let percentages: (em: Int, therm: Int, kin: Int, exp: Int)
    private let actualDamages: (em: Double, therm: Double, kin: Double, exp: Double)
    
    init(damages: (em: Double, therm: Double, kin: Double, exp: Double), damageMultiplier: Double) {
        self.damages = damages
        self.damageMultiplier = damageMultiplier
        
        // 在初始化时计算所有值
        self.weaponInfo = WeaponInfo(damages: damages, multiplier: damageMultiplier)
        self.percentages = weaponInfo.getDamagePercentages()
        self.actualDamages = weaponInfo.actualDamages
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                // 电磁伤害
                DamageTypeView(
                    iconName: "em",
                    percentage: percentages.em,
                    value: actualDamages.em,
                    color: Color(red: 74/255, green: 128/255, blue: 192/255)
                )
                
                // 热能伤害
                DamageTypeView(
                    iconName: "th",
                    percentage: percentages.therm,
                    value: actualDamages.therm,
                    color: Color(red: 176/255, green: 53/255, blue: 50/255)
                )
                
                // 动能伤害
                DamageTypeView(
                    iconName: "ki",
                    percentage: percentages.kin,
                    value: actualDamages.kin,
                    color: Color(red: 155/255, green: 155/255, blue: 155/255)
                )
                
                // 爆炸伤害
                DamageTypeView(
                    iconName: "ex",
                    percentage: percentages.exp,
                    value: actualDamages.exp,
                    color: Color(red: 185/255, green: 138/255, blue: 62/255)
                )
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .drawingGroup() // 使用 Metal 渲染
    }
}

// 在 AttributeGroupView 扩展中添加武器伤害相关方法
extension AttributeGroupView {
    // 获取武器伤害信息
    func getWeaponInfo() -> WeaponInfo? {
        // 只要有这些属性就返回伤害信息，不检查数值是否为0
        if hasWeaponDamageAttributes {
            let damages = (
                em: allAttributes[114] ?? 0,
                therm: allAttributes[118] ?? 0,
                kin: allAttributes[117] ?? 0,
                exp: allAttributes[116] ?? 0
            )
            
            // 获取伤害倍增系数
            let multiplier = allAttributes[64] ?? 1.0
            
            return WeaponInfo(damages: damages, multiplier: multiplier)
        }
        return nil
    }
    
    // 检查当前组是否包含武器伤害属性
    private var hasWeaponDamageAttributes: Bool {
        return group.attributes.contains { damageAttributeIDs.contains($0.id) }
    }
    
    @ViewBuilder
    func weaponDamageView() -> some View {
        // 只要有武器伤害属性就显示
        if let weaponInfo = getWeaponInfo() {
            WeaponDamageView(
                damages: weaponInfo.damages,
                damageMultiplier: weaponInfo.multiplier
            )
        }
    }
}

// 添加 Double 扩展来处理小数位数
private extension Double {
    func rounded(toDecimalPlaces places: Int) -> Double {
        let multiplier = pow(10.0, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
} 
