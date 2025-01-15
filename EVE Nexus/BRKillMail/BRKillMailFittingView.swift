import SwiftUI
import Foundation

struct BRKillMailFittingView: View {
    var body: some View {
        GeometryReader { geometry in
            let outerRadius = geometry.size.width * 0.475 // 外环半径
            let slotOuterRadius = outerRadius - 5 // 槽位区域的外半径，与外环保持10的间距
            let slotInnerRadius = slotOuterRadius - 36 // 槽位区域的内半径
            
            // 内环相关尺寸
            let innerCircleRadius = outerRadius * 0.55 // 内环半径约为外环的45%
            let innerSlotOuterRadius = innerCircleRadius - 5 // 内环槽位外半径，与内环保持10的间距
            let innerSlotInnerRadius = innerSlotOuterRadius - 30 // 内环槽位内半径
            
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                // 基础圆环
                Circle()
                    .stroke(Color.gray.opacity(0.5), lineWidth: 3)
                    .frame(width: geometry.size.width * 0.95)
                
                // 内环
                Circle()
                    .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                    .frame(width: innerCircleRadius * 2) // 直径为半径的2倍
                
                // 区域分隔线
                ForEach([60.0, 180.0, 300.0], id: \.self) { angle in
                    SectionDivider(
                        center: CGPoint(x: geometry.size.width/2, y: geometry.size.height/2),
                        radius: outerRadius,
                        angle: angle
                    )
                    .stroke(Color.gray.opacity(0.5), lineWidth: 3)
                }
                
                // 高槽区域 (-56° to 56°, 顶部12点位置)
                SlotSection(
                    center: CGPoint(x: geometry.size.width/2, y: geometry.size.height/2),
                    innerRadius: slotInnerRadius,
                    outerRadius: slotOuterRadius,
                    startAngle: -52,
                    endAngle: 52,
                    use12OClock: true,
                    slotCount: 8
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                
                // 右侧低槽区域 (64° to 176°, 4点位置)
                SlotSection(
                    center: CGPoint(x: geometry.size.width/2, y: geometry.size.height/2),
                    innerRadius: slotInnerRadius,
                    outerRadius: slotOuterRadius,
                    startAngle: 68,
                    endAngle: 172,
                    use12OClock: true,
                    slotCount: 8
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                
                // 左侧中槽区域 (184° to 296°, 8点位置)
                SlotSection(
                    center: CGPoint(x: geometry.size.width/2, y: geometry.size.height/2),
                    innerRadius: slotInnerRadius,
                    outerRadius: slotOuterRadius,
                    startAngle: 188,
                    endAngle: 292,
                    use12OClock: true,
                    slotCount: 8
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                
                // 底部装备架区域（3个槽位，每个槽位28度）
                SlotSection(
                    center: CGPoint(x: geometry.size.width/2, y: geometry.size.height/2),
                    innerRadius: innerSlotInnerRadius,
                    outerRadius: innerSlotOuterRadius,
                    startAngle: 142,
                    endAngle: 218,
                    use12OClock: true,
                    slotCount: 3
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                
                // 顶部子系统区域（4个槽位，每个槽位28度）
                SlotSection(
                    center: CGPoint(x: geometry.size.width/2, y: geometry.size.height/2),
                    innerRadius: innerSlotInnerRadius,
                    outerRadius: innerSlotOuterRadius,
                    startAngle: -48,
                    endAngle: 48,
                    use12OClock: true,
                    slotCount: 4
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
            }
        }
    }
}

// 区域分隔线
struct SectionDivider: Shape {
    let center: CGPoint
    let radius: CGFloat
    let angle: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let adjustment = -90.0 // 调整角度以匹配12点钟方向为0度
        let radian = (angle + adjustment) * .pi / 180
        
        let outerPoint = CGPoint(
            x: center.x + radius * Foundation.cos(radian),
            y: center.y + radius * Foundation.sin(radian)
        )
        
        let innerPoint = CGPoint(
            x: center.x + (radius - 30) * Foundation.cos(radian),
            y: center.y + (radius - 30) * Foundation.sin(radian)
        )
        
        path.move(to: innerPoint)
        path.addLine(to: outerPoint)
        
        return path
    }
}

// 槽位区域形状
struct SlotSection: Shape {
    let center: CGPoint
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let startAngle: Double
    let endAngle: Double
    let use12OClock: Bool
    let slotCount: Int
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let adjustment = -90.0 // 将0度从3点钟位置调整到12点钟位置
        
        // 绘制主弧形
        let startRadian = (startAngle + adjustment) * .pi / 180
        let endRadian = (endAngle + adjustment) * .pi / 180
        
        // 绘制外弧
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .radians(startRadian),
            endAngle: .radians(endRadian),
            clockwise: false
        )
        
        // 绘制内弧
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .radians(endRadian),
            endAngle: .radians(startRadian),
            clockwise: true
        )
        
        // 绘制分隔线
        let totalAngle = endAngle - startAngle
        let slotWidth = totalAngle / Double(slotCount) // 将总角度分成8份
        
        // 绘制所有分隔线（包括起始和结束位置）
        for i in 0...slotCount {
            let angle = startAngle + slotWidth * Double(i)
            let radian = (angle + adjustment) * .pi / 180
            
            let innerPoint = CGPoint(
                x: center.x + innerRadius * Foundation.cos(radian),
                y: center.y + innerRadius * Foundation.sin(radian)
            )
            let outerPoint = CGPoint(
                x: center.x + outerRadius * Foundation.cos(radian),
                y: center.y + outerRadius * Foundation.sin(radian)
            )
            
            path.move(to: innerPoint)
            path.addLine(to: outerPoint)
        }
        
        path.closeSubpath()
        return path
    }
}

// 预览
struct BRKillMailFittingView_Previews: PreviewProvider {
    static var previews: some View {
        BRKillMailFittingView()
            .frame(width: 400, height: 400)
            .preferredColorScheme(.dark)
    }
} 
