import SwiftUI

/// 脉动进度条组件 - 带有从左到右的闪烁效果
struct PulsingProgressBar: View {
    /// 当前进度 (0.0 - 1.0)
    let progress: Double
    /// 进度条颜色
    let color: Color
    /// 进度条高度
    let height: CGFloat
    /// 圆角半径
    let cornerRadius: CGFloat
    /// 是否显示脉动效果（当进度在0-1之间时）
    let showPulse: Bool

    @State private var shimmerPhase: Double = 0 // 0到1的动画相位

    init(
        progress: Double,
        color: Color = .blue,
        height: CGFloat = 4,
        cornerRadius: CGFloat = 2,
        showPulse: Bool = true
    ) {
        self.progress = max(0, min(1, progress)) // 确保在0-1范围内
        self.color = color
        self.height = height
        self.cornerRadius = cornerRadius
        self.showPulse = showPulse
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: height)

                // 进度条主体
                let progressWidth = geometry.size.width * progress

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(color)
                    .frame(width: progressWidth, height: height)
                    .overlay(alignment: .leading) {
                        // 闪烁遮罩效果
                        if showPulse && progress > 0 && progress < 1.0 {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0),
                                            Color.white.opacity(0.6),
                                            Color.white.opacity(0),
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: progressWidth * 0.4, height: height)
                                .offset(x: calculateShimmerOffset(progressWidth: progressWidth, phase: shimmerPhase))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .frame(height: height)
        .onAppear {
            startShimmerAnimation()
        }
    }

    /// 计算光斑偏移量（基于动画相位）
    private func calculateShimmerOffset(progressWidth: CGFloat, phase: Double) -> CGFloat {
        let shimmerWidth = progressWidth * 0.4
        let startOffset = -shimmerWidth
        let endOffset = progressWidth
        return startOffset + (endOffset - startOffset) * CGFloat(phase)
    }

    /// 开始闪烁动画循环
    private func startShimmerAnimation() {
        // 重置到起始位置（相位为0）
        shimmerPhase = 0

        // 1. 从0移动到1（3秒）
        withAnimation(.linear(duration: 3.0)) {
            shimmerPhase = 1.0
        }

        // 2. 在终点停留0.8秒后，重新开始循环
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
            startShimmerAnimation()
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // 不同进度示例
        VStack(alignment: .leading, spacing: 8) {
            Text("25% - 蓝色")
            PulsingProgressBar(progress: 0.25, color: .blue)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("50% - 绿色")
            PulsingProgressBar(progress: 0.5, color: .green)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("75% - 橙色")
            PulsingProgressBar(progress: 0.75, color: .orange)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("已完成 - 灰色（无脉动）")
            PulsingProgressBar(progress: 1.0, color: .gray)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("自定义高度和圆角")
            PulsingProgressBar(
                progress: 0.6,
                color: .purple,
                height: 8,
                cornerRadius: 4
            )
        }
    }
    .padding()
}
