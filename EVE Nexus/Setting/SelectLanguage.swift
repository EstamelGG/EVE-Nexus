import SwiftUI

// MARK: - 圆环进度指示器

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 2.5)
                .opacity(0.2)
                .foregroundColor(.accentColor)
            Circle()
                .trim(from: 0.0, to: min(max(progress, 0), 1.0))
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .foregroundColor(.accentColor)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - 数据库语言数据模型

private struct DBLanguage: Identifiable {
    let code: String
    let name: String
    let englishName: String?
    let isBuiltin: Bool
    var id: String { code }
}

private let allDBLanguages: [DBLanguage] = [
    DBLanguage(code: "en", name: "English", englishName: nil, isBuiltin: true),
    DBLanguage(code: "zh-Hans", name: "中文", englishName: nil, isBuiltin: true),
    DBLanguage(code: "de", name: "Deutsch (Beta)", englishName: "German", isBuiltin: false),
    DBLanguage(code: "es", name: "Español (Beta)", englishName: "Spanish", isBuiltin: false),
    DBLanguage(code: "fr", name: "Français (Beta)", englishName: "French", isBuiltin: false),
    DBLanguage(code: "ja", name: "日本語 (Beta)", englishName: "Japanese", isBuiltin: false),
    DBLanguage(code: "ko", name: "한국어 (Beta)", englishName: "Korean", isBuiltin: false),
    DBLanguage(code: "ru", name: "Русский (Beta)", englishName: "Russian", isBuiltin: false),
]

// MARK: - 语言行右侧操作状态

private enum LanguageActionState {
    case selected
    case updatable
    case downloadable
    case downloading(Double)
    case processing
    case none
}

// MARK: - APP 语言选项

struct LanguageOptionView: View {
    let language: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(language)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - SelectLanguageView

struct SelectLanguageView: View {
    let appLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("zh-Hans", "中文"),
        ("ru", "Русский (Beta)"),
    ]

    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    @AppStorage("selectedDatabaseLanguage") private var selectedDatabaseLanguage: String = "en"
    @ObservedObject var databaseManager: DatabaseManager
    @StateObject private var extraDBManager = ExtraLanguageDBManager.shared
    @StateObject private var updateChecker = SDEUpdateChecker.shared
    @State private var showingSDEUpdateSheet = false
    @State private var isDeleteMode = false

    var body: some View {
        List {
            // APP 语言设置
            Section {
                ForEach(appLanguages, id: \.code) { lang in
                    LanguageOptionView(
                        language: lang.name,
                        isSelected: selectedLanguage == lang.code,
                        onTap: {
                            if selectedLanguage != lang.code {
                                applyLanguageChange(code: lang.code)
                            }
                        }
                    )
                }
            } header: {
                Text(NSLocalizedString("Main_Setting_Language", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            // 数据库语言设置
            Section {
                ForEach(allDBLanguages) { lang in
                    databaseLanguageRow(lang)
                }
            } header: {
                HStack {
                    Text(NSLocalizedString("Main_Setting_Database_Language", comment: "数据库语言"))
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Button {
                        withAnimation { isDeleteMode.toggle() }
                    } label: {
                        Text(isDeleteMode
                            ? NSLocalizedString("Common_Done", comment: "完成")
                            : NSLocalizedString("ExtraDB_Manage_Delete", comment: "管理"))
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
            }

            // 检查 SDE 更新
            Section {
                Button {
                    Task { await checkSDEUpdate() }
                } label: {
                    HStack {
                        Spacer()
                        if updateChecker.isChecking {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text(NSLocalizedString("SDE_Checking_Update", comment: "正在检查更新..."))
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(NSLocalizedString("SDE_Check_Update", comment: "检查 SDE 更新"))
                        }
                        Spacer()
                    }
                }
                .disabled(updateChecker.isChecking || updateChecker.isButtonDisabled)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Select_Language", comment: ""))
        .sheet(isPresented: $showingSDEUpdateSheet) {
            SDEUpdateDetailView()
        }
    }

    // MARK: - 数据库语言行

    @ViewBuilder
    private func databaseLanguageRow(_ lang: DBLanguage) -> some View {
        let isSelected = selectedDatabaseLanguage == lang.code
        let isInstalled = lang.isBuiltin || extraDBManager.isExtraDBAvailable(languageCode: lang.code)
        let status = extraDBManager.languageStatus[lang.code]
        let actionState = resolveActionState(isSelected: isSelected, isInstalled: isInstalled, status: status)
        let isInProgress = status?.isInProgress == true
        let canDelete = isDeleteMode && !lang.isBuiltin && isInstalled && !isInProgress

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.name)
                    .foregroundColor(.primary)
                if let englishName = lang.englishName {
                    Text(englishName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            if isDeleteMode {
                if lang.isBuiltin {
                    tagLabel(NSLocalizedString("ExtraDB_Builtin", comment: "内置"), color: Color(red: 0.4, green: 0.7, blue: 1.0))
                } else if canDelete {
                    Button(role: .destructive) {
                        deleteExtraDB(lang: lang)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                } else if !isInstalled {
                    tagLabel(NSLocalizedString("ExtraDB_NotDownloaded", comment: "未下载"), color: .secondary)
                }
            } else {
                actionIndicator(actionState)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isInProgress && !isDeleteMode else { return }
            handleRowTap(lang: lang, isInstalled: isInstalled)
        }
    }

    private func resolveActionState(
        isSelected: Bool,
        isInstalled: Bool,
        status: ExtraLanguageDBManager.DownloadStatus?
    ) -> LanguageActionState {
        if let status = status {
            if case let .downloading(p) = status { return .downloading(p) }
            if status.isInProgress { return .processing }
        }
        if updateChecker.updateStatus == .hasUpdate && isInstalled { return .updatable }
        if !isInstalled { return .downloadable }
        if isSelected { return .selected }
        return .none
    }

    @ViewBuilder
    private func actionIndicator(_ state: LanguageActionState) -> some View {
        switch state {
        case .selected:
            Image(systemName: "checkmark")
                .foregroundColor(.blue)
        case .updatable:
            actionBadge(
                title: NSLocalizedString("ExtraDB_Update", comment: "Update"),
                color: .orange
            )
        case .downloadable:
            actionBadge(
                title: NSLocalizedString("ExtraDB_Download", comment: "下载"),
                color: .blue
            )
        case let .downloading(progress):
            CircularProgressView(progress: progress)
        case .processing:
            ProgressView()
                .controlSize(.small)
        case .none:
            EmptyView()
        }
    }

    private func actionBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .cornerRadius(12)
    }

    private func tagLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }

    // MARK: - 行点击处理

    private func handleRowTap(lang: DBLanguage, isInstalled: Bool) {
        if updateChecker.updateStatus == .hasUpdate, isInstalled {
            showingSDEUpdateSheet = true
        } else if !isInstalled {
            Task {
                await extraDBManager.downloadAndInstall(languageCode: lang.code)
                if extraDBManager.isExtraDBAvailable(languageCode: lang.code) {
                    applyDatabaseLanguageChange(code: lang.code)
                }
            }
        } else {
            applyDatabaseLanguageChange(code: lang.code)
        }
    }

    // MARK: - 删除额外语言数据库

    private func deleteExtraDB(lang: DBLanguage) {
        let wasSelected = selectedDatabaseLanguage == lang.code
        extraDBManager.removeExtraDB(languageCode: lang.code)

        if wasSelected {
            applyDatabaseLanguageChange(code: "en")
        }
    }

    // MARK: - 检查 SDE 更新

    private func checkSDEUpdate() async {
        await updateChecker.forceCheckForUpdates()
        if updateChecker.updateStatus == .hasUpdate {
            showingSDEUpdateSheet = true
        }
    }

    // MARK: - 语言切换

    private func applyLanguageChange(code: String) {
        selectedLanguage = code
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        if let languageBundlePath = Bundle.main.path(forResource: code, ofType: "lproj"),
           Bundle(path: languageBundlePath) != nil
        {
            Bundle.setLanguage(code)
        }

        DatabaseBrowserView.clearCache()
        databaseManager.clearCache()
        databaseManager.loadDatabase()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: NSNotification.Name("LanguageChanged"), object: nil
            )
        }
    }

    private func applyDatabaseLanguageChange(code: String) {
        selectedDatabaseLanguage = code

        DatabaseBrowserView.clearCache()
        databaseManager.clearCache()
        databaseManager.loadDatabase()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NotificationCenter.default.post(
                name: NSNotification.Name("DatabaseLanguageChanged"), object: nil
            )
        }
    }
}

// MARK: - Bundle 扩展

extension Bundle {
    private static var bundle: Bundle?

    static func setLanguage(_ language: String) {
        defer {
            object_setClass(Bundle.main, AnyLanguageBundle.self)
        }

        guard let path = Bundle.main.path(forResource: language, ofType: "lproj") else {
            bundle = nil
            return
        }

        bundle = Bundle(path: path)
    }

    static func localizedBundle() -> Bundle! {
        return bundle ?? Bundle.main
    }
}

@objc final class AnyLanguageBundle: Bundle, @unchecked Sendable {
    private static let fallbackLanguage = "en"

    override func localizedString(forKey key: String, value: String?, table tableName: String?)
        -> String
    {
        guard let bundle = Bundle.localizedBundle() else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }

        let fallbackValue = value ?? ""
        let result = bundle.localizedString(forKey: key, value: fallbackValue, table: tableName)
        // NSLocalizedString 默认 value 为空串，未找到时返回 ""；部分调用可能传 key。两种都视为未找到，回退英文
        let notFound = result.isEmpty || result == key
        if notFound, let enPath = Bundle.main.path(forResource: Self.fallbackLanguage, ofType: "lproj"),
           let enBundle = Bundle(path: enPath)
        {
            let enResult = enBundle.localizedString(forKey: key, value: key, table: tableName)
            if enResult != key { return enResult }
        }
        // 都未找到时：有 value 用 value，否则用 key，避免显示空
        return result.isEmpty ? (fallbackValue.isEmpty ? key : fallbackValue) : result
    }
}
