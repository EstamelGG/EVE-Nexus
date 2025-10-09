import SwiftUI

// MARK: - 颜色逻辑扩展

extension RegionMapView {
    // 获取星域的边框颜色
    func getRegionBorderColor(regionId: Int, factionId: Int) -> Color {
        switch regionId {
        case 10_000_070:
            return Color(red: 175 / 255.0, green: 46 / 255.0, blue: 30 / 255.0)
        case 10_001_000:
            return Color(red: 255 / 255.0, green: 255 / 255.0, blue: 255 / 255.0)
        default:
            switch factionId {
            case 500_001: // C
                return Color(red: 165 / 255.0, green: 208 / 255.0, blue: 225 / 255.0)
            case 500_002: // M
                return Color(red: 148 / 255.0, green: 76 / 255.0, blue: 50 / 255.0)
            case 500_003: // A
                return Color(red: 251 / 255.0, green: 239 / 255.0, blue: 156 / 255.0)
            case 500_004: // G
                return Color(red: 122 / 255.0, green: 174 / 255.0, blue: 159 / 255.0)
            case 500_008: // Khanid
                return Color(red: 251 / 255.0, green: 239 / 255.0, blue: 156 / 255.0)
            case 500_007: // Ammatar
                return Color(red: 148 / 255.0, green: 76 / 255.0, blue: 50 / 255.0)
            default:
                return Color(red: 134 / 255.0, green: 57 / 255.0, blue: 103 / 255.0)
            }
        }
    }

    // 获取节点背景色（基于边框颜色调暗）
    func getRegionNodeColor(regionId: Int, factionId: Int) -> Color {
        let borderColor = getRegionBorderColor(regionId: regionId, factionId: factionId)

        // 使用Core Graphics提取RGB值
        let uiColor = UIColor(borderColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // 调暗处理：乘以0.3-0.5的系数
        let darkenFactor: CGFloat = 0.4
        return Color(
            red: red * darkenFactor,
            green: green * darkenFactor,
            blue: blue * darkenFactor
        )
    }
}

struct RegionMapView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var regionData: [RegionData] = []
    @State private var regionNames: [Int: String] = [:]
    @State private var factionNames: [Int: String] = [:]
    @State private var isLoading = true
    @State private var transform = ViewTransform()
    @State private var selectedRegionId: Int?
    @State private var showRegionDetail = false
    @State private var isExporting = false
    @State private var showExportSuccess = false
    @State private var showExportError = false

    struct ViewTransform {
        var scale: CGFloat = 1.0
        var offset: CGSize = .zero
        var lastScale: CGFloat = 1.0
        var lastOffset: CGSize = .zero
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    } else if !regionData.isEmpty {
                        // 星域图Canvas - 使用原生iOS18+ Canvas
                        Canvas { context, size in
                            drawStarMapNative(context: context, size: size)
                        } symbols: {
                            ForEach(regionData, id: \.region_id) { region in
                                RegionNodeView(
                                    regionName: regionNames[region.region_id]
                                        ?? NSLocalizedString(
                                            "StarMap_Unknown_Region", comment: "Unknown"
                                        ),
                                    regionId: region.region_id,
                                    factionId: region.faction_id,
                                    parentView: self
                                )
                                .tag(region.region_id)
                            }
                        }
                        .gesture(createGestures(viewSize: geometry.size))
                        .onTapGesture { location in
                            handleNodeTap(at: location, viewSize: geometry.size)
                        }
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
            if !isLoading && !regionData.isEmpty {
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
        .navigationTitle(NSLocalizedString("StarMap_Title", comment: "Star Map"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isLoading && !regionData.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
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
        .navigationDestination(isPresented: $showRegionDetail) {
            if let selectedRegionId = selectedRegionId,
               let regionName = regionNames[selectedRegionId]
            {
                RegionSystemMapView(
                    databaseManager: databaseManager, regionId: selectedRegionId,
                    regionName: regionName
                )
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
            DragGesture(minimumDistance: 15) // 设置最小拖拽距离，避免与点击冲突
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

    // MARK: - 点击处理

    private func handleNodeTap(at location: CGPoint, viewSize: CGSize) {
        // 计算点击位置在地图坐标系中的位置
        let bounds = calculateBounds()
        let centerX =
            viewSize.width / 2 / (transform.scale * 1.0) - (bounds.minX + bounds.width / 2)
        let centerY =
            viewSize.height / 2 / (transform.scale * 1.0) - (bounds.minY + bounds.height / 2)

        let mapLocation = CGPoint(
            x: (location.x - transform.offset.width) / (transform.scale * 1.0) - centerX,
            y: (location.y - transform.offset.height) / (transform.scale * 1.0) - centerY
        )

        // 查找点击的节点（基于节点实际大小）
        let nodeWidth: CGFloat = 46 // 节点实际宽度
        let nodeHeight: CGFloat = 20 // 节点实际高度
        var closestRegion: RegionData?
        var minDistance = CGFloat.greatestFiniteMagnitude

        for region in regionData {
            let regionPoint = CGPoint(x: region.center.x, y: region.center.y)

            // 计算点击位置与节点中心的距离
            let distanceX = abs(mapLocation.x - regionPoint.x)
            let distanceY = abs(mapLocation.y - regionPoint.y)

            // 检查点击是否在节点矩形范围内
            let halfWidth = nodeWidth / 2
            let halfHeight = nodeHeight / 2

            if distanceX <= halfWidth, distanceY <= halfHeight {
                // 在节点范围内，计算到中心的距离用于优先级
                let distance = sqrt(
                    pow(mapLocation.x - regionPoint.x, 2) + pow(mapLocation.y - regionPoint.y, 2))

                if distance < minDistance {
                    minDistance = distance
                    closestRegion = region
                }
            }
        }

        // 如果找到节点，触发导航
        if let region = closestRegion {
            selectedRegionId = region.region_id
            showRegionDetail = true
        }
    }

    // MARK: - 拖动范围限制 (基于内容边界)

    private func constrainOffset(_ offset: CGSize, scale _: CGFloat, viewSize: CGSize) -> CGSize {
        guard !regionData.isEmpty else { return offset }

        // 节点尺寸 (考虑节点实际大小)
        let nodeWidth: CGFloat = 46
        let nodeHeight: CGFloat = 20

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
            // 加载基础数据
            let regions = self.loadRegionData()
            guard !regions.isEmpty else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }

            // 查询名称
            let regionNames = self.queryRegionNames(regionIds: regions.map { $0.region_id })
            let factionNames = self.queryFactionNames(
                factionIds: Array(
                    Set(regions.compactMap { $0.faction_id != 0 ? $0.faction_id : nil })))

            DispatchQueue.main.async {
                self.regionData = regions
                self.regionNames = regionNames
                self.factionNames = factionNames
                self.isLoading = false
            }
        }
    }

    private func loadRegionData() -> [RegionData] {
        guard let url = StaticResourceManager.shared.getMapDataURL(filename: "regions_data"),
              let data = try? Data(contentsOf: url),
              let regions = try? JSONDecoder().decode([RegionData].self, from: data)
        else {
            Logger.error("无法加载 regions_data.json")
            return []
        }

        Logger.info("成功加载 \(regions.count) 个星域数据")
        return regions
    }

    private func queryRegionNames(regionIds: [Int]) -> [Int: String] {
        let sql =
            "SELECT regionID, regionName FROM regions WHERE regionID IN (\(regionIds.map(String.init).joined(separator: ",")))"

        guard case let .success(rows) = databaseManager.executeQuery(sql) else {
            Logger.error("查询星域名称失败")
            return [:]
        }

        var names: [Int: String] = [:]
        for row in rows {
            if let id = row["regionID"] as? Int,
               let name = row["regionName"] as? String
            {
                names[id] = name
            }
        }

        Logger.info("查询到 \(names.count) 个星域名称")
        return names
    }

    private func queryFactionNames(factionIds: [Int]) -> [Int: String] {
        guard !factionIds.isEmpty else { return [:] }

        let sql =
            "SELECT id, name FROM factions WHERE id IN (\(factionIds.map(String.init).joined(separator: ",")))"

        guard case let .success(rows) = databaseManager.executeQuery(sql) else {
            Logger.error("查询势力名称失败")
            return [:]
        }

        var names: [Int: String] = [:]
        for row in rows {
            if let id = row["id"] as? Int,
               let name = row["name"] as? String
            {
                names[id] = name
            }
        }

        Logger.info("查询到 \(names.count) 个势力名称")
        return names
    }

    // MARK: - Canvas 绘制 (原生iOS18+实现)

    private func drawStarMapNative(context: GraphicsContext, size: CGSize) {
        // 绘制Canvas背景
        let backgroundRect = CGRect(origin: .zero, size: size)
        context.fill(Path(backgroundRect), with: .color(.black))

        // 使用图层来应用变换
        context.drawLayer { layerContext in
            // 应用用户变换
            layerContext.translateBy(x: transform.offset.width, y: transform.offset.height)
            layerContext.scaleBy(x: transform.scale * 1.0, y: transform.scale * 1.0) // 1倍基础缩放

            // 计算居中偏移
            let bounds = calculateBounds()
            let centerX =
                size.width / 2 / (transform.scale * 1.0) - (bounds.minX + bounds.width / 2)
            let centerY =
                size.height / 2 / (transform.scale * 1.0) - (bounds.minY + bounds.height / 2)
            layerContext.translateBy(x: centerX, y: centerY)

            // 绘制连接线
            drawConnectionsNative(context: layerContext)

            // 绘制星域节点
            drawRegionNodesNative(context: layerContext)
        }
    }

    // MARK: - Canvas 绘制 (导出完整地图)

    private func drawStarMapForExport(context: GraphicsContext, size: CGSize) {
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
            let exportScale = min(scaleX, scaleY, 3.0) // 限制最大缩放为3倍

            // 计算居中偏移
            let centerX = size.width / 2 - (bounds.minX + bounds.width / 2) * exportScale
            let centerY = size.height / 2 - (bounds.minY + bounds.height / 2) * exportScale
            layerContext.translateBy(x: centerX, y: centerY)
            layerContext.scaleBy(x: exportScale, y: exportScale)

            // 绘制连接线
            drawConnectionsNative(context: layerContext)

            // 绘制星域节点
            drawRegionNodesNative(context: layerContext)
        }
    }

    private func calculateBounds() -> (
        minX: Double, maxX: Double, minY: Double, maxY: Double, width: Double, height: Double
    ) {
        let xs = regionData.map { $0.center.x }
        let ys = regionData.map { $0.center.y }

        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1000
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1000

        return (minX, maxX, minY, maxY, maxX - minX, maxY - minY)
    }

    // 原生Canvas连接线绘制 - 带渐变效果
    private func drawConnectionsNative(context: GraphicsContext) {
        for region in regionData {
            let fromPoint = CGPoint(x: region.center.x, y: region.center.y)
            let fromColor = getRegionBorderColor(
                regionId: region.region_id, factionId: region.faction_id
            )

            for relationId in region.relations {
                if let targetRegion = regionData.first(where: { String($0.region_id) == relationId }
                ) {
                    let toPoint = CGPoint(x: targetRegion.center.x, y: targetRegion.center.y)
                    let toColor = getRegionBorderColor(
                        regionId: targetRegion.region_id, factionId: targetRegion.faction_id
                    )

                    // 创建单条连线的渐变
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

                    context.stroke(
                        linePath, with: gradientShading, lineWidth: 1.2 / transform.scale
                    )
                }
            }
        }
    }

    // 原生Canvas节点绘制 - 节点大小不受缩放影响
    private func drawRegionNodesNative(context: GraphicsContext) {
        for region in regionData {
            let position = CGPoint(x: region.center.x, y: region.center.y)

            // 绘制星域节点symbol，使用反向缩放保持原始大小
            if let nodeSymbol = context.resolveSymbol(id: region.region_id) {
                context.drawLayer { nodeContext in
                    // 反向缩放，抵消外层的缩放效果
                    nodeContext.scaleBy(x: 1.0 / transform.scale, y: 1.0 / transform.scale)
                    nodeContext.draw(
                        nodeSymbol,
                        at: CGPoint(
                            x: position.x * transform.scale,
                            y: position.y * transform.scale
                        ), anchor: .center
                    )
                }
            }
        }
    }

    // MARK: - 星域节点视图

    private struct RegionNodeView: View {
        let regionName: String
        let regionId: Int
        let factionId: Int
        let parentView: RegionMapView

        private var borderColor: Color {
            parentView.getRegionBorderColor(regionId: regionId, factionId: factionId)
        }

        private var nodeColor: Color {
            parentView.getRegionNodeColor(regionId: regionId, factionId: factionId)
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
            Text(regionName)
                .font(.system(size: 8 * nodeScale, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 46 * nodeScale, height: 20 * nodeScale) // 根据缩放调整尺寸
                .background(
                    RoundedRectangle(cornerRadius: 4 * nodeScale)
                        .fill(nodeColor)
                        .stroke(borderColor, lineWidth: 1 * nodeScale)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4 * nodeScale)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5 * nodeScale)
                )
                .shadow(color: .black.opacity(0.2), radius: 1 * nodeScale, x: 0, y: 1 * nodeScale)
        }
    }

    private func resetView() {
        withAnimation(.easeOut(duration: 0.4)) {
            transform.scale = 1.0
            transform.lastScale = 1.0
            transform.offset = .zero
            transform.lastOffset = .zero
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

            // 星域图Canvas - 导出完整地图
            Canvas { context, size in
                drawStarMapForExport(context: context, size: size)
            } symbols: {
                ForEach(regionData, id: \.region_id) { region in
                    RegionNodeView(
                        regionName: regionNames[region.region_id]
                            ?? NSLocalizedString("StarMap_Unknown_Region", comment: "Unknown"),
                        regionId: region.region_id,
                        factionId: region.faction_id,
                        parentView: self
                    )
                    .tag(region.region_id)
                }
            }
        }
        .frame(width: 1200, height: 900) // 更大的导出尺寸以容纳完整地图
    }
}
