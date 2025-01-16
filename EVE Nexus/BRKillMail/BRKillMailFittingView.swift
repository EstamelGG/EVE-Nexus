import SwiftUI
import Foundation
import Kingfisher

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
    let killMailData: [String: Any]  // 替换 killMailId，直接接收 JSON 数据
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
        
        let processor = DownsamplingImageProcessor(size: CGSize(width: 300, height: 300))
        let options: KingfisherOptionsInfo = [
            .processor(processor),
            .scaleFactor(UIScreen.main.scale),
            .cacheOriginalImage,
            .memoryCacheExpiration(.days(7)),
            .diskCacheExpiration(.days(30))
        ]
        
        await withCheckedContinuation { continuation in
            KingfisherManager.shared.retrieveImage(with: KF.ImageResource(downloadURL: url), options: options) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let imageResult):
                        shipImage = Image(uiImage: imageResult.image)
                        Logger.debug("装配图标: 成功加载飞船图片 - TypeID: \(typeId)")
                    case .failure(let error):
                        Logger.error("装配图标: 加载飞船图片失败 - \(error)")
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    // 从数据库批量获取图标文件名和类别信息
    private func getIconFileNames(typeIds: [Int]) -> [Int: (String, Int)] {
        guard !typeIds.isEmpty else { 
            Logger.debug("装配图标: 没有需要获取的图标")
            return [:] 
        }
        
        // 对 typeIds 进行去重
        let uniqueTypeIds = Array(Set(typeIds))
        Logger.debug("装配图标: 原始物品ID数量: \(typeIds.count)，去重后数量: \(uniqueTypeIds.count)")
        
        let placeholders = String(repeating: "?,", count: uniqueTypeIds.count).dropLast()
        let query = """
            SELECT type_id, icon_filename, categoryID
            FROM types 
            WHERE type_id IN (\(placeholders))
        """
        
        Logger.debug("装配图标: 开始查询 \(uniqueTypeIds.count) 个物品的图标")
        var iconFileNames: [Int: (String, Int)] = [:]
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: uniqueTypeIds) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let iconFileName = row["icon_filename"] as? String,
                   let categoryId = row["categoryID"] as? Int {
                    let finalIconName = iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
                    iconFileNames[typeId] = (finalIconName, categoryId)
                    Logger.debug("装配图标: 物品ID \(typeId) 的图标文件名为 \(finalIconName), 类别ID: \(categoryId)")
                }
            }
        }
        
        Logger.debug("装配图标: 成功获取 \(iconFileNames.count) 个图标文件名")
        return iconFileNames
    }
    
    // 加载 killmail 数据
    private func loadKillMailData() async {
        if let victInfo = killMailData["vict"] as? [String: Any],
           let items = victInfo["itms"] as? [[Int]],
           let shipId = victInfo["ship"] as? Int {
            
            Logger.debug("装配图标: 开始处理击毁数据，飞船ID: \(shipId)，装备数量: \(items.count)")
            
            // 加载飞船图片
            await loadShipImage(typeId: shipId)
            
            // 按槽位ID分组物品，并收集所有不重复的typeId
            var slotItems: [Int: [[Int]]] = [:] // [slotId: [[slotId, typeId, ...]]]
            var uniqueTypeIds = Set<Int>() // 使用Set来存储不重复的typeId
            
            for item in items where item.count >= 4 {
                let slotId = item[0]
                let typeId = item[1]
                
                if slotItems[slotId] == nil {
                    slotItems[slotId] = []
                }
                slotItems[slotId]?.append(item)
                uniqueTypeIds.insert(typeId)
            }
            
            Logger.debug("装配图标: 收集到 \(uniqueTypeIds.count) 个不重复物品ID")
            
            // 查询所有物品的图标文件名和类别信息
            let typeInfos = getIconFileNames(typeIds: Array(uniqueTypeIds))
            
            // 处理每个槽位的装备
            for (slotId, items) in slotItems {
                // 过滤掉弹药类装备（categoryId = 8）
                let nonAmmoItems = items.filter { item in
                    if let typeInfo = typeInfos[item[1]] {
                        return typeInfo.1 != 8  // 不是弹药类
                    }
                    return false
                }
                
                // 如果有非弹药装备，使用第一个
                if let firstItem = nonAmmoItems.first,
                   let typeInfo = typeInfos[firstItem[1]] {
                    await MainActor.run {
                        equipmentIcons[slotId] = IconManager.shared.loadImage(for: typeInfo.0)
                    }
                    Logger.debug("装配图标: 加载装备图标 - 槽位ID: \(slotId), 物品ID: \(firstItem[1]), 图标: \(typeInfo.0)")
                }
            }
        } else {
            Logger.error("装配图标: 无效的击毁数据格式")
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
            let baseRadius: CGFloat = 190 // 基础半径
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
                // 添加阴影背景
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: outerCircleRadius * 2)
                    .shadow(color: Color.primary.opacity(0.2), radius: 8, x: 0, y: 4)
                
                // 添加内部黑色圆形背景（在飞船环和最外环之间）
                Circle()
                    .fill(Color.black.opacity(0.8))
                    .frame(width: outerCircleRadius * 2)
                
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
        // 创建一个示例 JSON 数据用于预览
        let sampleData: [String: Any] = [
            "vict": [
                "ship": 123456,
                "itms": [[27, 12345, 1, 1]]
            ]
        ]
        BRKillMailFittingView(killMailData: sampleData)
            .frame(width: 400, height: 400)
            .preferredColorScheme(.dark)
    }
} 
