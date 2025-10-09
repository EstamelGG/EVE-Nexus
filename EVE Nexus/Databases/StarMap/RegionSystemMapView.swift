import Foundation
import SwiftUI
import UIKit

// MARK: - 星域地图视图

struct RegionSystemMapView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let regionId: Int
    let regionName: String

    @State private var mapData: SystemMapData?
    @State private var systemNodes: [SystemNodeData] = []
    @State private var isLoading = true
    @State private var transform = ViewTransform()
    @State private var searchText = ""
    @State private var filteredNodes: [SystemNodeData] = []
    @State private var selectedSystemId: Int?
    @State private var isExporting = false
    @State private var showExportSuccess = false
    @State private var showExportError = false
    @State private var selectedFilter: PlanetFilter = .all
    @State private var filteredSystemIds: Set<Int> = []

    struct ViewTransform {
        var scale: CGFloat = 1.0
        var offset: CGSize = .zero
        var lastScale: CGFloat = 1.0
        var lastOffset: CGSize = .zero
    }

    // MARK: - 筛选枚举

    enum PlanetFilter: String, CaseIterable {
        case all
        case gas
        case temperate
        case barren
        case oceanic
        case ice
        case lava
        case storm
        case plasma
        case jove

        var displayName: String {
            switch self {
            case .all:
                return NSLocalizedString("StarMap_Filter_All", comment: "All")
            case .gas:
                return NSLocalizedString("StarMap_Filter_Gas", comment: "Planet (Gas)")
            case .temperate:
                return NSLocalizedString("StarMap_Filter_Temperate", comment: "Planet (Temperate)")
            case .barren:
                return NSLocalizedString("StarMap_Filter_Barren", comment: "Planet (Barren)")
            case .oceanic:
                return NSLocalizedString("StarMap_Filter_Oceanic", comment: "Planet (Oceanic)")
            case .ice:
                return NSLocalizedString("StarMap_Filter_Ice", comment: "Planet (Ice)")
            case .lava:
                return NSLocalizedString("StarMap_Filter_Lava", comment: "Planet (Lava)")
            case .storm:
                return NSLocalizedString("StarMap_Filter_Storm", comment: "Planet (Storm)")
            case .plasma:
                return NSLocalizedString("StarMap_Filter_Plasma", comment: "Planet (Plasma)")
            case .jove:
                return NSLocalizedString("StarMap_Filter_Jove", comment: "Jove Observatory")
            }
        }

        var color: Color {
            switch self {
            case .all:
                return .clear // 使用安全等级颜色
            case .gas:
                return Color(red: 182 / 255, green: 180 / 255, blue: 164 / 255)
            case .temperate:
                return Color(red: 86 / 255, green: 113 / 255, blue: 112 / 255)
            case .barren:
                return Color(red: 183 / 255, green: 171 / 255, blue: 152 / 255)
            case .oceanic:
                return Color(red: 59 / 255, green: 98 / 255, blue: 103 / 255)
            case .ice:
                return Color(red: 107 / 255, green: 113 / 255, blue: 122 / 255)
            case .lava:
                return Color(red: 190 / 255, green: 118 / 255, blue: 70 / 255)
            case .storm:
                return Color(red: 87 / 255, green: 106 / 255, blue: 120 / 255)
            case .plasma:
                return Color(red: 102 / 255, green: 194 / 255, blue: 194 / 255)
            case .jove:
                return Color(red: 229 / 255, green: 228 / 255, blue: 173 / 255)
            }
        }

        var databaseField: String {
            switch self {
            case .all:
                return ""
            case .gas:
                return "gas"
            case .temperate:
                return "temperate"
            case .barren:
                return "barren"
            case .oceanic:
                return "oceanic"
            case .ice:
                return "ice"
            case .lava:
                return "lava"
            case .storm:
                return "storm"
            case .plasma:
                return "plasma"
            case .jove:
                return "jove"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索栏
            if !isLoading && !systemNodes.isEmpty {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(
                            NSLocalizedString("StarMap_Search_System", comment: "搜索星系"),
                            text: $searchText
                        )
                        .textFieldStyle(PlainTextFieldStyle())
                        .onChange(of: searchText) { _, _ in
                            filterSystems()
                        }

                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                selectedSystemId = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                    if !searchText.isEmpty && !filteredNodes.isEmpty {
                        Button(NSLocalizedString("StarMap_Clear_Search", comment: "清除")) {
                            searchText = ""
                            selectedSystemId = nil
                        }
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(.separator)),
                    alignment: .bottom
                )
            }

            GeometryReader { geometry in
                ZStack {
                    if isLoading {
                        VStack {
                            ProgressView(
                                NSLocalizedString("StarMap_Loading", comment: "Loading star map")
                            )
                            .padding()
                            Text(
                                NSLocalizedString(
                                    "StarMap_Processing", comment: "Processing star map data"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !systemNodes.isEmpty {
                        // 星系图Canvas
                        Canvas { context, size in
                            drawSystemMapNative(context: context, size: size)
                        } symbols: {
                            ForEach(systemNodes, id: \.systemId) { system in
                                SystemNodeView(
                                    systemName: system.name,
                                    security: system.security,
                                    systemId: system.systemId,
                                    parentView: self
                                )
                                .tag(system.systemId)
                            }
                        }
                        .gesture(createGestures(viewSize: geometry.size))
                    } else {
                        // 错误状态
                        VStack {
                            Text(
                                NSLocalizedString(
                                    "StarMap_Load_Failed", comment: "Failed to load star map data"
                                )
                            )
                            .foregroundColor(.red)
                            Button(NSLocalizedString("StarMap_Retry", comment: "Retry")) {
                                loadData()
                            }
                            .padding()
                        }
                    }
                }
            }

            // 底部控制栏
            if !isLoading && !systemNodes.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        // 缩放指示器
                        Text("\(Int(transform.scale * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40)

                        // 缩放滑块
                        Slider(
                            value: Binding(
                                get: { transform.scale },
                                set: { newValue in
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        transform.scale = newValue
                                        transform.lastScale = newValue
                                    }
                                }
                            ),
                            in: 0.2 ... 5.0,
                            step: 0.1
                        )
                        .accentColor(.blue)

                        // 重置按钮
                        Button(action: resetView) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .help(NSLocalizedString("StarMap_Reset_View", comment: "Reset View"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .overlay(
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundColor(Color(.separator)),
                        alignment: .top
                    )
                }
            }
        }
        .navigationTitle(regionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isLoading && !systemNodes.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        // 筛选按钮
                        Menu {
                            ForEach(PlanetFilter.allCases, id: \.self) { filter in
                                Button(action: {
                                    selectedFilter = filter
                                    applyFilter()
                                }) {
                                    HStack {
                                        Text(filter.displayName)
                                        if selectedFilter == filter {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                            }
                            .foregroundColor(selectedFilter == .all ? .blue : .orange)
                        }

                        // 导出按钮
                        Button(action: exportMap) {
                            ZStack {
                                Image(systemName: "photo.badge.plus")
                                    .opacity(isExporting ? 0 : 1)

                                if isExporting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                            .frame(width: 24, height: 24) // 固定尺寸防止跳动
                        }
                        .disabled(isExporting)
                    }
                }
            }
        }
        .alert(
            NSLocalizedString("StarMap_Export_Success", comment: "Export Success"),
            isPresented: $showExportSuccess
        ) {
            Button("OK") {}
        } message: {
            Text(
                NSLocalizedString(
                    "StarMap_Export_Success_Message", comment: "Map exported to photo library"
                ))
        }
        .alert(
            NSLocalizedString("StarMap_Export_Error", comment: "Export Failed"),
            isPresented: $showExportError
        ) {
            Button("OK") {}
        } message: {
            Text(NSLocalizedString("StarMap_Export_Error_Message", comment: "Failed to export map"))
        }
        .onAppear {
            selectedFilter = .all
            filteredSystemIds.removeAll()
            loadData()
        }
    }

    // MARK: - 手势处理

    private func createGestures(viewSize: CGSize) -> some Gesture {
        SimultaneousGesture(
            // 缩放手势
            MagnificationGesture()
                .onChanged { value in
                    transform.scale = transform.lastScale * value
                }
                .onEnded { _ in
                    transform.lastScale = max(0.2, min(5.0, transform.scale))
                    transform.scale = transform.lastScale
                },

            // 拖拽手势
            DragGesture()
                .onChanged { value in
                    let newOffset = CGSize(
                        width: transform.lastOffset.width + value.translation.width,
                        height: transform.lastOffset.height + value.translation.height
                    )
                    transform.offset = constrainOffset(
                        newOffset, scale: transform.scale, viewSize: viewSize
                    )
                }
                .onEnded { _ in
                    transform.lastOffset = transform.offset
                }
        )
    }

    // MARK: - 拖动范围限制 (基于内容边界)

    private func constrainOffset(_ offset: CGSize, scale _: CGFloat, viewSize: CGSize) -> CGSize {
        guard !systemNodes.isEmpty else { return offset }

        // 节点尺寸 (考虑节点实际大小)
        let nodeWidth: CGFloat = 50
        let nodeHeight: CGFloat = 24

        // 计算地图内容的实际边界
        let bounds = calculateBounds()
        let contentWidth = bounds.width
        let contentHeight = bounds.height

        // 计算缩放后的内容尺寸
        let scaledContentWidth = contentWidth * transform.scale * 1.0
        let scaledContentHeight = contentHeight * transform.scale * 1.0

        // 计算缩放后的节点尺寸
        let scaledNodeWidth = nodeWidth * transform.scale * 1.0
        let scaledNodeHeight = nodeHeight * transform.scale * 1.0

        // 计算最大可偏移量（确保节点完全可见）
        let maxOffsetX = max(
            0, (scaledContentWidth - viewSize.width) / 2 + scaledNodeWidth / 2 + 20
        )
        let maxOffsetY = max(
            0, (scaledContentHeight - viewSize.height) / 2 + scaledNodeHeight / 2 + 20
        )

        // 应用边界限制
        let constrainedX = max(-maxOffsetX, min(maxOffsetX, offset.width))
        let constrainedY = max(-maxOffsetY, min(maxOffsetY, offset.height))

        return CGSize(width: constrainedX, height: constrainedY)
    }

    // MARK: - 数据加载

    private func loadData() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            // 加载地图数据
            guard let mapData = self.loadMapData() else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            // 查询星系信息
            let systemIds = Array(mapData.systems.keys).compactMap { Int($0) }
            let systemInfo = self.querySystemInfo(systemIds: systemIds)

            // 构建节点数据
            let nodes = self.buildSystemNodes(mapData: mapData, systemInfo: systemInfo)

            DispatchQueue.main.async {
                self.mapData = mapData
                self.systemNodes = nodes
                self.filteredNodes = []
                self.isLoading = false

                // 应用当前筛选
                if self.selectedFilter != .all {
                    self.applyFilter()
                }
            }
        }
    }

    private func loadMapData() -> SystemMapData? {
        guard let url = StaticResourceManager.shared.getMapDataURL(filename: "systems_data"),
              let data = try? Data(contentsOf: url),
              let allSystemsData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let regionData = allSystemsData[String(regionId)] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: regionData),
              let mapData = try? JSONDecoder().decode(SystemMapData.self, from: jsonData)
        else {
            Logger.error("无法加载星域 \(regionId) 的地图数据")
            return nil
        }

        Logger.info("成功加载星域 \(regionId) 的地图数据")
        return mapData
    }

    private func querySystemInfo(systemIds: [Int]) -> [Int: (
        name: String, nameEn: String, nameZh: String, security: Double, regionId: Int,
        planetCounts: PlanetCounts
    )] {
        guard !systemIds.isEmpty else { return [:] }

        let placeholders = String(repeating: "?,", count: systemIds.count).dropLast()
        let sql = """
            SELECT solarSystemID, solarSystemName, solarSystemName_en, solarSystemName_zh, system_security, region_id,
                   gas, temperate, barren, oceanic, ice, lava, storm, plasma, jove
            FROM solarsystems s
            JOIN universe u ON u.solarsystem_id = s.solarSystemID
            WHERE s.solarSystemID IN (\(placeholders))
        """

        guard
            case let .success(rows) = databaseManager.executeQuery(
                sql, parameters: systemIds.map { $0 as Any }
            )
        else {
            Logger.error("查询星系信息失败")
            return [:]
        }

        var systemInfo:
            [Int: (
                name: String, nameEn: String, nameZh: String, security: Double, regionId: Int,
                planetCounts: PlanetCounts
            )] = [:]
        for row in rows {
            if let id = row["solarSystemID"] as? Int,
               let name = row["solarSystemName"] as? String,
               let nameEn = row["solarSystemName_en"] as? String,
               let nameZh = row["solarSystemName_zh"] as? String,
               let security = row["system_security"] as? Double,
               let regionId = row["region_id"] as? Int
            {
                let planetCounts = PlanetCounts(
                    gas: row["gas"] as? Int ?? 0,
                    temperate: row["temperate"] as? Int ?? 0,
                    barren: row["barren"] as? Int ?? 0,
                    oceanic: row["oceanic"] as? Int ?? 0,
                    ice: row["ice"] as? Int ?? 0,
                    lava: row["lava"] as? Int ?? 0,
                    storm: row["storm"] as? Int ?? 0,
                    plasma: row["plasma"] as? Int ?? 0,
                    jove: row["jove"] as? Int ?? 0
                )

                systemInfo[id] = (
                    name: name, nameEn: nameEn, nameZh: nameZh, security: security,
                    regionId: regionId, planetCounts: planetCounts
                )
            }
        }

        Logger.info("查询到 \(systemInfo.count) 个星系信息")
        return systemInfo
    }

    private func buildSystemNodes(
        mapData: SystemMapData,
        systemInfo: [Int: (
            name: String, nameEn: String, nameZh: String, security: Double, regionId: Int,
            planetCounts: PlanetCounts
        )]
    ) -> [SystemNodeData] {
        var nodes: [SystemNodeData] = []

        for (systemIdStr, position) in mapData.systems {
            guard let systemId = Int(systemIdStr),
                  let info = systemInfo[systemId]
            else { continue }

            let connections = mapData.jumps[systemIdStr]?.compactMap { Int($0) } ?? []

            let node = SystemNodeData(
                systemId: systemId,
                name: info.name,
                nameEn: info.nameEn,
                nameZh: info.nameZh,
                security: info.security,
                regionId: info.regionId,
                position: CGPoint(x: position.x, y: position.y),
                connections: connections,
                planetCounts: info.planetCounts
            )
            nodes.append(node)
        }

        return nodes
    }

    // MARK: - Canvas 绘制

    private func drawSystemMapNative(context: GraphicsContext, size: CGSize) {
        // 绘制Canvas背景
        let backgroundRect = CGRect(origin: .zero, size: size)
        context.fill(Path(backgroundRect), with: .color(.black))

        // 使用图层来应用变换
        context.drawLayer { layerContext in
            // 应用用户变换
            layerContext.translateBy(x: transform.offset.width, y: transform.offset.height)
            layerContext.scaleBy(x: transform.scale * 1.0, y: transform.scale * 1.0)

            // 计算居中偏移
            let bounds = calculateBounds()
            let centerX =
                size.width / 2 / (transform.scale * 1.0) - (bounds.minX + bounds.width / 2)
            let centerY =
                size.height / 2 / (transform.scale * 1.0) - (bounds.minY + bounds.height / 2)
            layerContext.translateBy(x: centerX, y: centerY)

            // 绘制连接线
            drawConnectionsNative(context: layerContext)

            // 绘制星系节点
            drawSystemNodesNative(context: layerContext)
        }
    }

    // MARK: - Canvas 绘制 (导出完整地图)

    private func drawSystemMapForExport(context: GraphicsContext, size: CGSize) {
        // 绘制Canvas背景
        let backgroundRect = CGRect(origin: .zero, size: size)
        context.fill(Path(backgroundRect), with: .color(.black))

        // 使用图层来绘制完整地图
        context.drawLayer { layerContext in
            // 计算地图边界
            let bounds = calculateBounds()

            // 计算缩放比例，确保完整地图适合导出尺寸
            let mapWidth = bounds.width
            let mapHeight = bounds.height
            let scaleX = (size.width - 100) / mapWidth // 留出边距
            let scaleY = (size.height - 100) / mapHeight
            let exportScale = min(scaleX, scaleY, 4.0) // 限制最大缩放为4倍

            // 计算居中偏移
            let centerX = size.width / 2 - (bounds.minX + bounds.width / 2) * exportScale
            let centerY = size.height / 2 - (bounds.minY + bounds.height / 2) * exportScale
            layerContext.translateBy(x: centerX, y: centerY)
            layerContext.scaleBy(x: exportScale, y: exportScale)

            // 绘制连接线
            drawConnectionsNative(context: layerContext)

            // 绘制星系节点
            drawSystemNodesNative(context: layerContext)
        }
    }

    private func calculateBounds() -> (
        minX: Double, maxX: Double, minY: Double, maxY: Double, width: Double, height: Double
    ) {
        let xs = systemNodes.map { $0.position.x }
        let ys = systemNodes.map { $0.position.y }

        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1000
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1000

        return (minX, maxX, minY, maxY, maxX - minX, maxY - minY)
    }

    // 原生Canvas连接线绘制
    private func drawConnectionsNative(context: GraphicsContext) {
        for system in systemNodes {
            let fromPoint = system.position
            let fromColor = getSystemColor(system)

            for connectionId in system.connections {
                if let targetSystem = systemNodes.first(where: { $0.systemId == connectionId }) {
                    let toPoint = targetSystem.position
                    let toColor = getSystemColor(targetSystem)

                    // 判断是否为跨星域连线
                    let isCrossRegion = system.regionId != targetSystem.regionId

                    // 创建连线路径
                    var linePath = Path()
                    linePath.move(to: fromPoint)
                    linePath.addLine(to: toPoint)

                    // 创建线性渐变
                    let gradient = Gradient(colors: [fromColor.opacity(0.6), toColor.opacity(0.6)])
                    let gradientShading = GraphicsContext.Shading.linearGradient(
                        gradient,
                        startPoint: fromPoint,
                        endPoint: toPoint
                    )

                    // 根据是否跨星域选择线型
                    if isCrossRegion {
                        // 跨星域连线使用虚线
                        context.stroke(
                            linePath, with: gradientShading,
                            style: StrokeStyle(
                                lineWidth: 1.2 / transform.scale,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: [4.0 / transform.scale, 2.0 / transform.scale]
                            )
                        )
                    } else {
                        // 同星域连线使用实线
                        context.stroke(
                            linePath, with: gradientShading, lineWidth: 1.2 / transform.scale
                        )
                    }
                }
            }
        }
    }

    // 原生Canvas节点绘制 - 节点大小不受缩放影响
    private func drawSystemNodesNative(context: GraphicsContext) {
        for system in systemNodes {
            // 绘制星系节点symbol，使用反向缩放保持原始大小
            if let nodeSymbol = context.resolveSymbol(id: system.systemId) {
                context.drawLayer { nodeContext in
                    // 反向缩放，抵消外层的缩放效果
                    nodeContext.scaleBy(x: 1.0 / transform.scale, y: 1.0 / transform.scale)
                    nodeContext.draw(
                        nodeSymbol,
                        at: CGPoint(
                            x: system.position.x * transform.scale,
                            y: system.position.y * transform.scale
                        ), anchor: .center
                    )
                }
            }
        }
    }

    // MARK: - 星系节点视图

    private struct SystemNodeView: View {
        let systemName: String
        let security: Double
        let systemId: Int
        let parentView: RegionSystemMapView

        private var isSelected: Bool {
            parentView.selectedSystemId == systemId
        }

        private var isFiltered: Bool {
            !parentView.searchText.isEmpty
                && parentView.filteredNodes.contains { $0.systemId == systemId }
        }

        private var securityColor: Color {
            parentView.getSystemColor(
                SystemNodeData(
                    systemId: systemId,
                    name: systemName,
                    nameEn: systemName,
                    nameZh: systemName,
                    security: security,
                    regionId: 0,
                    position: .zero,
                    connections: [],
                    planetCounts: PlanetCounts()
                ))
        }

        private var borderColor: Color? {
            parentView.getSystemBorderColor(
                SystemNodeData(
                    systemId: systemId,
                    name: systemName,
                    nameEn: systemName,
                    nameZh: systemName,
                    security: security,
                    regionId: 0,
                    position: .zero,
                    connections: [],
                    planetCounts: PlanetCounts()
                ))
        }

        private var nodeColor: Color {
            // 使用Core Graphics提取RGB值并调暗
            let uiColor = UIColor(securityColor)
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0

            uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            let darkenFactor: CGFloat = 0.4
            return Color(
                red: red * darkenFactor,
                green: green * darkenFactor,
                blue: blue * darkenFactor
            )
        }

        private var nodeScale: CGFloat {
            let scale = parentView.transform.scale
            if scale <= 1.0 {
                return 1.0 // 100%以下不变化
            } else {
                return 1.0 + (scale - 1.0) * 0.1 // 1/10变化率
            }
        }

        var body: some View {
            VStack(spacing: 2 * nodeScale) {
                Text(systemName)
                    .font(.system(size: 8 * nodeScale, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                // 显示安全等级或行星数量
                if parentView.selectedFilter != .all {
                    let planetCount = parentView.getSystemPlanetCount(systemId: systemId)
                    if planetCount > 0 {
                        Text("\(planetCount)")
                            .font(.system(size: 6 * nodeScale, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    } else {
                        Text(formatSystemSecurity(security))
                            .font(.system(size: 6 * nodeScale, weight: .medium))
                            .foregroundColor(securityColor)
                            .lineLimit(1)
                    }
                } else {
                    Text(formatSystemSecurity(security))
                        .font(.system(size: 6 * nodeScale, weight: .medium))
                        .foregroundColor(securityColor)
                        .lineLimit(1)
                }
            }
            .frame(width: 50 * nodeScale, height: 24 * nodeScale)
            .background(
                RoundedRectangle(cornerRadius: 4 * nodeScale)
                    .fill(nodeColor)
            )
            .overlay(
                ZStack {
                    // 默认边框（最内层）
                    RoundedRectangle(cornerRadius: 4 * nodeScale)
                        .stroke(securityColor, lineWidth: 1 * nodeScale)

                    // 筛选边框（中间层）
                    if let borderColor = borderColor {
                        RoundedRectangle(cornerRadius: 4 * nodeScale)
                            .stroke(borderColor, lineWidth: 4 * nodeScale)
                    }

                    // 搜索高亮边框
                    if isFiltered {
                        RoundedRectangle(cornerRadius: 4 * nodeScale)
                            .stroke(.orange, lineWidth: 2 * nodeScale)
                    }

                    // 选中边框（最外层，覆盖筛选框）
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4 * nodeScale)
                            .stroke(.yellow, lineWidth: 3 * nodeScale)
                    }
                }
            )
            .scaleEffect(isSelected ? 1.2 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }

    // MARK: - 搜索功能

    private func filterSystems() {
        if searchText.isEmpty {
            filteredNodes = []
            selectedSystemId = nil
        } else {
            filteredNodes = systemNodes.filter { system in
                system.name.localizedCaseInsensitiveContains(searchText)
                    || system.nameEn.localizedCaseInsensitiveContains(searchText)
                    || system.nameZh.localizedCaseInsensitiveContains(searchText)
                    || formatSystemSecurity(system.security).contains(searchText)
            }

            // 如果只有一个结果，自动选中
            if filteredNodes.count == 1 {
                selectedSystemId = filteredNodes[0].systemId
                centerOnSystem(filteredNodes[0])
            } else {
                selectedSystemId = nil
            }
        }
    }

    private func centerOnSystem(_ system: SystemNodeData) {
        let bounds = calculateBounds()
        let centerX =
            UIScreen.main.bounds.width / 2 / (transform.scale * 2.0)
                - (bounds.minX + bounds.width / 2)
        let centerY =
            UIScreen.main.bounds.height / 2 / (transform.scale * 2.0)
                - (bounds.minY + bounds.height / 2)

        let targetX = centerX + system.position.x
        let targetY = centerY + system.position.y

        withAnimation(.easeOut(duration: 0.5)) {
            transform.offset = CGSize(width: -targetX, height: -targetY)
            transform.lastOffset = transform.offset
        }
    }

    // MARK: - 筛选相关函数

    private func applyFilter() {
        if selectedFilter == .all {
            filteredSystemIds.removeAll()
        } else {
            loadFilteredSystems()
        }
    }

    private func loadFilteredSystems() {
        guard selectedFilter != .all else {
            filteredSystemIds.removeAll()
            return
        }

        let systemIds = systemNodes.map { $0.systemId }
        guard !systemIds.isEmpty else { return }

        let placeholders = String(repeating: "?,", count: systemIds.count).dropLast()
        let field = selectedFilter.databaseField
        let sql = """
            SELECT solarsystem_id
            FROM universe
            WHERE solarsystem_id IN (\(placeholders))
            AND \(field) > 0
        """

        guard
            case let .success(rows) = databaseManager.executeQuery(
                sql, parameters: systemIds.map { $0 as Any }
            )
        else {
            Logger.error("筛选星系失败")
            return
        }

        let filteredIds = rows.compactMap { row in
            row["solarsystem_id"] as? Int
        }

        DispatchQueue.main.async {
            self.filteredSystemIds = Set(filteredIds)
        }
    }

    private func getSystemColor(_ system: SystemNodeData) -> Color {
        // 始终使用安全等级颜色作为基础颜色
        return getSecurityColor(system.security)
    }

    private func getSystemBorderColor(_ system: SystemNodeData) -> Color? {
        // 只有在筛选模式下才显示边框颜色
        if selectedFilter != .all, filteredSystemIds.contains(system.systemId) {
            return selectedFilter.color
        }
        return nil
    }

    private func getSystemPlanetCount(systemId: Int) -> Int {
        guard let system = systemNodes.first(where: { $0.systemId == systemId }) else {
            return 0
        }
        return system.planetCounts.getCount(for: selectedFilter)
    }

    // MARK: - 控制函数

    private func resetView() {
        withAnimation(.easeOut(duration: 0.4)) {
            transform.scale = 1.0
            transform.lastScale = 1.0
            transform.offset = .zero
            transform.lastOffset = .zero
            searchText = ""
            selectedSystemId = nil
            filteredNodes = []
            selectedFilter = .all
            filteredSystemIds.removeAll()
        }
    }

    // MARK: - 导出功能

    private func exportMap() {
        isExporting = true

        // 创建画布图片
        let renderer = ImageRenderer(content: createExportView())
        renderer.scale = 2.0 // 高分辨率导出

        if let image = renderer.uiImage {
            ImageSaver.saveImage(image) { success in
                self.isExporting = false
                if success {
                    self.showExportSuccess = true
                } else {
                    self.showExportError = true
                }
            }
        } else {
            isExporting = false
            showExportError = true
        }
    }

    private func createExportView() -> some View {
        ZStack {
            // 黑色背景
            Color.black

            // 星系图Canvas - 导出完整地图
            Canvas { context, size in
                drawSystemMapForExport(context: context, size: size)
            } symbols: {
                ForEach(systemNodes, id: \.systemId) { system in
                    SystemNodeView(
                        systemName: system.name,
                        security: system.security,
                        systemId: system.systemId,
                        parentView: self
                    )
                    .tag(system.systemId)
                }
            }
        }
        .frame(width: 1200, height: 900) // 更大的导出尺寸以容纳完整地图
    }
}
