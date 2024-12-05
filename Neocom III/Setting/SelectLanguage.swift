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
        "中文": "zh-Hans"
    ]
    
    @AppStorage("selectedLanguage") var storedLanguage: String?
    @State private var selectedLanguage: String?
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showConfirmationDialog = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                ForEach(languages.keys.sorted(), id: \.self) { language in
                    LanguageOptionView(
                        language: language,
                        isSelected: language == selectedLanguage,
                        onTap: {
                            if language != selectedLanguage {
                                selectedLanguage = language
                                showConfirmationDialog = true
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
        .navigationTitle(NSLocalizedString("Main_Setting_Select Language", comment: ""))
        .onAppear(perform: setupInitialLanguage)
        .confirmationDialog(
            NSLocalizedString("Main_Setting_SwitchLanguageConfirmation", comment: ""),
            isPresented: $showConfirmationDialog,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Continue", comment: ""), role: .destructive) {
                applyLanguageChange()
            }
            
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                restoreOriginalLanguage()
            }
        }
    }
    
    private func setupInitialLanguage() {
        if let storedLang = storedLanguage,
           let defaultLanguage = languages.first(where: { $0.value == storedLang })?.key {
            selectedLanguage = defaultLanguage
        } else {
            let systemLanguage = Locale.preferredLanguages.first ?? "en"
            if let defaultLanguage = languages.first(where: { $0.value == systemLanguage })?.key {
                selectedLanguage = defaultLanguage
            }
        }
    }
    
    private func applyLanguageChange() {
        guard let language = selectedLanguage,
              let languageCode = languages[language] else { return }
        
        // 1. 保存新的语言设置
        storedLanguage = languageCode
        
        // 2. 更新语言设置
        UserDefaults.standard.set([languageCode], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        
        // 3. 应用新的语言设置
        if let languageBundlePath = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let _ = Bundle(path: languageBundlePath) {
            Bundle.setLanguage(languageCode)
        }
        
        // 4. 发送通知以重新加载UI
        NotificationCenter.default.post(name: NSNotification.Name("LanguageChanged"), object: nil)
        
        // 5. 清空所有缓存并重新加载数据库
        DatabaseBrowserView.clearCache()  // 清除导航缓存
        databaseManager.clearCache()      // 清除 SQL 查询缓存
        databaseManager.loadDatabase()
        
        // 6. 关闭当前视图
        dismiss()
    }
    
    private func restoreOriginalLanguage() {
        if let storedLang = storedLanguage,
           let defaultLanguage = languages.first(where: { $0.value == storedLang })?.key {
            selectedLanguage = defaultLanguage
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
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = Bundle.localizedBundle() {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        } else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
    }
}

#Preview {
    SelectLanguageView(databaseManager: DatabaseManager())
}
