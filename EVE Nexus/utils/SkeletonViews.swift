import SwiftUI

/// 通用列表骨架屏行：可选左侧图标占位 + 文本条组 + 可选尾部数值条。
/// 用于列表初始加载场景，替代居中的 ProgressView，让用户预感到内容的形状。
struct ListSkeletonRow: View {
    /// 左侧图标尺寸；nil 表示无图标
    var iconSize: CGFloat? = 48
    var iconCornerRadius: CGFloat = 8
    /// 文本条宽度，按行排列（首行较深色，其余较浅色）
    var lineWidths: [CGFloat] = [140, 200]
    /// 尾部数值条宽度；nil 表示无尾部
    var trailingWidth: CGFloat?

    @State private var isPulsing = false

    private let barFill = Color.secondary.opacity(0.2)
    private let barFillLight = Color.secondary.opacity(0.15)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let iconSize {
                RoundedRectangle(cornerRadius: iconCornerRadius)
                    .fill(barFill)
                    .frame(width: iconSize, height: iconSize)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(lineWidths.enumerated()), id: \.offset) { index, width in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == 0 ? barFill : barFillLight)
                        .frame(width: width, height: index == 0 ? 12 : 10)
                }
            }

            Spacer(minLength: 0)

            if let trailingWidth {
                RoundedRectangle(cornerRadius: 4)
                    .fill(barFillLight)
                    .frame(width: trailingWidth, height: 12)
            }
        }
        .padding(.vertical, 4)
        .opacity(isPulsing ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
        .accessibilityHidden(true)
    }
}

// MARK: - 预设样式

extension ListSkeletonRow {
    /// 战斗日志行（BRKillMailCell 轮廓）：48 图标 + 两行文本 + 尾部数值
    static var killMail: ListSkeletonRow {
        ListSkeletonRow(lineWidths: [140, 200], trailingWidth: 72)
    }

    /// 邮件行（头像 + 主题/发件人/时间三行）
    static var mail: ListSkeletonRow {
        ListSkeletonRow(lineWidths: [160, 120, 90])
    }

    /// 钱包日志行（无图标：左侧日期+笔数，右侧金额）
    static var walletJournal: ListSkeletonRow {
        ListSkeletonRow(iconSize: nil, lineWidths: [100, 70], trailingWidth: 80)
    }
}

// MARK: - 组合骨架

/// 钱包日志页骨架：汇总区（标题 + 三行标签/数值）+ 日期条目区，对应页面的两个 section
struct WalletJournalSkeleton: View {
    @State private var isPulsing = false

    private let barFill = Color.secondary.opacity(0.2)
    private let barFillLight = Color.secondary.opacity(0.15)

    var body: some View {
        // 汇总区：标题条 + 时间范围按钮条
        Section(
            header: HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(barFill)
                    .frame(width: 90, height: 16)
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(barFillLight)
                    .frame(width: 60, height: 12)
            }
        ) {
            // 三行「标签 + ISK 数值」（总收入/总支出/净收益）
            ForEach(0 ..< 3, id: \.self) { _ in
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barFill)
                        .frame(width: 70, height: 12)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barFillLight)
                        .frame(width: 110, height: 10)
                }
            }
        }
        .opacity(isPulsing ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
        .accessibilityHidden(true)

        // 日期条目区
        Section(
            header: RoundedRectangle(cornerRadius: 4)
                .fill(barFill)
                .frame(width: 110, height: 16)
        ) {
            ForEach(0 ..< 6, id: \.self) { _ in
                ListSkeletonRow.walletJournal
            }
        }
    }
}
