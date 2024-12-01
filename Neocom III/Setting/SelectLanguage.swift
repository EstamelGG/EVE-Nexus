import SwiftUI

struct SelectLanguageView: View {
    // 语言名称与代号映射
    let languages: [String: String] = [
        "English": "en",
        "中文": "zh-Hans",
        "Français": "fr",
        "Español": "es"
        // 可以继续添加其他语言
    ]
    
    // 使用 @AppStorage 来持久化存储用户选择的语言
    @AppStorage("selectedLanguage") var storedLanguage: String?
    
    // 跟踪用户选择的语言
    @State private var selectedLanguage: String?
    
    var body: some View {
        NavigationView {
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
                            storedLanguage = languages[language]
                        }
                    }
                }
            }
            .navigationTitle("Select Language")
            .onAppear {
                // 初始加载时根据存储的语言设置
                if let storedLang = storedLanguage, let defaultLanguage = languages.first(where: { $0.value == storedLang })?.key {
                    selectedLanguage = defaultLanguage
                } else {
                    // 如果没有存储的语言，使用系统语言或默认语言
                    selectedLanguage = "English"
                    storedLanguage = "en"
                }
            }
        }
    }
}

#Preview {
    SelectLanguageView()
}
