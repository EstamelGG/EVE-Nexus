import SwiftUI

struct WealthPieSlice: Identifiable {
    let id = UUID()
    let type: WealthType
    let value: Double
    let percentage: Double
    let startAngle: Double
    let endAngle: Double
    let color: Color
    
    var midAngle: Double {
        (startAngle + endAngle) / 2
    }
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
        case .wallet:
            return .purple
        }
    }
    
    var body: some View {
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
            
            if let selected = selectedSlice {
                // 显示选中片段的详细信息
                VStack {
                    Text(NSLocalizedString("Wealth_\(selected.type.rawValue)", comment: ""))
                        .font(.headline)
                    Text(String(format: "%.1f%%", selected.percentage))
                        .font(.subheadline)
                    Text(FormatUtil.formatISK(selected.value) + " ISK")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(UIColor.systemBackground).opacity(0.8))
                .cornerRadius(8)
            }
        }
        .frame(width: size, height: size)
    }
}

struct PieSliceView: View {
    let slice: WealthPieSlice
    let size: CGFloat
    
    var path: Path {
        var path = Path()
        let center = CGPoint(x: size/2, y: size/2)
        let radius = size/2
        
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(slice.startAngle - 90),
            endAngle: .degrees(slice.endAngle - 90),
            clockwise: false
        )
        path.closeSubpath()
        
        return path
    }
    
    var body: some View {
        path
            .fill(slice.color)
            .overlay(
                path.stroke(Color(UIColor.systemBackground), lineWidth: 2)
            )
    }
} 