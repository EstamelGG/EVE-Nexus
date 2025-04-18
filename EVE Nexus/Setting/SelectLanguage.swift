import SwiftUI

// 语言选项视图组件
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

struct SelectLanguageView: View {
    // 语言名称与代号映射
    let languages: [String: String] = [
        "English": "en",
        "中文": "zh-Hans",
    ]

    @AppStorage("selectedLanguage") private var selectedLanguage: String = "en"
    @ObservedObject var databaseManager: DatabaseManager
    @State private var displayLanguage: String = "English"

    var body: some View {
        List {
            Section {
                ForEach(languages.keys.sorted(), id: \.self) { language in
                    LanguageOptionView(
                        language: language,
                        isSelected: language == displayLanguage,
                        onTap: {
                            if language != displayLanguage {
                                displayLanguage = language
                                applyLanguageChange(language)
                            }
                        }
                    )
                }
            } header: {
                Text(NSLocalizedString("Main_Setting_Language", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Select_Language", comment: ""))
        .onAppear(perform: setupInitialLanguage)
    }

    private func setupInitialLanguage() {
        // 根据当前 selectedLanguage 设置显示语言
        if let defaultLanguage = languages.first(where: { $0.value == selectedLanguage })?.key {
            displayLanguage = defaultLanguage
        } else {
            // 如果没有匹配的语言，默认使用英语
            displayLanguage = "English"
            selectedLanguage = "en"
        }
    }

    private func applyLanguageChange(_ language: String) {
        guard let languageCode = languages[language] else { return }

        // 1. 保存新的语言设置
        selectedLanguage = languageCode

        // 2. 更新系统语言设置
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()

        // 3. 应用新的语言设置
        if let languageBundlePath = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
            Bundle(path: languageBundlePath) != nil
        {
            Bundle.setLanguage(languageCode)
        }

        // 4. 清空所有缓存并重新加载数据库
        DatabaseBrowserView.clearCache()  // 清除导航缓存
        databaseManager.clearCache()  // 清除 SQL 查询缓存
        databaseManager.loadDatabase()

        // 5. 延迟发送通知，让视图有时间完成关闭动画
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // 发送通知以重新加载UI
            NotificationCenter.default.post(
                name: NSNotification.Name("LanguageChanged"), object: nil
            )
        }
    }
}

// Bundle 扩展，用于切换语言
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

// 自定义 Bundle 类，用于语言切换
@objc final class AnyLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?)
        -> String
    {
        if let bundle = Bundle.localizedBundle() {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        } else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
    }
}
