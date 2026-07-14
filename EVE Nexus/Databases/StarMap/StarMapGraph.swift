import CoreGraphics
import SwiftUI
import UIKit

// MARK: - Graph

struct MapGraph {
    var nodes: [MapNode]
    var edges: [MapEdge]
    var contentSize: CGSize
    /// 数据版本，变更时触发内容重绘（不重置缩放）
    var revision: Int = 0

    static let empty = MapGraph(nodes: [], edges: [], contentSize: CGSize(width: 400, height: 400))
}

struct MapNode {
    let id: Int
    var position: CGPoint
    var title: String
    var subtitle: String?
    var accent: UIColor
    var fill: UIColor
    var dimmed: Bool = false
    var highlighted: Bool = false
    var selected: Bool = false
    var accentRing: UIColor?
    /// 是否在节点后方绘制入侵渐变光圈
    var incursionGlow: Bool = false
    /// 相邻星域跳接节点
    var isExternal: Bool = false
    var style: Style

    enum Style {
        case region
        case system
    }
}

struct MapEdge {
    let from: CGPoint
    let to: CGPoint
    let fromColor: UIColor
    let toColor: UIColor
    let dashed: Bool
}

// MARK: - Layout

enum StarMapLayout {
    /// 将世界坐标投影到内容坐标系，并以包围盒几何中心落在画布中心
    static func project(
        points: [Int: CGPoint],
        padding: CGFloat = 120,
        targetSpan: CGFloat = 1400
    ) -> (positions: [Int: CGPoint], contentSize: CGSize) {
        guard !points.isEmpty else {
            return ([:], CGSize(width: 400, height: 400))
        }

        let xs = points.values.map(\.x)
        let ys = points.values.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        let worldW = max(maxX - minX, 1)
        let worldH = max(maxY - minY, 1)
        let scale = targetSpan / max(worldW, worldH)

        let projectedW = worldW * scale
        let projectedH = worldH * scale
        // 正方形画布，包围盒几何中心对齐画布中心
        let canvasSide = max(projectedW, projectedH) + padding * 2
        let worldCenterX = (minX + maxX) / 2
        let worldCenterY = (minY + maxY) / 2
        let canvasCenter = canvasSide / 2

        var positions: [Int: CGPoint] = [:]
        for (id, point) in points {
            // SDE position2D：+Y 为北；UIKit：+Y 向下 → 取反使北朝上
            positions[id] = CGPoint(
                x: canvasCenter + (point.x - worldCenterX) * scale,
                y: canvasCenter - (point.y - worldCenterY) * scale
            )
        }

        return (positions, CGSize(width: canvasSide, height: canvasSide))
    }
}

// MARK: - Builders

enum StarMapGraphBuilder {
    static func buildRegionGraph(
        regions: [RegionData],
        names: [Int: String],
        searchMatchedIds: Set<Int> = [],
        incursionRegionIds: Set<Int> = []
    ) -> MapGraph {
        let world: [Int: CGPoint] = Dictionary(
            uniqueKeysWithValues: regions.map {
                ($0.region_id, CGPoint(x: $0.center.x, y: $0.center.y))
            }
        )
        let (positions, contentSize) = StarMapLayout.project(points: world, targetSpan: 1600)

        let regionById = Dictionary(uniqueKeysWithValues: regions.map { ($0.region_id, $0) })
        var edgeKeys = Set<String>()
        var edges: [MapEdge] = []
        let searching = !searchMatchedIds.isEmpty

        for region in regions {
            guard let from = positions[region.region_id] else { continue }
            let fromColor = StarMapColors.regionAccent(
                regionId: region.region_id, factionId: region.faction_id
            )

            for relation in region.relations {
                guard let toId = Int(relation),
                      let toRegion = regionById[toId],
                      let to = positions[toId]
                else { continue }

                let key = relationKey(region.region_id, toId)
                guard edgeKeys.insert(key).inserted else { continue }

                let toColor = StarMapColors.regionAccent(
                    regionId: toRegion.region_id, factionId: toRegion.faction_id
                )
                edges.append(
                    MapEdge(
                        from: from, to: to, fromColor: fromColor, toColor: toColor, dashed: false
                    )
                )
            }
        }

        let nodes: [MapNode] = regions.compactMap { region in
            guard let position = positions[region.region_id] else { return nil }
            let accent = StarMapColors.regionAccent(
                regionId: region.region_id, factionId: region.faction_id
            )
            let matched = searchMatchedIds.contains(region.region_id)
            return MapNode(
                id: region.region_id,
                position: position,
                title: names[region.region_id]
                    ?? NSLocalizedString("StarMap_Unknown_Region", comment: "Unknown"),
                subtitle: nil,
                accent: accent,
                fill: StarMapColors.darkened(accent),
                dimmed: searching && !matched,
                highlighted: matched,
                incursionGlow: incursionRegionIds.contains(region.region_id),
                style: .region
            )
        }

        return MapGraph(nodes: nodes, edges: edges, contentSize: contentSize)
    }

    static func buildSystemGraph(
        systems: [SystemNodeData],
        selectedId: Int?,
        searchMatchedIds: Set<Int>,
        filterMatchedIds: Set<Int>?,
        filter: RegionSystemMapView.PlanetFilter,
        incursionSystemIds: Set<Int> = []
    ) -> MapGraph {
        let world = Dictionary(uniqueKeysWithValues: systems.map { ($0.systemId, $0.position) })
        let (positions, contentSize) = StarMapLayout.project(points: world, targetSpan: 1200)
        let byId = Dictionary(uniqueKeysWithValues: systems.map { ($0.systemId, $0) })

        var edgeKeys = Set<String>()
        var edges: [MapEdge] = []

        for system in systems {
            guard let from = positions[system.systemId] else { continue }
            let fromColor = StarMapColors.security(system.security)

            for connectionId in system.connections {
                guard let target = byId[connectionId],
                      let to = positions[connectionId]
                else { continue }

                let key = relationKey(system.systemId, connectionId)
                guard edgeKeys.insert(key).inserted else { continue }

                let isCrossRegion = system.regionId != target.regionId
                    || system.isExternal || target.isExternal
                edges.append(
                    MapEdge(
                        from: from,
                        to: to,
                        fromColor: fromColor,
                        toColor: StarMapColors.security(target.security),
                        dashed: isCrossRegion
                    )
                )
            }
        }

        let filtering = filter != .all
        let nodes: [MapNode] = systems.compactMap { system in
            guard let position = positions[system.systemId] else { return nil }
            let accent: UIColor
            let subtitle: String?
            let accentRing: UIColor?
            let dimmed: Bool

            if system.isExternal {
                accent = StarMapColors.security(system.security)
                let regionTitle = SDEMemoryStore.regionName(for: system.regionId)
                subtitle = regionTitle ?? formatSystemSecurity(system.security)
                accentRing = UIColor.white.withAlphaComponent(0.55)
                dimmed = false
            } else if filtering {
                let matched = filterMatchedIds?.contains(system.systemId) == true
                let count = system.planetCounts.getCount(for: filter)
                accent = matched
                    ? StarMapColors.planetFilter(filter) : StarMapColors.security(system.security)
                subtitle = matched && count > 0 ? "\(count)" : formatSystemSecurity(system.security)
                accentRing = matched ? StarMapColors.planetFilter(filter) : nil
                dimmed = !matched
            } else {
                accent = StarMapColors.security(system.security)
                subtitle = formatSystemSecurity(system.security)
                accentRing = nil
                dimmed = false
            }

            return MapNode(
                id: system.systemId,
                position: position,
                title: system.name,
                subtitle: subtitle,
                accent: accent,
                fill: StarMapColors.darkened(accent, factor: system.isExternal ? 0.22 : 0.35),
                dimmed: dimmed,
                highlighted: !system.isExternal && searchMatchedIds.contains(system.systemId),
                selected: !system.isExternal && selectedId == system.systemId,
                accentRing: accentRing,
                incursionGlow: incursionSystemIds.contains(system.systemId),
                isExternal: system.isExternal,
                style: .system
            )
        }

        return MapGraph(nodes: nodes, edges: edges, contentSize: contentSize)
    }

    private static func relationKey(_ a: Int, _ b: Int) -> String {
        a < b ? "\(a)-\(b)" : "\(b)-\(a)"
    }
}

// MARK: - Drawing

enum MapGraphRenderer {
    static func draw(
        _ graph: MapGraph,
        in context: CGContext,
        bounds: CGRect,
        background: Bool = true,
        edges: Bool = true,
        nodes: Bool = true
    ) {
        if background {
            drawBackground(context, in: bounds, seed: graph.contentSize)
        } else {
            context.clear(bounds)
        }

        if edges {
            for edge in graph.edges {
                drawEdge(edge, in: context)
            }
        }

        if nodes {
            for node in graph.nodes {
                drawNode(node, in: context)
            }
        }
    }

    static func drawBackground(_ context: CGContext, in bounds: CGRect, seed: CGSize) {
        let colors = [
            UIColor(red: 0.02, green: 0.04, blue: 0.09, alpha: 1).cgColor,
            UIColor(red: 0.04, green: 0.07, blue: 0.14, alpha: 1).cgColor,
            UIColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 1).cgColor,
        ]
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 0.45, 1]
        ) {
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: bounds.midX, y: bounds.midY * 0.85),
                startRadius: 0,
                endCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                endRadius: max(bounds.width, bounds.height) * 0.75,
                options: [.drawsAfterEndLocation]
            )
        } else {
            context.setFillColor(UIColor.black.cgColor)
            context.fill(bounds)
        }

        var rng = SeededGenerator(seed: UInt64(seed.width) &<< 16 ^ UInt64(seed.height))
        let starCount = Int(min(bounds.width * bounds.height / 1800, 220))
        for _ in 0 ..< starCount {
            let x = CGFloat.random(in: 0 ... bounds.width, using: &rng)
            let y = CGFloat.random(in: 0 ... bounds.height, using: &rng)
            let radius = CGFloat.random(in: 0.4 ... 1.2, using: &rng)
            let alpha = CGFloat.random(in: 0.15 ... 0.55, using: &rng)
            context.setFillColor(UIColor.white.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
        }
    }

    private static func drawEdge(_ edge: MapEdge, in context: CGContext) {
        let path = CGMutablePath()
        path.move(to: edge.from)
        path.addLine(to: edge.to)

        context.saveGState()
        context.setStrokeColor(edge.fromColor.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(3.5)
        context.setLineCap(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        if edge.dashed {
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.setLineWidth(1.35)
        } else {
            context.setLineWidth(1.15)
        }
        context.setLineCap(.round)

        let colors = [
            edge.fromColor.withAlphaComponent(0.7).cgColor,
            edge.toColor.withAlphaComponent(0.7).cgColor,
        ] as CFArray
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]
        ) {
            context.addPath(path)
            context.replacePathWithStrokedPath()
            context.clip()
            context.drawLinearGradient(gradient, start: edge.from, end: edge.to, options: [])
        } else {
            context.setStrokeColor(edge.fromColor.withAlphaComponent(0.55).cgColor)
            context.addPath(path)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// 星系节点在 marker 内的圆点 Y；需大于 selected 外环半径，避免顶部被裁切
    static let systemDotCenterY: CGFloat = 16

    static func drawNodeInMarker(_ node: MapNode, in context: CGContext, bounds: CGRect) {
        var centered = node
        switch node.style {
        case .region:
            centered.position = CGPoint(x: bounds.midX, y: bounds.midY)
        case .system:
            centered.position = CGPoint(x: bounds.midX, y: systemDotCenterY)
        }
        drawNode(centered, in: context)
    }

    fileprivate static func drawNode(_ node: MapNode, in context: CGContext) {
        context.saveGState()
        if node.dimmed {
            context.setAlpha(0.28)
        }

        switch node.style {
        case .region:
            drawRegionNode(node, in: context)
        case .system:
            drawSystemNode(node, in: context)
        }
        context.restoreGState()
    }

    private static func drawRegionNode(_ node: MapNode, in context: CGContext) {
        let font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
        ]
        let text = node.title as NSString
        let textSize = text.size(withAttributes: attrs)
        let padding = CGSize(width: 8, height: 5)
        let rect = CGRect(
            x: node.position.x - (textSize.width + padding.width * 2) / 2,
            y: node.position.y - (textSize.height + padding.height * 2) / 2,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )

        let path = UIBezierPath(roundedRect: rect, cornerRadius: 5)

        context.setFillColor(node.fill.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()

        if node.incursionGlow {
            // 渐变边框：4 层从粗到细、从淡到浓的描边
            let layers: [(line: CGFloat, alpha: CGFloat)] = [
                (11, 0.02), (9, 0.07), (7, 0.18), (5, 0.35),
            ]
            for layer in layers {
                context.setStrokeColor(StarMapColors.incursion.withAlphaComponent(layer.alpha).cgColor)
                context.setLineWidth(layer.line)
                context.addPath(path.cgPath)
                context.strokePath()
            }
            // 实线边框
            context.setStrokeColor(StarMapColors.incursion.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(3)
        } else {
            context.setStrokeColor(
                (node.highlighted ? UIColor.systemYellow : node.accent).withAlphaComponent(0.95).cgColor
            )
            context.setLineWidth(node.highlighted ? 1.8 : 1)
        }
        context.addPath(path.cgPath)
        context.strokePath()

        context.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
        context.setLineWidth(0.5)
        context.addPath(path.cgPath)
        context.strokePath()

        text.draw(
            at: CGPoint(x: rect.minX + padding.width, y: rect.minY + padding.height),
            withAttributes: attrs
        )
    }

    private static func drawSystemNode(_ node: MapNode, in context: CGContext) {
        let radius: CGFloat = node.selected ? 5.5 : (node.isExternal ? 3.8 : 4.2)
        let dotRect = CGRect(
            x: node.position.x - radius,
            y: node.position.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        if node.selected || node.highlighted {
            let glow = (node.selected ? UIColor.systemYellow : UIColor.systemOrange)
                .withAlphaComponent(0.35)
            context.setFillColor(glow.cgColor)
            context.fillEllipse(in: dotRect.insetBy(dx: -5, dy: -5))
        }

        if node.isExternal {
            context.setFillColor(node.fill.withAlphaComponent(0.55).cgColor)
            context.fillEllipse(in: dotRect)
            context.setStrokeColor(node.accent.withAlphaComponent(0.85).cgColor)
            context.setLineWidth(1.2)
            context.setLineDash(phase: 0, lengths: [2.5, 2])
            context.strokeEllipse(in: dotRect.insetBy(dx: -2.5, dy: -2.5))
            context.setLineDash(phase: 0, lengths: [])
        } else {
            context.setFillColor(node.fill.cgColor)
            context.fillEllipse(in: dotRect)
            if node.incursionGlow {
                // 渐变边框：4 层从粗到细、从淡到浓的描边
                let layers: [(line: CGFloat, alpha: CGFloat)] = [
                    (10, 0.02), (8, 0.07), (6, 0.18), (4, 0.35),
                ]
                for layer in layers {
                    context.setStrokeColor(StarMapColors.incursion.withAlphaComponent(layer.alpha).cgColor)
                    context.setLineWidth(layer.line)
                    context.strokeEllipse(in: dotRect)
                }
                // 实线边框
                context.setStrokeColor(StarMapColors.incursion.cgColor)
                context.setLineWidth(2.5)
            } else {
                context.setStrokeColor(node.accent.cgColor)
                context.setLineWidth(1.2)
            }
            context.strokeEllipse(in: dotRect)
        }

        if let ring = node.accentRing {
            context.setStrokeColor(ring.cgColor)
            context.setLineWidth(node.isExternal ? 1.4 : 2.2)
            if node.isExternal {
                context.setLineDash(phase: 0, lengths: [3, 2.5])
            }
            context.strokeEllipse(in: dotRect.insetBy(dx: -3, dy: -3))
            context.setLineDash(phase: 0, lengths: [])
        }

        if node.highlighted {
            context.setStrokeColor(UIColor.systemOrange.cgColor)
            context.setLineWidth(2)
            context.strokeEllipse(in: dotRect.insetBy(dx: -5, dy: -5))
        }

        if node.selected {
            context.setStrokeColor(UIColor.systemYellow.cgColor)
            context.setLineWidth(2.4)
            context.strokeEllipse(in: dotRect.insetBy(dx: -7, dy: -7))
        }

        let titleFont = UIFont.systemFont(ofSize: node.isExternal ? 9 : 10, weight: .medium)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.white.withAlphaComponent(node.isExternal ? 0.75 : 0.95),
        ]
        let title = node.title as NSString
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(
            at: CGPoint(x: node.position.x - titleSize.width / 2, y: node.position.y + radius + 3),
            withAttributes: titleAttrs
        )

        if let subtitle = node.subtitle {
            let subFont = UIFont.systemFont(ofSize: node.isExternal ? 7 : 8, weight: .semibold)
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: subFont,
                .foregroundColor: node.isExternal
                    ? UIColor.white.withAlphaComponent(0.55) : node.accent,
            ]
            let sub = subtitle as NSString
            let subSize = sub.size(withAttributes: subAttrs)
            sub.draw(
                at: CGPoint(
                    x: node.position.x - subSize.width / 2,
                    y: node.position.y + radius + 3 + titleSize.height + 1
                ),
                withAttributes: subAttrs
            )
        }
    }

    /// - Parameter contentScale: 当前内容缩放；命中半径按屏幕恒定尺寸反算到内容坐标
    static func hitTest(graph: MapGraph, point: CGPoint, contentScale: CGFloat) -> Int? {
        var bestId: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        let scale = max(contentScale, 0.001)

        for node in graph.nodes {
            let screenRadius: CGFloat = node.style == .region ? 30 : 20
            let hitRadius = screenRadius / scale
            let dx = point.x - node.position.x
            let dy = point.y - node.position.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance <= hitRadius, distance < bestDistance {
                bestDistance = distance
                bestId = node.id
            }
        }
        return bestId
    }

    static func markerSize(for node: MapNode) -> CGSize {
        switch node.style {
        case .region:
            let font = UIFont.systemFont(ofSize: 9, weight: .semibold)
            let textSize = (node.title as NSString).size(withAttributes: [.font: font])
            let pad: CGFloat = node.incursionGlow ? 28 : 20
            let padV: CGFloat = node.incursionGlow ? 22 : 14
            return CGSize(width: textSize.width + pad, height: textSize.height + padV)
        case .system:
            let titleFont = UIFont.systemFont(ofSize: 10, weight: .medium)
            let titleSize = (node.title as NSString).size(withAttributes: [.font: titleFont])
            let subWidth: CGFloat
            if let subtitle = node.subtitle {
                let subFont = UIFont.systemFont(ofSize: 8, weight: .semibold)
                subWidth = (subtitle as NSString).size(withAttributes: [.font: subFont]).width
            } else {
                subWidth = 0
            }
            // 选中外环相对半径约 +7，再加线宽，两侧各需约 14
            let width = max(titleSize.width, subWidth, 28) + 10
            let height: CGFloat = node.subtitle == nil ? 46 : 58
            return CGSize(width: width, height: height)
        }
    }
}

// MARK: - Seeded RNG

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}
