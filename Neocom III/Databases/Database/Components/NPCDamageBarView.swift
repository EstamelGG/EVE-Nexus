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
            em: damages.em * multiplier,
            therm: damages.therm * multiplier,
            kin: damages.kin * multiplier,
            exp: damages.exp * multiplier
        )
    }
}

// 导弹伤害显示组件
struct MissileInfoView: View {
    let ammoID: Int
    let damages: (em: Double, therm: Double, kin: Double, exp: Double)
    let damageMultiplier: Double
    @ObservedObject var databaseManager: DatabaseManager
    
    private var missileInfo: MissileInfo {
        MissileInfo(ammoID: ammoID, damages: damages, multiplier: damageMultiplier)
    }
    
    var body: some View {
        NavigationLink(destination: ItemInfoMap.getItemInfoView(
            itemID: ammoID,
            categoryID: 8,
            databaseManager: databaseManager
        )) {
            VStack(alignment: .leading, spacing: 2) {
                // 弹药名称和图标
                HStack {
                    IconManager.shared.loadImage(for: databaseManager.getItemIconFileName(for: ammoID) ?? DatabaseConfig.defaultItemIcon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                    Text(databaseManager.getTypeName(for: ammoID) ?? NSLocalizedString("Main_Database_Unknown", comment: "未知"))
                        .font(.body)
                        .foregroundColor(.primary)
                }
                
                // 伤害条
                HStack(spacing: 8) {
                    // 电磁伤害
                    DamageTypeView(
                        iconName: "items_22_32_12.png",
                        percentage: Int(round((missileInfo.damages.em / missileInfo.totalDamage) * 100)),
                        value: missileInfo.actualDamages.em,
                        color: Color(red: 74/255, green: 128/255, blue: 192/255)
                    )
                    
                    // 热能伤害
                    DamageTypeView(
                        iconName: "items_22_32_10.png",
                        percentage: Int(round((missileInfo.damages.therm / missileInfo.totalDamage) * 100)),
                        value: missileInfo.actualDamages.therm,
                        color: Color(red: 176/255, green: 53/255, blue: 50/255)
                    )
                    
                    // 动能伤害
                    DamageTypeView(
                        iconName: "items_22_32_9.png",
                        percentage: Int(round((missileInfo.damages.kin / missileInfo.totalDamage) * 100)),
                        value: missileInfo.actualDamages.kin,
                        color: Color(red: 155/255, green: 155/255, blue: 155/255)
                    )
                    
                    // 爆炸伤害
                    DamageTypeView(
                        iconName: "items_22_32_11.png",
                        percentage: Int(round((missileInfo.damages.exp / missileInfo.totalDamage) * 100)),
                        value: missileInfo.actualDamages.exp,
                        color: Color(red: 185/255, green: 138/255, blue: 62/255)
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// 单个伤害类型显示组件
private struct DamageTypeView: View {
    let iconName: String
    let percentage: Int
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                IconManager.shared.loadImage(for: iconName)
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
            MissileInfoView(
                ammoID: missileInfo.ammoID,
                damages: missileInfo.damages,
                damageMultiplier: missileInfo.multiplier,
                databaseManager: databaseManager
            )
        }
    }
} 
