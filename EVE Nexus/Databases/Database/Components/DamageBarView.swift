import SwiftUI

struct DamageBarView: View {
    let percentage: Int
    let color: Color
    let showValue: Bool
    let value: Double?

    // 缓存颜色和渐变
    private let backgroundColor: Color
    private let foregroundColor: Color

    init(percentage: Int, color: Color, value: Double? = nil, showValue: Bool = false) {
        self.percentage = percentage
        self.color = color
        self.value = value
        self.showValue = showValue

        // 预计算颜色
        backgroundColor = color.opacity(0.8)
        foregroundColor = color.saturated(by: 1.2)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景条
                Rectangle()
                    .fill(backgroundColor)
                    .frame(width: geometry.size.width)
                    .overlay(Color.black.opacity(0.5))

                // 进度条
                Rectangle()
                    .fill(foregroundColor)
                    .brightness(0.1)  // 增加亮度
                    .frame(
                        width: max(
                            0,
                            min(
                                geometry.size.width * CGFloat(percentage) / 100, geometry.size.width
                            )
                        ))

                // 文字显示
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

// 颜色扩展
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
