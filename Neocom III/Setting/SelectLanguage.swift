import SwiftUI

struct SelectLanguageView: View {
    // 语言名称与代号映射
    let languages: [String: String] = [
        "English": "en",
        "中文": "zh-Hans",
        "Français": "fr",
        "Español": "es"
    ]
    
    // 使用 @AppStorage 来持久化存储用户选择的语言
    @AppStorage("selectedLanguage") var storedLanguage: String?
    
    // 跟踪用户选择的语言
    @State private var selectedLanguage: String?
    
    // 控制弹窗的显示
    @State private var showConfirmationDialog = false
    
    var body: some View {
        List {
            Section(header: Text("Language Packs")
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
                        // 更新选择的语言
                        selectedLanguage = language
                        storedLanguage = languages[language] // 存储用户选择的语言
                        
                        // 显示确认弹窗
                        showConfirmationDialog = true
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
                // 如果没有存储的语言，则不做任何勾选
                selectedLanguage = nil
            }
        }
        .confirmationDialog(
            NSLocalizedString("Main_Setting_SwitchLanguageConfirmation", comment: ""),
            isPresented: $showConfirmationDialog,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Continue", comment: ""), role: .destructive) {
                // 等待 0.2 秒后退出应用
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    exit(0) // 退出应用
                }
            }
            
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {
                // 取消，什么都不做
            }
        }
    }
}

#Preview {
    SelectLanguageView()
}
