import Foundation
import Kingfisher
import SwiftUI

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

// 槽位配置结构
struct ShipSlotConfig {
    var highSlots: Int = 0
    var mediumSlots: Int = 0
    var lowSlots: Int = 0
    var rigSlots: Int = 0
    var subsystemSlots: Int = 0
}

struct BRKillMailFittingView: View {
    let killMailData: [String: Any]  // 替换 killMailId，直接接收 JSON 数据
    let databaseManager = DatabaseManager.shared

    // 添加状态变量存储实际槽位配置
    @State private var actualSlotConfig = ShipSlotConfig()

    // 槽位定义
    private let highSlots: [SlotInfo] = [
        SlotInfo(id: 27, name: "HiSlot0", type: .high),
        SlotInfo(id: 28, name: "HiSlot1", type: .high),
        SlotInfo(id: 29, name: "HiSlot2", type: .high),
        SlotInfo(id: 30, name: "HiSlot3", type: .high),
        SlotInfo(id: 31, name: "HiSlot4", type: .high),
        SlotInfo(id: 32, name: "HiSlot5", type: .high),
        SlotInfo(id: 33, name: "HiSlot6", type: .high),
        SlotInfo(id: 34, name: "HiSlot7", type: .high),
    ]

    private let mediumSlots: [SlotInfo] = [
        SlotInfo(id: 19, name: "MedSlot0", type: .medium),
        SlotInfo(id: 20, name: "MedSlot1", type: .medium),
        SlotInfo(id: 21, name: "MedSlot2", type: .medium),
        SlotInfo(id: 22, name: "MedSlot3", type: .medium),
        SlotInfo(id: 23, name: "MedSlot4", type: .medium),
        SlotInfo(id: 24, name: "MedSlot5", type: .medium),
        SlotInfo(id: 25, name: "MedSlot6", type: .medium),
        SlotInfo(id: 26, name: "MedSlot7", type: .medium),
    ]

    private let lowSlots: [SlotInfo] = [
        SlotInfo(id: 11, name: "LoSlot0", type: .low),
        SlotInfo(id: 12, name: "LoSlot1", type: .low),
        SlotInfo(id: 13, name: "LoSlot2", type: .low),
        SlotInfo(id: 14, name: "LoSlot3", type: .low),
        SlotInfo(id: 15, name: "LoSlot4", type: .low),
        SlotInfo(id: 16, name: "LoSlot5", type: .low),
        SlotInfo(id: 17, name: "LoSlot6", type: .low),
        SlotInfo(id: 18, name: "LoSlot7", type: .low),
    ]

    private let rigSlots: [SlotInfo] = [
        SlotInfo(id: 92, name: "RigSlot0", type: .rig),
        SlotInfo(id: 93, name: "RigSlot1", type: .rig),
        SlotInfo(id: 94, name: "RigSlot2", type: .rig),
    ]

    private let subsystemSlots: [SlotInfo] = [
        SlotInfo(id: 125, name: "SubSystem0", type: .subsystem),
        SlotInfo(id: 126, name: "SubSystem1", type: .subsystem),
        SlotInfo(id: 127, name: "SubSystem2", type: .subsystem),
        SlotInfo(id: 128, name: "SubSystem3", type: .subsystem),
    ]

    // 添加飞船图片状态
    @State private var shipImage: Image?
    @State private var shipTypeId: Int?
    @State private var equipmentIcons: [Int: Image] = [:]
    @State private var isLoading = true

    // 从EVE官方API加载飞船图片
    private func loadShipImage(typeId: Int) async {
        do {
            let image = try await ItemRenderAPI.shared.fetchItemRender(typeId: typeId, size: 512)
            await MainActor.run {
                shipImage = Image(uiImage: image)
                Logger.debug("装配图标: 成功加载飞船图片 - TypeID: \(typeId)")
            }
        } catch {
            Logger.error("装配图标: 加载飞船图片失败 - \(error)")
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
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: uniqueTypeIds)
        {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let iconFileName = row["icon_filename"] as? String,
                    let categoryId = row["categoryID"] as? Int
                {
                    let finalIconName =
                        iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName
                    iconFileNames[typeId] = (finalIconName, categoryId)
                    Logger.debug(
                        "装配图标: 物品ID \(typeId) 的图标文件名为 \(finalIconName), 类别ID: \(categoryId)")
                }
            }
        }

        Logger.debug("装配图标: 成功获取 \(iconFileNames.count) 个图标文件名")
        return iconFileNames
    }

    // 加载 killmail 数据
    private func loadKillMailData() async {
        // 首先尝试获取飞船ID并加载飞船图片
        if let victInfo = killMailData["vict"] as? [String: Any],
           let shipId = victInfo["ship"] as? Int {
            await loadShipImage(typeId: shipId)
        }
        
        // 然后处理装备数据
        if let victInfo = killMailData["vict"] as? [String: Any],
           let items = victInfo["itms"] as? [[Int]],
           let shipId = victInfo["ship"] as? Int {
            Logger.debug("装配图标: 开始处理击毁数据，飞船ID: \(shipId)，装备数量: \(items.count)")

            // 按槽位ID分组物品，并收集所有不重复的typeId
            var slotItems: [Int: [[Int]]] = [:]
            var uniqueTypeIds = Set<Int>()

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

            // 初始化槽位配置
            await initializeSlotConfig(shipId: shipId, items: items, typeInfos: typeInfos)

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
                    let typeInfo = typeInfos[firstItem[1]]
                {
                    await MainActor.run {
                        equipmentIcons[slotId] = IconManager.shared.loadImage(for: typeInfo.0)
                    }
                    Logger.debug(
                        "装配图标: 加载装备图标 - 槽位ID: \(slotId), 物品ID: \(firstItem[1]), 图标: \(typeInfo.0)")
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
        maxSlots: Int,  // 改为使用最大槽位数
        totalAngle: Double
    ) -> CGPoint {
        let slotWidth = totalAngle / Double(maxSlots)
        let angle = startAngle + slotWidth * Double(slotIndex) + (slotWidth / 2)
        let radian = (angle - 90) * .pi / 180

        return CGPoint(
            x: center.x + radius * Foundation.cos(radian),
            y: center.y + radius * Foundation.sin(radian)
        )
    }

    // 获取船只基础槽位配置
    private func getShipBaseSlotConfig(typeId: Int) async -> ShipSlotConfig {
        var config = ShipSlotConfig()

        let query = """
                SELECT high_slot, mid_slot, low_slot, rig_slot, groupID
                FROM types
                WHERE type_id = ?
            """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeId]),
            let row = rows.first
        {
            config.highSlots = (row["high_slot"] as? Int) ?? 0
            config.mediumSlots = (row["mid_slot"] as? Int) ?? 0
            config.lowSlots = (row["low_slot"] as? Int) ?? 0
            config.rigSlots = (row["rig_slot"] as? Int) ?? 0

            // 检查是否为T3巡洋舰（groupID = 963）
            if let groupId = row["groupID"] as? Int, groupId == 963 {
                config.subsystemSlots = 4
            }
        }

        Logger.debug(
            "船只槽位配置: typeId=\(typeId), high=\(config.highSlots), mid=\(config.mediumSlots), low=\(config.lowSlots), rig=\(config.rigSlots), subsystem=\(config.subsystemSlots)"
        )
        return config
    }

    // 计算实际装配的非弹药装备数量
    private func calculateActualFittedSlots(
        items: [[Int]], typeInfos: [Int: (String, Int)], slotRange: Range<Int>
    ) -> Int {
        var fittedSlots = Set<Int>()

        for item in items {
            let slotId = item[0]
            let typeId = item[1]

            // 检查是否在指定槽位范围内且不是弹药
            if slotRange.contains(slotId),
                let typeInfo = typeInfos[typeId],
                typeInfo.1 != 8
            {
                fittedSlots.insert(slotId)
            }
        }

        return fittedSlots.count
    }

    // 初始化实际槽位配置
    private func initializeSlotConfig(shipId: Int, items: [[Int]], typeInfos: [Int: (String, Int)])
        async
    {
        // 获取基础配置
        let baseConfig = await getShipBaseSlotConfig(typeId: shipId)

        // 计算实际装配的槽位数量
        let actualHighSlots = calculateActualFittedSlots(
            items: items, typeInfos: typeInfos, slotRange: 27..<35
        )
        let actualMediumSlots = calculateActualFittedSlots(
            items: items, typeInfos: typeInfos, slotRange: 19..<27
        )
        let actualLowSlots = calculateActualFittedSlots(
            items: items, typeInfos: typeInfos, slotRange: 11..<19
        )
        let actualRigSlots = calculateActualFittedSlots(
            items: items, typeInfos: typeInfos, slotRange: 92..<95
        )
        let actualSubsystemSlots = calculateActualFittedSlots(
            items: items, typeInfos: typeInfos, slotRange: 125..<129
        )

        // 确定最终槽位数量
        await MainActor.run {
            actualSlotConfig.highSlots = min(8, max(baseConfig.highSlots, actualHighSlots))
            actualSlotConfig.mediumSlots = min(8, max(baseConfig.mediumSlots, actualMediumSlots))
            actualSlotConfig.lowSlots = min(8, max(baseConfig.lowSlots, actualLowSlots))
            actualSlotConfig.rigSlots = min(3, max(baseConfig.rigSlots, actualRigSlots))
            actualSlotConfig.subsystemSlots = min(
                4, max(baseConfig.subsystemSlots, actualSubsystemSlots)
            )
        }

        Logger.debug(
            """
            实际槽位配置:
            高槽: \(actualSlotConfig.highSlots) (基础:\(baseConfig.highSlots), 实装:\(actualHighSlots))
            中槽: \(actualSlotConfig.mediumSlots) (基础:\(baseConfig.mediumSlots), 实装:\(actualMediumSlots))
            低槽: \(actualSlotConfig.lowSlots) (基础:\(baseConfig.lowSlots), 实装:\(actualLowSlots))
            改装: \(actualSlotConfig.rigSlots) (基础:\(baseConfig.rigSlots), 实装:\(actualRigSlots))
            子系统: \(actualSlotConfig.subsystemSlots) (基础:\(baseConfig.subsystemSlots), 实装:\(actualSubsystemSlots))
            """)
    }

    var body: some View {
        GeometryReader { geometry in
            let minSize = min(geometry.size.width, geometry.size.height)
            let baseSize: CGFloat = 400
            let scale = minSize / baseSize
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            let baseRadius: CGFloat = 190
            let scaledRadius = baseRadius * scale

            let outerCircleRadius = scaledRadius
            let outerStrokeWidth: CGFloat = 2 * scale

            let slotOuterRadius = scaledRadius - (10 * scale)
            let slotInnerRadius = slotOuterRadius - (35 * scale)
            let slotCenterRadius = (slotOuterRadius + slotInnerRadius) / 2

            let innerCircleRadius = scaledRadius * 0.6
            let innerStrokeWidth: CGFloat = 1.5 * scale

            let innerSlotOuterRadius = innerCircleRadius - (5 * scale)
            let innerSlotInnerRadius = innerSlotOuterRadius - (30 * scale)
            let innerSlotCenterRadius = (innerSlotOuterRadius + innerSlotInnerRadius) / 2

            let equipmentIconSize: CGFloat = 32 * scale

            ZStack {
                // 外层阴影和发光效果
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: outerCircleRadius * 2)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.2), lineWidth: 3)
                    )
                    .shadow(
                        color: Color.primary.opacity(0.3),
                        radius: 16,
                        x: 0,
                        y: 8
                    )

                // 内部发光效果
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: outerCircleRadius * 2)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.primary.opacity(0.3),
                                        Color.primary.opacity(0.1),
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(
                        color: Color.primary.opacity(0.2),
                        radius: 8,
                        x: 0,
                        y: 4
                    )

                // 基础圆环
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.gray.opacity(0.6),
                                Color.gray.opacity(0.3),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: outerStrokeWidth
                    )
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
                        .stroke(Color.primary.opacity(0.6), lineWidth: innerStrokeWidth)
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
                    .stroke(Color.primary.opacity(0.4), lineWidth: outerStrokeWidth)
                }

                // 高槽区域 (-52° to 52°)
                if actualSlotConfig.highSlots > 0 {
                    SlotSection(
                        center: center,
                        innerRadius: slotInnerRadius,
                        outerRadius: slotOuterRadius,
                        startAngle: -52,
                        endAngle: 52,
                        use12OClock: true,
                        maxSlots: 8,
                        actualSlots: actualSlotConfig.highSlots,
                        strokeWidth: innerStrokeWidth
                    )
                    .stroke(Color.gray.opacity(0.8), lineWidth: innerStrokeWidth)
                }

                // 低槽区域 (68° to 172°)
                if actualSlotConfig.lowSlots > 0 {
                    SlotSection(
                        center: center,
                        innerRadius: slotInnerRadius,
                        outerRadius: slotOuterRadius,
                        startAngle: 68,
                        endAngle: 172,
                        use12OClock: true,
                        maxSlots: 8,
                        actualSlots: actualSlotConfig.lowSlots,
                        strokeWidth: innerStrokeWidth
                    )
                    .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                }

                // 中槽区域 (188° to 292°)
                if actualSlotConfig.mediumSlots > 0 {
                    SlotSection(
                        center: center,
                        innerRadius: slotInnerRadius,
                        outerRadius: slotOuterRadius,
                        startAngle: 188,
                        endAngle: 292,
                        use12OClock: true,
                        maxSlots: 8,
                        actualSlots: actualSlotConfig.mediumSlots,
                        strokeWidth: innerStrokeWidth
                    )
                    .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                }

                // 改装槽区域 (142° to 218°)
                if actualSlotConfig.rigSlots > 0 {
                    SlotSection(
                        center: center,
                        innerRadius: innerSlotInnerRadius,
                        outerRadius: innerSlotOuterRadius,
                        startAngle: 142,
                        endAngle: 218,
                        use12OClock: true,
                        maxSlots: 3,
                        actualSlots: actualSlotConfig.rigSlots,
                        strokeWidth: innerStrokeWidth
                    )
                    .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                }

                // 子系统区域 (-48° to 48°)
                if actualSlotConfig.subsystemSlots > 0 {
                    SlotSection(
                        center: center,
                        innerRadius: innerSlotInnerRadius,
                        outerRadius: innerSlotOuterRadius,
                        startAngle: -48,
                        endAngle: 48,
                        use12OClock: true,
                        maxSlots: 4,
                        actualSlots: actualSlotConfig.subsystemSlots,
                        strokeWidth: innerStrokeWidth
                    )
                    .stroke(Color.gray.opacity(0.5), lineWidth: innerStrokeWidth)
                }

                // 高槽装备图标
                ForEach(0..<actualSlotConfig.highSlots, id: \.self) { index in
                    if let icon = equipmentIcons[highSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
                            .position(
                                calculateSlotPosition(
                                    center: center,
                                    radius: slotCenterRadius,
                                    startAngle: -52,
                                    slotIndex: index,
                                    maxSlots: 8,
                                    totalAngle: 104
                                ))
                    }
                }

                // 低槽装备图标
                ForEach(0..<actualSlotConfig.lowSlots, id: \.self) { index in
                    if let icon = equipmentIcons[lowSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
                            .position(
                                calculateSlotPosition(
                                    center: center,
                                    radius: slotCenterRadius,
                                    startAngle: 68,
                                    slotIndex: index,
                                    maxSlots: 8,
                                    totalAngle: 104
                                ))
                    }
                }

                // 中槽装备图标
                ForEach(0..<actualSlotConfig.mediumSlots, id: \.self) { index in
                    if let icon = equipmentIcons[mediumSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
                            .position(
                                calculateSlotPosition(
                                    center: center,
                                    radius: slotCenterRadius,
                                    startAngle: 188,
                                    slotIndex: index,
                                    maxSlots: 8,
                                    totalAngle: 104
                                ))
                    }
                }

                // 改装槽图标
                ForEach(0..<actualSlotConfig.rigSlots, id: \.self) { index in
                    if let icon = equipmentIcons[rigSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
                            .position(
                                calculateSlotPosition(
                                    center: center,
                                    radius: innerSlotCenterRadius,
                                    startAngle: 142,
                                    slotIndex: index,
                                    maxSlots: 3,
                                    totalAngle: 76
                                ))
                    }
                }

                // 子系统图标
                ForEach(0..<actualSlotConfig.subsystemSlots, id: \.self) { index in
                    if let icon = equipmentIcons[subsystemSlots[index].id] {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: equipmentIconSize, height: equipmentIconSize)
                            .position(
                                calculateSlotPosition(
                                    center: center,
                                    radius: innerSlotCenterRadius,
                                    startAngle: -48,
                                    slotIndex: index,
                                    maxSlots: 4,
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

    func path(in _: CGRect) -> Path {
        var path = Path()

        let adjustment = -90.0  // 调整角度以匹配12点钟方向为0度
        let radian = (angle + adjustment) * .pi / 180

        let outerPoint = CGPoint(
            x: center.x + radius * Foundation.cos(radian),
            y: center.y + radius * Foundation.sin(radian)
        )

        let dividerLength: CGFloat = 30 * scale  // 分隔线长度
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
    let maxSlots: Int  // 最大槽位数（用于计算分隔线间距）
    let actualSlots: Int  // 实际显示的槽位数
    let strokeWidth: CGFloat

    func path(in _: CGRect) -> Path {
        var path = Path()

        let adjustment = -90.0

        // 计算实际槽位对应的结束角度
        let totalAngle = endAngle - startAngle
        let slotWidth = totalAngle / Double(maxSlots)
        let actualEndAngle = startAngle + slotWidth * Double(actualSlots)

        // 绘制主弧形
        let startRadian = (startAngle + adjustment) * .pi / 180
        let endRadian = (actualEndAngle + adjustment) * .pi / 180

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
        for i in 0...actualSlots {
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
