import SwiftUI

// MARK: - Models

struct MissileInfo {
    let ammoID: Int
    let damages: DamageQuad
    let multiplier: Double
    let flightTime: Double? // 属性281，单位：ms
    let flightSpeed: Double? // 属性37，单位：米/s

    var actualDamages: DamageQuad {
        DamageQuadMath.scaled(damages, by: multiplier)
    }
}

struct WeaponInfo {
    let damages: DamageQuad
    let multiplier: Double

    var actualDamages: DamageQuad {
        DamageQuadMath.scaled(damages, by: multiplier)
    }
}

// MARK: - Views

struct MissileNameView: View {
    let ammoID: Int
    @ObservedObject var databaseManager: DatabaseManager

    var body: some View {
        NavigationLink {
            ItemInfoMap.getItemInfoView(itemID: ammoID, databaseManager: databaseManager)
        } label: {
            HStack {
                IconManager.shared.loadImage(
                    for: databaseManager.getItemIconFileName(for: ammoID)
                        ?? IconManager.defaultItemIcon
                )
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

                Text(
                    databaseManager.getTypeName(for: ammoID)
                        ?? NSLocalizedString("Main_Database_Unknown", comment: "未知")
                )
                .font(.body)
                .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 由基础伤害 + 倍率构建四系伤害条（导弹 / 武器共用）
struct DamageProfileBarView: View {
    let damages: DamageQuad
    let damageMultiplier: Double

    private let percentages: DamagePercentages
    private let actualDamages: DamageQuad

    init(damages: DamageQuad, damageMultiplier: Double) {
        self.damages = damages
        self.damageMultiplier = damageMultiplier
        percentages = DamageQuadMath.percentages(of: damages)
        actualDamages = DamageQuadMath.scaled(damages, by: damageMultiplier)
    }

    private var values: [Double] {
        [actualDamages.em, actualDamages.therm, actualDamages.kin, actualDamages.exp]
    }

    private var percentValues: [Int] {
        [percentages.em, percentages.therm, percentages.kin, percentages.exp]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DamageTypePalette.damageIcons.indices, id: \.self) { index in
                DamageTypeView(
                    iconName: DamageTypePalette.damageIcons[index],
                    percentage: percentValues[index],
                    value: values[index],
                    color: DamageTypePalette.colors[index]
                )
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .drawingGroup()
    }
}

typealias MissileDamageView = DamageProfileBarView
typealias WeaponDamageView = DamageProfileBarView

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
            DamageBarView(percentage: percentage, color: color, value: value, showValue: true)
        }
    }
}

// MARK: - AttributeGroupView Helpers

extension AttributeGroupView {
    func getMissileInfo() -> MissileInfo? {
        guard let ammoID = allAttributes[507].map({ Int($0) }),
              let missileData = databaseManager.getMissileAttributes(for: ammoID)
        else { return nil }

        return MissileInfo(
            ammoID: ammoID,
            damages: missileData.damages,
            multiplier: allAttributes[212] ?? 1.0,
            flightTime: missileData.flightTime,
            flightSpeed: missileData.flightSpeed
        )
    }

    func getWeaponInfo() -> WeaponInfo? {
        guard hasWeaponDamageAttributes else { return nil }
        return WeaponInfo(
            damages: (
                em: allAttributes[114] ?? 0,
                therm: allAttributes[118] ?? 0,
                kin: allAttributes[117] ?? 0,
                exp: allAttributes[116] ?? 0
            ),
            multiplier: allAttributes[64] ?? 1.0
        )
    }

    @ViewBuilder
    func missileInfoView() -> some View {
        if let info = getMissileInfo() {
            MissileNameView(ammoID: info.ammoID, databaseManager: databaseManager)
            MissileDamageView(damages: info.damages, damageMultiplier: info.multiplier)
        }
    }

    @ViewBuilder
    func weaponDamageView() -> some View {
        if let info = getWeaponInfo() {
            WeaponDamageView(damages: info.damages, damageMultiplier: info.multiplier)
        }
    }
}
