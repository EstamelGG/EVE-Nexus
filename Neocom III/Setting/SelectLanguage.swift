import SwiftUI

struct SelectLanguageView: View {
    // 语言名称与代号映射
    let languages: [String: String] = [
        "English": "en",
        "中文": "zh-Hans"
    ]
    
    // 使用 @AppStorage 来持久化存储用户选择的语言
    @AppStorage("selectedLanguage") var storedLanguage: String?
    
    // 跟踪用户选择的语言
    @State private var selectedLanguage: String?
    
    // 注入数据库管理器
    @ObservedObject var databaseManager: DatabaseManager
    
    // 控制弹窗的显示
    @State private var showConfirmationDialog = false
    
    // 环境变量来获取当前的 Scene
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Main_Setting_Language Packs", comment: ""))
                        .font(.headline)
                        .foregroundColor(.primary)
            ) {
                ForEach(languages.keys.sorted(), id: \.self) { language in
                    HStack {
                        Text(language)
                        
                        Spacer()
                        
                        // 显示勾选标记
                        if language == selectedLanguage {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())  // 确保点击区域完整
                    .onTapGesture {
                        if language != selectedLanguage {
                            // 更新选择的语言
                            selectedLanguage = language
                            
                            // 显示确认弹窗
                            showConfirmationDialog = true
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Select Language", comment: ""))
        .onAppear {
            // 根据存储的语言来设置默认勾选项
            if let storedLang = storedLanguage, let defaultLanguage = languages.first(where: { $0.value == storedLang })?.key {
                selectedLanguage = defaultLanguage
            } else {
                // 如果没有存储的语言，则使用系统语言
                let systemLanguage = Locale.preferredLanguages.first ?? "en"
                if let defaultLanguage = languages.first(where: { $0.value == systemLanguage })?.key {
                    selectedLanguage = defaultLanguage
                }
            }
        }
        .confirmationDialog(
            NSLocalizedString("Main_Setting_SwitchLanguageConfirmation", comment: ""),
            isPresented: $showConfirmationDialog,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Continue", comment: ""), role: .destructive) {
                if let language = selectedLanguage, let languageCode = languages[language] {
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
                    
                    // 5. 重新加载数据库
                    databaseManager.reloadDatabase()
                    // 6. 关闭当前视图
                    dismiss()
                }
            }
            
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                // 取消时恢复原来的选择
                if let storedLang = storedLanguage, let defaultLanguage = languages.first(where: { $0.value == storedLang })?.key {
                    selectedLanguage = defaultLanguage
                }
            }
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
class AnyLanguageBundle: Bundle {
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
