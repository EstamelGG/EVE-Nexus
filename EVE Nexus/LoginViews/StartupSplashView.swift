import SwiftUI

/// 加载完成状态（设置页 SDE 重置的 FullScreenCover 完成信号）
enum LoadingState {
    case processing
    case complete
}

/// 启动阶段
enum StartupStage {
    /// 检查静态资源（SDE 健康检查）
    case checking
    /// 首装 / 重置时解压 SDE 与图标包
    case extracting
    /// 主库加载（内存索引逐表构建，n/20）
    case loadingDB
    /// 技能树 / 行星缓存等初始化
    case initializing

    var title: String {
        switch self {
        case .checking:
            return NSLocalizedString("Startup_Checking", comment: "正在检查资源")
        case .extracting:
            return NSLocalizedString("Startup_Extracting", comment: "正在解压数据")
        case .loadingDB:
            return NSLocalizedString("Startup_Loading_DB", comment: "正在加载数据")
        case .initializing:
            return NSLocalizedString("Startup_Initializing", comment: "正在初始化")
        }
    }
}

/// 启动开屏页：深色渐变背景 + 当前选中 App 图标（无角标）+ 进度条
/// 覆盖首装解压、常规启动数据库加载、设置页 SDE 重置三类场景
struct StartupSplashView: View {
    let stage: StartupStage
    /// 0-1；不定进度阶段（如 .checking / .initializing）传 nil，进度条保持最近一次非 nil 进度
    let progress: Double?
    /// 进度条下方明细（如 "8/20"）
    var detailText: String? = nil

    /// 深浅色由根视图挂载的 preferredColorScheme 决定（随主题设置即时切换），无需自行读取 selectedTheme
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool {
        colorScheme == .dark
    }

    /// 最近一次非 nil 进度；不定阶段（progress == nil）显示该值
    @State private var lastProgress: Double = 0

    /// 背景渐变：深色模式沿 EVE 深蓝，浅色模式为淡灰蓝
    private var backgroundGradient: LinearGradient {
        if isDark {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.04, green: 0.055, blue: 0.10), location: 0),
                    .init(color: Color(red: 0.10, green: 0.13, blue: 0.20), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.93, green: 0.94, blue: 0.97), location: 0),
                    .init(color: Color(red: 0.86, green: 0.88, blue: 0.93), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// 当前选中的 App 图标（无角标母图）
    private var appIcon: UIImage? {
        let (iconName, _) = AppIconConfig.getCurrentIconAndBadge()
        return UIImage(named: iconName)
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            // 图标绝对居中，不受底部文本行数影响
            if let icon = appIcon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .cornerRadius(24)
                    .shadow(color: .blue.opacity(0.35), radius: 24, x: 0, y: 8)
            }

            // 底部固定区：进度条锚定底部，文本行数变化只影响其上方文本堆叠，不影响进度条位置
            VStack(spacing: 12) {
                Spacer(minLength: 0)

                // 百分比
                if let progress {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .monospacedDigit()
                }

                // 阶段文案 + 明细
                HStack(spacing: 6) {
                    Text(stage.title)
                    if let detailText {
                        Text(detailText)
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                // 进度条固定在文案下方，距底边 48
                progressBar
                    .frame(height: 6)
                    .padding(.horizontal, 60)
                    .padding(.bottom, 48)
            }
        }
        // 记录最近一次非 nil 进度，供不定阶段（progress == nil）沿用
        .onChange(of: progress) { _, newValue in
            if let newValue {
                lastProgress = newValue
            }
        }
    }

    /// 进度条：胶囊条填充到 progress；不定阶段保持上次进度静止显示
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(progressGradient)
                    .frame(width: max(geometry.size.width * displayProgress, 8))
            }
        }
    }

    /// 不定阶段（progress == nil）保持最近一次非 nil 进度（初始为 0）
    private var displayProgress: Double {
        progress ?? lastProgress
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .cyan],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
