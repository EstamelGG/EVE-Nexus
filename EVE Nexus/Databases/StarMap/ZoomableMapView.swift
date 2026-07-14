import SwiftUI
import UIKit

/// 相对「适合全图」的缩放桥接：捏合与 SwiftUI 滑条双向同步
final class StarMapZoomController: ObservableObject {
    @Published private(set) var relativeZoom: Double = 1
    @Published private(set) var percent: Int = 100
    @Published private(set) var minRelative: Double = 0.55
    @Published private(set) var maxRelative: Double = 5

    private var isUpdatingFromMap = false
    weak var scrollView: ZoomableMapScrollView?

    func syncFromMap(_ map: ZoomableMapScrollView) {
        let fit = max(map.fitZoomScale, 0.0001)
        let newMin = Double(map.minimumZoomScale / fit)
        let newMax = Double(map.maximumZoomScale / fit)
        let newRel = Double(map.zoomScale / fit)
        let newPercent = map.displayScalePercent

        // 避免在 SwiftUI updateUIView / body 刷新路径里直接写 @Published
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard abs(self.relativeZoom - newRel) > 0.000_5
                || self.percent != newPercent
                || abs(self.minRelative - newMin) > 0.000_5
                || abs(self.maxRelative - newMax) > 0.000_5
            else { return }
            self.isUpdatingFromMap = true
            self.minRelative = newMin
            self.maxRelative = newMax
            self.relativeZoom = newRel
            self.percent = newPercent
            self.isUpdatingFromMap = false
        }
    }

    func setRelativeZoom(_ value: Double) {
        guard !isUpdatingFromMap else { return }
        let clamped = min(max(value, minRelative), maxRelative)
        relativeZoom = clamped
        guard let map = scrollView else {
            percent = Int((clamped * 100).rounded())
            return
        }
        let fit = max(map.fitZoomScale, 0.0001)
        map.setZoomScaleCentered(fit * CGFloat(clamped), animated: false)
        percent = map.displayScalePercent
    }
}

/// 基于 UIScrollView 的跟手缩放地图容器（捏合；缩放条由 SwiftUI 浮层承担）
struct ZoomableMapView: UIViewRepresentable {
    var graph: MapGraph
    var resetToken: Int = 0
    var focusNodeId: Int?
    var zoomController: StarMapZoomController
    var onNodeTap: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNodeTap: onNodeTap, zoomController: zoomController)
    }

    func makeUIView(context: Context) -> ZoomableMapContainerView {
        let container = ZoomableMapContainerView()
        container.scrollView.coordinator = context.coordinator
        context.coordinator.scrollView = container.scrollView
        context.coordinator.container = container
        context.coordinator.zoomController = zoomController
        zoomController.scrollView = container.scrollView
        context.coordinator.lastResetToken = resetToken
        context.coordinator.lastFocusNodeId = focusNodeId
        container.scrollView.apply(graph: graph, reset: true, focusNodeId: focusNodeId)
        // apply / layout 内会 publishZoom，此处不再同步写 @Published
        return container
    }

    func updateUIView(_ container: ZoomableMapContainerView, context: Context) {
        context.coordinator.onNodeTap = onNodeTap
        context.coordinator.zoomController = zoomController
        context.coordinator.scrollView = container.scrollView
        context.coordinator.container = container
        container.scrollView.coordinator = context.coordinator
        zoomController.scrollView = container.scrollView

        let needsReset = context.coordinator.lastResetToken != resetToken
        if needsReset {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.lastFocusNodeId = nil
        }

        let focusId: Int?
        if needsReset {
            focusId = nil
        } else {
            let focusChanged = context.coordinator.lastFocusNodeId != focusNodeId
            context.coordinator.lastFocusNodeId = focusNodeId
            focusId = focusChanged ? focusNodeId : nil
        }

        container.scrollView.apply(
            graph: graph,
            reset: needsReset,
            focusNodeId: focusId
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onNodeTap: (Int) -> Void
        var zoomController: StarMapZoomController
        weak var scrollView: ZoomableMapScrollView?
        weak var container: ZoomableMapContainerView?
        var lastResetToken = 0
        var lastFocusNodeId: Int?

        init(onNodeTap: @escaping (Int) -> Void, zoomController: StarMapZoomController) {
            self.onNodeTap = onNodeTap
            self.zoomController = zoomController
        }

        func publishZoom() {
            guard let mapScroll = scrollView else { return }
            zoomController.syncFromMap(mapScroll)
        }

        func viewForZooming(in _: UIScrollView) -> UIView? {
            scrollView?.contentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let mapScroll = scrollView as? ZoomableMapScrollView else { return }
            mapScroll.centerContentIfNeeded()
            mapScroll.updateMarkerScreenScale()
            publishZoom()
        }

        func scrollViewDidEndZooming(
            _ scrollView: UIScrollView, with _: UIView?, atScale _: CGFloat
        ) {
            guard let mapScroll = scrollView as? ZoomableMapScrollView else { return }
            mapScroll.updateMarkerScreenScale()
            publishZoom()
        }
    }
}

// MARK: - Container（全屏星空 + 滚动）

final class ZoomableMapContainerView: UIView {
    let backgroundView = StarfieldBackgroundView()
    let scrollView = ZoomableMapScrollView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
        addSubview(backgroundView)
        addSubview(scrollView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        scrollView.frame = bounds
    }
}

final class StarfieldBackgroundView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
        backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.06, alpha: 1)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        MapGraphRenderer.drawBackground(context, in: bounds, seed: bounds.size)
    }
}

// MARK: - Scroll + Content

final class ZoomableMapScrollView: UIScrollView {
    let contentView = MapContentView()
    weak var coordinator: ZoomableMapView.Coordinator?
    private var lastRevisionMark: Int = -1
    private var hasPerformedInitialFit = false
    private(set) var fitZoomScale: CGFloat = 1

    var displayScalePercent: Int {
        let fit = max(fitZoomScale, 0.0001)
        return Int(((zoomScale / fit) * 100).rounded())
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        decelerationRate = .fast
        bouncesZoom = true
        alwaysBounceVertical = true
        alwaysBounceHorizontal = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never

        contentView.backgroundColor = .clear
        addSubview(contentView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        addGestureRecognizer(tap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !hasPerformedInitialFit, bounds.width > 0, !contentView.graph.nodes.isEmpty {
            prepareUnzoomedCanvas(size: contentView.graph.contentSize)
            fitContent(animated: false)
            hasPerformedInitialFit = true
            coordinator?.publishZoom()
        } else if hasPerformedInitialFit {
            centerContentIfNeeded()
        }
    }

    func apply(graph: MapGraph, reset: Bool, focusNodeId: Int?) {
        delegate = coordinator

        let sizeChanged = graph.contentSize != contentView.graph.contentSize
        let contentChanged =
            graph.revision != lastRevisionMark
                || sizeChanged
                || graph.nodes.count != contentView.graph.nodes.count

        if contentChanged {
            contentView.graph = graph
            lastRevisionMark = graph.revision
            contentView.rebuildMarkers()
            contentView.setNeedsDisplay()
            updateMarkerScreenScale()
        }

        // 首次：zoom=1 设画布后无动画 fit。重置：保留当前倍率，动画回到 fit+居中
        if reset || !hasPerformedInitialFit {
            if bounds.width > 0, !graph.nodes.isEmpty {
                if !hasPerformedInitialFit {
                    prepareUnzoomedCanvas(size: graph.contentSize)
                    fitContent(animated: false)
                } else {
                    fitContent(animated: true)
                }
                hasPerformedInitialFit = true
            }
            return
        }

        if sizeChanged {
            let relative = zoomScale / max(fitZoomScale, 0.0001)
            prepareUnzoomedCanvas(size: graph.contentSize)
            fitContent(animated: false)
            setZoomScaleCentered(fitZoomScale * relative, animated: false)
            return
        }

        if let focusNodeId,
           let node = contentView.graph.nodes.first(where: { $0.id == focusNodeId })
        {
            focus(on: node, animated: true)
        }
    }

    /// 与首次进入一致：在 zoomScale==1 时设置画布尺寸
    private func prepareUnzoomedCanvas(size: CGSize) {
        zoomScale = 1
        contentInset = .zero
        contentOffset = .zero
        contentView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
    }

    func fitContent(animated: Bool) {
        // 用未缩放画布尺寸算 fit，勿用可能被错误覆写过的 contentSize
        let canvas = contentView.bounds.size
        guard canvas.width > 0, canvas.height > 0, bounds.width > 0 else { return }

        let scaleX = bounds.width / canvas.width
        let scaleY = bounds.height / canvas.height
        let fit = min(scaleX, scaleY)
        fitZoomScale = fit

        minimumZoomScale = max(fit * 0.55, 0.08)
        maximumZoomScale = max(fit * 5.0, 3.0)

        layer.removeAllAnimations()
        contentView.layer.removeAllAnimations()

        let applyZoom = {
            self.zoomScale = fit
            self.snapToCenteredOffset()
            self.updateMarkerScreenScale()
            self.coordinator?.publishZoom()
        }

        if animated {
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                applyZoom()
            }
        } else {
            applyZoom()
        }
    }

    /// 按当前 contentSize / inset 把视口对到地图几何中心（与首进一致）
    private func snapToCenteredOffset() {
        centerContentIfNeeded()
        let x = max((contentSize.width - bounds.width) * 0.5, 0) - contentInset.left
        let y = max((contentSize.height - bounds.height) * 0.5, 0) - contentInset.top
        setContentOffset(CGPoint(x: x, y: y), animated: false)
    }

    func focus(on node: MapNode, animated: Bool) {
        let targetZoom = min(max(zoomScale, minimumZoomScale * 2.2), maximumZoomScale)
        let size = CGSize(
            width: bounds.width / targetZoom,
            height: bounds.height / targetZoom
        )
        let rect = CGRect(
            x: node.position.x - size.width / 2,
            y: node.position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        zoom(to: rect, animated: animated)
        updateMarkerScreenScale()
        coordinator?.publishZoom()
    }

    func setZoomScaleCentered(_ scale: CGFloat, animated: Bool) {
        let clamped = min(max(scale, minimumZoomScale), maximumZoomScale)
        let centerInView = CGPoint(x: bounds.midX, y: bounds.midY)
        let centerInContent = convert(centerInView, to: contentView)
        let size = CGSize(width: bounds.width / clamped, height: bounds.height / clamped)
        let rect = CGRect(
            x: centerInContent.x - size.width / 2,
            y: centerInContent.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        zoom(to: rect, animated: animated)
        updateMarkerScreenScale()
        centerContentIfNeeded()
    }

    func centerContentIfNeeded() {
        let sw = bounds.width
        let sh = bounds.height
        let cw = contentSize.width
        let ch = contentSize.height
        let insetX = max((sw - cw) * 0.5, 0)
        let insetY = max((sh - ch) * 0.5, 0)
        contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
    }

    func updateMarkerScreenScale() {
        let scale = max(zoomScale, 0.001)
        let boost: CGFloat
        if scale <= fitZoomScale {
            boost = 1
        } else {
            boost = 1 + (scale / fitZoomScale - 1) * 0.1
        }
        contentView.applyMarkerScale((1 / scale) * boost)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: contentView)
        if let id = MapGraphRenderer.hitTest(
            graph: contentView.graph, point: point, contentScale: zoomScale
        ) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            coordinator?.onNodeTap(id)
        }
    }
}

final class MapContentView: UIView {
    var graph: MapGraph = .empty
    private var markers: [MapNodeMarkerView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isOpaque = false
        contentMode = .redraw
        backgroundColor = .clear
        layer.drawsAsynchronously = true
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        MapGraphRenderer.draw(
            graph, in: context, bounds: bounds, background: false, edges: true, nodes: false
        )
    }

    func rebuildMarkers() {
        markers.forEach { $0.removeFromSuperview() }
        markers = graph.nodes.map { node in
            let marker = MapNodeMarkerView(node: node)
            addSubview(marker)
            return marker
        }
    }

    func applyMarkerScale(_ scale: CGFloat) {
        let t = CGAffineTransform(scaleX: scale, y: scale)
        for marker in markers {
            marker.transform = t
        }
    }
}

final class MapNodeMarkerView: UIView {
    private var node: MapNode

    init(node: MapNode) {
        self.node = node
        let size = MapGraphRenderer.markerSize(for: node)
        super.init(frame: CGRect(origin: .zero, size: size))
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false

        bounds = CGRect(origin: .zero, size: size)
        applyAnchor(for: node.style, size: size)
        layer.position = node.position
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyAnchor(for style: MapNode.Style, size: CGSize) {
        switch style {
        case .region:
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        case .system:
            let anchorY = MapGraphRenderer.systemDotCenterY / max(size.height, 1)
            layer.anchorPoint = CGPoint(x: 0.5, y: anchorY)
        }
    }

    override func draw(_: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        MapGraphRenderer.drawNodeInMarker(node, in: context, bounds: bounds)
    }
}
