import SwiftUI
import Foundation

// 槽位类型定义
enum SlotType {
    case high
    case medium
    case low
    case rig
    case subsystem
}

// 槽位信息结构
struct SlotInfo {
    let id: Int
    let name: String
    let type: SlotType
}

struct BRKillMailFittingView: View {
    let killMailId: Int
    let databaseManager = DatabaseManager.shared
    
    // 槽位定义
    private let highSlots: [SlotInfo] = [
        SlotInfo(id: 27, name: "HiSlot0", type: .high),
        SlotInfo(id: 28, name: "HiSlot1", type: .high),
        SlotInfo(id: 29, name: "HiSlot2", type: .high),
        SlotInfo(id: 30, name: "HiSlot3", type: .high),
        SlotInfo(id: 31, name: "HiSlot4", type: .high),
        SlotInfo(id: 32, name: "HiSlot5", type: .high),
        SlotInfo(id: 33, name: "HiSlot6", type: .high),
        SlotInfo(id: 34, name: "HiSlot7", type: .high)
    ]
    
    private let mediumSlots: [SlotInfo] = [
        SlotInfo(id: 19, name: "MedSlot0", type: .medium),
        SlotInfo(id: 20, name: "MedSlot1", type: .medium),
        SlotInfo(id: 21, name: "MedSlot2", type: .medium),
        SlotInfo(id: 22, name: "MedSlot3", type: .medium),
        SlotInfo(id: 23, name: "MedSlot4", type: .medium),
        SlotInfo(id: 24, name: "MedSlot5", type: .medium),
        SlotInfo(id: 25, name: "MedSlot6", type: .medium),
        SlotInfo(id: 26, name: "MedSlot7", type: .medium)
    ]
    
    private let lowSlots: [SlotInfo] = [
        SlotInfo(id: 11, name: "LoSlot0", type: .low),
        SlotInfo(id: 12, name: "LoSlot1", type: .low),
        SlotInfo(id: 13, name: "LoSlot2", type: .low),
        SlotInfo(id: 14, name: "LoSlot3", type: .low),
        SlotInfo(id: 15, name: "LoSlot4", type: .low),
        SlotInfo(id: 16, name: "LoSlot5", type: .low),
        SlotInfo(id: 17, name: "LoSlot6", type: .low),
        SlotInfo(id: 18, name: "LoSlot7", type: .low)
    ]
    
    private let rigSlots: [SlotInfo] = [
        SlotInfo(id: 92, name: "RigSlot0", type: .rig),
        SlotInfo(id: 93, name: "RigSlot1", type: .rig),
        SlotInfo(id: 94, name: "RigSlot2", type: .rig)
    ]
    
    private let subsystemSlots: [SlotInfo] = [
        SlotInfo(id: 125, name: "SubSystem0", type: .subsystem),
        SlotInfo(id: 126, name: "SubSystem1", type: .subsystem),
        SlotInfo(id: 127, name: "SubSystem2", type: .subsystem),
        SlotInfo(id: 128, name: "SubSystem3", type: .subsystem)
    ]
    
    // 添加装备和飞船图片状态
    @State private var shipImage: Image?
    @State private var equipmentIcons: [Int: Image] = [:]
    @State private var isLoading = true
    
    // 从数据库批量获取图标文件名
    private func getIconFileNames(typeIds: [Int]) -> [Int: String] {
        guard !typeIds.isEmpty else { 
            Logger.debug("装配图标: 没有需要获取的图标")
            return [:] 
        }
        
        let placeholders = String(repeating: "?,", count: typeIds.count).dropLast()
        let query = """
            SELECT type_id, icon_filename 
            FROM types 
            WHERE type_id IN (\(placeholders))
        """
        
        Logger.debug("装配图标: 开始查询 \(typeIds.count) 个物品的图标")
        var iconFileNames: [Int: String] = [:]
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: typeIds) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let iconFileName = row["icon_filename"] as? String {
                    let finalIconName = iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
                    iconFileNames[typeId] = finalIconName
                    Logger.debug("装配图标: 物品ID \(typeId) 的图标文件名为 \(finalIconName)")
                }
            }
        }
        
        Logger.debug("装配图标: 成功获取 \(iconFileNames.count) 个图标文件名")
        return iconFileNames
    }
    
    // 加载 killmail 数据
    private func loadKillMailData() async {
        Logger.debug("装配图标: 开始加载 KillMail ID \(killMailId)")
        let url = URL(string: "https://kb.evetools.org/api/v1/killmails/\(killMailId)")!
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let victInfo = json["vict"] as? [String: Any],
               let items = victInfo["itms"] as? [[Int]],
               let shipId = victInfo["ship"] as? Int {
                
                Logger.debug("装配图标: 成功获取击毁数据，飞船ID: \(shipId)，装备数量: \(items.count)")
                
                // 收集所有需要获取图标的type_id
                var typeIds = [shipId]
                for item in items where item.count >= 4 {
                    typeIds.append(item[1])
                }
                
                Logger.debug("装配图标: 需要获取 \(typeIds.count) 个物品的图标")
                
                // 一次性获取所有图标文件名
                let iconFileNames = getIconFileNames(typeIds: typeIds)
                
                // 加载飞船图标
                if let shipIconFileName = iconFileNames[shipId] {
                    Logger.debug("装配图标: 加载飞船图标 \(shipIconFileName)")
                    await MainActor.run {
                        shipImage = IconManager.shared.loadImage(for: shipIconFileName)
                    }
                }
                
                // 加载装备图标
                for item in items {
                    guard item.count >= 4 else { continue }
                    let slotId = item[0]
                    let typeId = item[1]
                    
                    if let iconFileName = iconFileNames[typeId] {
                        Logger.debug("装配图标: 加载装备图标 - 槽位ID: \(slotId), 物品ID: \(typeId), 图标: \(iconFileName)")
                        await MainActor.run {
                            equipmentIcons[slotId] = IconManager.shared.loadImage(for: iconFileName)
                        }
                    }
                }
            }
        } catch {
            Logger.error("装配图标: 加载击毁数据失败 - \(error)")
        }
        
        await MainActor.run {
            isLoading = false
            Logger.debug("装配图标: 加载完成")
        }
    }
    
    // 计算每个槽位的位置
    private func calculateSlotPosition(
        center: CGPoint,
        radius: CGFloat,
        startAngle: Double,
        slotIndex: Int,
        totalSlots: Int,
        totalAngle: Double
    ) -> CGPoint {
        let slotWidth = totalAngle / Double(totalSlots)
        let angle = startAngle + slotWidth * Double(slotIndex) + (slotWidth / 2) // 加上半个槽位宽度使图标居中
        let radian = (angle - 90) * .pi / 180 // 调整为12点钟方向为0度
        
        return CGPoint(
            x: center.x + radius * Foundation.cos(radian),
            y: center.y + radius * Foundation.sin(radian)
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
            let outerRadius = geometry.size.width * 0.4 // 高中低槽环半径
            let slotOuterRadius = outerRadius - 1 // 高中低槽到外环的距离
            let slotInnerRadius = slotOuterRadius - 35 // 槽位扇形的高度
            let slotCenterRadius = (slotOuterRadius + slotInnerRadius) / 2 // 槽位中心线半径
            
            let innerCircleRadius = outerRadius * 0.6
            let innerSlotOuterRadius = innerCircleRadius - 5
            let innerSlotInnerRadius = innerSlotOuterRadius - 30
            let innerSlotCenterRadius = (innerSlotOuterRadius + innerSlotInnerRadius) / 2
            
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                // 基础圆环
                Circle()
                    .stroke(Color.gray.opacity(0.5), lineWidth: 3)
                    .frame(width: geometry.size.width * 0.85) // 最外环半径
                
                // 内环和飞船图片
                ZStack {
                    // 飞船图片（在内环中）
                    if let shipImage = shipImage {
                        shipImage
                            .resizable()
                            .scaledToFill()
                            .frame(width: innerCircleRadius * 2, height: innerCircleRadius * 2)
                            .clipShape(Circle())
                    }
                    
                    // 内环（覆盖在飞船图片上）
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: innerCircleRadius * 2)
                }
                
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
                
                // 高槽装备图标
                ForEach(0..<8) { index in
                    if let icon = equipmentIcons[highSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .position(calculateSlotPosition(
                                center: center,
                                radius: slotCenterRadius,
                                startAngle: -52,
                                slotIndex: index,
                                totalSlots: 8,
                                totalAngle: 104
                            ))
                    }
                }
                
                // 低槽装备图标
                ForEach(0..<8) { index in
                    if let icon = equipmentIcons[lowSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .position(calculateSlotPosition(
                                center: center,
                                radius: slotCenterRadius,
                                startAngle: 68,
                                slotIndex: index,
                                totalSlots: 8,
                                totalAngle: 104
                            ))
                    }
                }
                
                // 中槽装备图标
                ForEach(0..<8) { index in
                    if let icon = equipmentIcons[mediumSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .position(calculateSlotPosition(
                                center: center,
                                radius: slotCenterRadius,
                                startAngle: 188,
                                slotIndex: index,
                                totalSlots: 8,
                                totalAngle: 104
                            ))
                    }
                }
                
                // 装备架图标
                ForEach(0..<3) { index in
                    if let icon = equipmentIcons[rigSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .position(calculateSlotPosition(
                                center: center,
                                radius: innerSlotCenterRadius,
                                startAngle: 142,
                                slotIndex: index,
                                totalSlots: 3,
                                totalAngle: 76
                            ))
                    }
                }
                
                // 子系统图标
                ForEach(0..<4) { index in
                    if let icon = equipmentIcons[subsystemSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .position(calculateSlotPosition(
                                center: center,
                                radius: innerSlotCenterRadius,
                                startAngle: -48,
                                slotIndex: index,
                                totalSlots: 4,
                                totalAngle: 96
                            ))
                    }
                }
                
                if isLoading {
                    ProgressView()
                }
            }
        }
        .onAppear {
            Task {
                await loadKillMailData()
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
        BRKillMailFittingView(killMailId: 123738476) // 使用一个实际的 killmail ID
            .frame(width: 400, height: 400)
            .preferredColorScheme(.dark)
    }
} 
