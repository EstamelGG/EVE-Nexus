import SwiftUI

struct WealthPieSlice: Identifiable {
    var id: String {
        type.rawValue
    } // 使用 type 的 rawValue 作为稳定的 ID
    let type: WealthType
    let value: Double
    let percentage: Double
    let startAngle: Double
    let endAngle: Double
    let color: Color
}

struct WealthPieChart: View {
    let items: [WealthItem]
    let size: CGFloat
    @State private var selectedSlice: WealthPieSlice?

    private var slices: [WealthPieSlice] {
        let total = items.reduce(0) { $0 + $1.value }
        var startAngle = 0.0

        return items.map { item in
            let percentage = total > 0 ? item.value / total : 0
            let angle = 360 * percentage
            let slice = WealthPieSlice(
                type: item.type,
                value: item.value,
                percentage: percentage * 100,
                startAngle: startAngle,
                endAngle: startAngle + angle,
                color: colorForType(item.type)
            )
            startAngle += angle
            return slice
        }
    }

    private func colorForType(_ type: WealthType) -> Color {
        switch type {
        case .assets:
            return .blue
        case .implants:
            return .green
        case .orders:
            return .orange
        case .contracts:
            return .teal
        case .wallet:
            return .purple
        }
    }

    var body: some View {
        let chartView = HStack(alignment: .center, spacing: 20) {
            // 图例和占比
            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        // 颜色方块
                        Rectangle()
                            .fill(slice.color)
                            .frame(width: 12, height: 12)
                            .cornerRadius(2)
                            .overlay(
                                // 高亮边框
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(selectedSlice?.id == slice.id ? Color.primary : Color.clear, lineWidth: 2)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            // 分类名称
                            Text(NSLocalizedString("Wealth_\(slice.type.rawValue)", comment: ""))
                                .font(.caption)
                                .fontWeight(selectedSlice?.id == slice.id ? .semibold : .regular)
                                .foregroundColor(selectedSlice?.id == slice.id ? .primary : .primary)

                            // 占比和金额
                            Text(
                                String(
                                    format: "%.1f%% (%@)", slice.percentage,
                                    FormatUtil.formatISK(slice.value)
                                )
                            )
                            .font(.caption2)
                            .foregroundColor(selectedSlice?.id == slice.id ? .primary : .secondary)
                        }
                    }
                    .padding(.horizontal, selectedSlice?.id == slice.id ? 4 : 0)
                    .padding(.vertical, selectedSlice?.id == slice.id ? 2 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedSlice?.id == slice.id ? Color.secondary.opacity(0.1) : Color.clear)
                    )
                    .onTapGesture {
                        withAnimation(.spring()) {
                            selectedSlice = selectedSlice?.id == slice.id ? nil : slice
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            // 圆环图
            ZStack {
                ForEach(slices) { slice in
                    PieSliceView(slice: slice, size: size)
                        .scaleEffect(selectedSlice?.id == slice.id ? 1.05 : 1.0)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                selectedSlice = selectedSlice?.id == slice.id ? nil : slice
                            }
                        }
                }
            }
            .frame(width: size, height: size)
        }

        return
            chartView
                .id(items.map { "\($0.type)\($0.value)" }.joined())
    }
}

struct PieSliceView: View {
    let slice: WealthPieSlice
    let size: CGFloat

    /// 内圆半径比例，设置为外圆半径的40%，形成圆环
    private var innerRadiusRatio: CGFloat {
        0.4
    }

    private var outerRadius: CGFloat {
        size / 2
    }

    private var innerRadius: CGFloat {
        outerRadius * innerRadiusRatio
    }

    var path: Path {
        var path = Path()
        let center = CGPoint(x: size / 2, y: size / 2)

        let startAngleRad = Double(slice.startAngle - 90) * .pi / 180
        let endAngleRad = Double(slice.endAngle - 90) * .pi / 180

        // 计算外圆起始点和内圆结束点
        let outerStart = CGPoint(
            x: center.x + outerRadius * CGFloat(cos(startAngleRad)),
            y: center.y + outerRadius * CGFloat(sin(startAngleRad))
        )
        let innerEnd = CGPoint(
            x: center.x + innerRadius * CGFloat(cos(endAngleRad)),
            y: center.y + innerRadius * CGFloat(sin(endAngleRad))
        )

        // 绘制圆环段路径
        // 1. 从外圆起始点开始
        path.move(to: outerStart)
        // 2. 沿着外圆绘制到结束点
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(slice.startAngle - 90),
            endAngle: .degrees(slice.endAngle - 90),
            clockwise: false
        )
        // 3. 连接到内圆结束点
        path.addLine(to: innerEnd)
        // 4. 沿着内圆反向绘制回到起始点
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(slice.endAngle - 90),
            endAngle: .degrees(slice.startAngle - 90),
            clockwise: true
        )
        // 5. 闭合路径
        path.closeSubpath()

        return path
    }

    var body: some View {
        path
            .fill(slice.color)
            .overlay(
                path.stroke(Color(UIColor.systemBackground), lineWidth: 1.5)
            )
    }
}
