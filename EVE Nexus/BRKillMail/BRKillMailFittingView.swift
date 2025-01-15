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
    
    // 添加飞船图片状态
    @State private var shipImage: Image?
    @State private var shipTypeId: Int?
    @State private var equipmentIcons: [Int: Image] = [:]
    @State private var isLoading = true
    
    // 从EVE官方API加载飞船图片
    private func loadShipImage(typeId: Int) async {
        let urlString = "https://images.evetech.net/types/\(typeId)/render"
        guard let url = URL(string: urlString) else {
            Logger.error("装配图标: 无效的飞船图片URL")
            return
        }
        
        do {
            let data = try await NetworkManager.shared.fetchData(from: url)
            if let uiImage = UIImage(data: data) {
                await MainActor.run {
                    shipImage = Image(uiImage: uiImage)
                    Logger.debug("装配图标: 成功加载飞船图片 - TypeID: \(typeId)")
                }
            }
        } catch {
            Logger.error("装配图标: 加载飞船图片失败 - \(error)")
        }
    }
    
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
                
                // 加载飞船图片
                await loadShipImage(typeId: shipId)
                
                // 收集所有需要获取图标的type_id
                var typeIds: [Int] = []
                for item in items where item.count >= 4 {
                    typeIds.append(item[1])
                }
                
                Logger.debug("装配图标: 需要获取 \(typeIds.count) 个物品的图标")
                
                // 一次性获取所有图标文件名
                let iconFileNames = getIconFileNames(typeIds: typeIds)
                
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
            let minSize = min(geometry.size.width, geometry.size.height)
            let baseSize: CGFloat = 400 // 基准尺寸
            let scale = minSize / baseSize // 计算缩放比例
            let center = CGPoint(x: geometry.size.width/2, y: geometry.size.height/2)
            
            // 基础尺寸计算
            let baseRadius: CGFloat = 180 // 基础半径
            let scaledRadius = baseRadius * scale
            
            // 外环计算
            let outerCircleRadius = scaledRadius // 最外圈圆环
            let outerStrokeWidth: CGFloat = 2 * scale // 外圈线条宽度
            
            // 装备槽位圆环计算
            let slotOuterRadius = scaledRadius - (10 * scale) // 槽位外圈
            let slotInnerRadius = slotOuterRadius - (35 * scale) // 槽位内圈
            let slotCenterRadius = (slotOuterRadius + slotInnerRadius) / 2 // 装备图标放置半径
            
            // 中心圆环计算
            let innerCircleRadius = scaledRadius * 0.6 // 中心圆环半径
            let innerStrokeWidth: CGFloat = 1.5 * scale // 内圈线条宽度
            
            // 内部装备槽位圆环（装备架和子系统）
            let innerSlotOuterRadius = innerCircleRadius - (5 * scale)
            let innerSlotInnerRadius = innerSlotOuterRadius - (30 * scale)
            let innerSlotCenterRadius = (innerSlotOuterRadius + innerSlotInnerRadius) / 2
            
            // 装备图标尺寸
            let equipmentIconSize: CGFloat = 32 * scale
            
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                // 基础圆环
                Circle()
                    .stroke(Color.gray.opacity(0.5), lineWidth: outerStrokeWidth)
                    .frame(width: outerCircleRadius * 2)
                
                // 内环和飞船图片
                ZStack {
                    // 飞船图片（在内环中）
                    if let shipImage = shipImage {
                        shipImage
                            .resizable()
                            .scaledToFit()
                            .frame(width: innerCircleRadius * 2, height: innerCircleRadius * 2)
                            .clipShape(Circle())
                    }
                    
                    // 内环（覆盖在飞船图片上）
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                        .frame(width: innerCircleRadius * 2)
                }
                
                // 区域分隔线
                ForEach([60.0, 180.0, 300.0], id: \.self) { angle in
                    SectionDivider(
                        center: center,
                        radius: slotOuterRadius,
                        angle: angle,
                        strokeWidth: outerStrokeWidth,
                        scale: scale
                    )
                    .stroke(Color.gray.opacity(0.5), lineWidth: outerStrokeWidth)
                }
                
                // 高槽区域 (-56° to 56°, 顶部12点位置)
                SlotSection(
                    center: center,
                    innerRadius: slotInnerRadius,
                    outerRadius: slotOuterRadius,
                    startAngle: -52,
                    endAngle: 52,
                    use12OClock: true,
                    slotCount: 8,
                    strokeWidth: innerStrokeWidth
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                
                // 右侧低槽区域 (64° to 176°, 4点位置)
                SlotSection(
                    center: center,
                    innerRadius: slotInnerRadius,
                    outerRadius: slotOuterRadius,
                    startAngle: 68,
                    endAngle: 172,
                    use12OClock: true,
                    slotCount: 8,
                    strokeWidth: innerStrokeWidth
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                
                // 左侧中槽区域 (184° to 296°, 8点位置)
                SlotSection(
                    center: center,
                    innerRadius: slotInnerRadius,
                    outerRadius: slotOuterRadius,
                    startAngle: 188,
                    endAngle: 292,
                    use12OClock: true,
                    slotCount: 8,
                    strokeWidth: innerStrokeWidth
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                
                // 底部装备架区域（3个槽位）
                SlotSection(
                    center: center,
                    innerRadius: innerSlotInnerRadius,
                    outerRadius: innerSlotOuterRadius,
                    startAngle: 142,
                    endAngle: 218,
                    use12OClock: true,
                    slotCount: 3,
                    strokeWidth: innerStrokeWidth
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                
                // 顶部子系统区域（4个槽位）
                SlotSection(
                    center: center,
                    innerRadius: innerSlotInnerRadius,
                    outerRadius: innerSlotOuterRadius,
                    startAngle: -48,
                    endAngle: 48,
                    use12OClock: true,
                    slotCount: 4,
                    strokeWidth: innerStrokeWidth
                )
                .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                
                // 高槽装备图标
                ForEach(0..<8) { index in
                    if let icon = equipmentIcons[highSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
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
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
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
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
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
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
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
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
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
    let strokeWidth: CGFloat
    let scale: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let adjustment = -90.0 // 调整角度以匹配12点钟方向为0度
        let radian = (angle + adjustment) * .pi / 180
        
        let outerPoint = CGPoint(
            x: center.x + radius * Foundation.cos(radian),
            y: center.y + radius * Foundation.sin(radian)
        )
        
        let dividerLength: CGFloat = 30 * scale // 分隔线长度
        let innerPoint = CGPoint(
            x: center.x + (radius - dividerLength) * Foundation.cos(radian),
            y: center.y + (radius - dividerLength) * Foundation.sin(radian)
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
    let strokeWidth: CGFloat
    
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
        let slotWidth = totalAngle / Double(slotCount)
        
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
