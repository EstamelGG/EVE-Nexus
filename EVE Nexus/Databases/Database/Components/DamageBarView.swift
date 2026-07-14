import SwiftUI

// MARK: - Shared Damage Type Style

enum DamageTypePalette {
    static let em = Color(red: 74 / 255, green: 128 / 255, blue: 192 / 255)
    static let thermal = Color(red: 176 / 255, green: 53 / 255, blue: 50 / 255)
    static let kinetic = Color(red: 155 / 255, green: 155 / 255, blue: 155 / 255)
    static let explosive = Color(red: 185 / 255, green: 138 / 255, blue: 62 / 255)

    static let colors = [em, thermal, kinetic, explosive]
    static let damageIcons = ["em", "th", "ki", "ex"]
    static let resistanceIcons = ["anti_em", "anti_th", "anti_ki", "anti_ex"]
}

typealias DamageQuad = (em: Double, therm: Double, kin: Double, exp: Double)
typealias DamagePercentages = (em: Int, therm: Int, kin: Int, exp: Int)

enum DamageQuadMath {
    static func total(_ d: DamageQuad) -> Double {
        d.em + d.therm + d.kin + d.exp
    }

    static func scaled(_ d: DamageQuad, by multiplier: Double, places: Int = 1) -> DamageQuad {
        (
            em: (d.em * multiplier).rounded(toDecimalPlaces: places),
            therm: (d.therm * multiplier).rounded(toDecimalPlaces: places),
            kin: (d.kin * multiplier).rounded(toDecimalPlaces: places),
            exp: (d.exp * multiplier).rounded(toDecimalPlaces: places)
        )
    }

    /// 按基础伤害占比（未乘 multiplier）计算百分比
    static func percentages(of d: DamageQuad) -> DamagePercentages {
        let sum = total(d)
        guard sum > 0 else { return (0, 0, 0, 0) }
        return (
            em: Int(round((d.em / sum) * 100)),
            therm: Int(round((d.therm / sum) * 100)),
            kin: Int(round((d.kin / sum) * 100)),
            exp: Int(round((d.exp / sum) * 100))
        )
    }
}

extension Double {
    func rounded(toDecimalPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}

// MARK: - Damage Bar

struct DamageBarView: View {
    let percentage: Int
    let color: Color
    let showValue: Bool
    let value: Double?

    private let backgroundColor: Color
    private let foregroundColor: Color

    init(percentage: Int, color: Color, value: Double? = nil, showValue: Bool = false) {
        self.percentage = percentage
        self.color = color
        self.value = value
        self.showValue = showValue
        backgroundColor = color.opacity(0.8)
        foregroundColor = color.saturated(by: 1.2)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(backgroundColor)
                    .frame(width: geometry.size.width)
                    .overlay(Color.black.opacity(0.5))

                Rectangle()
                    .fill(foregroundColor)
                    .brightness(0.1)
                    .frame(
                        width: max(
                            0,
                            min(geometry.size.width * CGFloat(percentage) / 100, geometry.size.width)
                        )
                    )

                Text(showValue && value != nil ? FormatUtil.format(value!) : "\(percentage)%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .drawingGroup()
    }
}

extension Color {
    func saturated(by amount: Double) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return Color(
            hue: Double(hue),
            saturation: min(Double(saturation) * amount, 1.0),
            brightness: Double(brightness),
            opacity: Double(alpha)
        )
    }
}
