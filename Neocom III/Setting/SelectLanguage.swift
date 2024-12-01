import SwiftUI

struct SelectLanguageView: View {
    // 语言名称与代号映射
    let languages: [String: String] = [
        "English": "en",
        "中文": "zh-Hans"
    ]
    
    // 跟踪用户选择的语言
    @State private var selectedLanguage: String?
    
    // 使用 @AppStorage 来持久化存储用户选择的语言
    @AppStorage("selectedLanguage") var storedLanguage: String?
    
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
                        }
                    }
                    .contentShape(Rectangle())  // 确保点击区域完整
                    .onTapGesture {
                        // 用户点击时更新选择的语言
                        selectedLanguage = language
                        storedLanguage = languages[language]
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Select Language", comment: ""))
        .onAppear {
            // 默认选择当前存储的语言
            if let languageCode = storedLanguage,
               let language = languages.first(where: { $0.value == languageCode })?.key {
                selectedLanguage = language
            } else {
                // 如果没有选择语言，则根据系统语言设置默认值
                let systemLanguage = Locale.preferredLanguages.first ?? "en"
                if let defaultLanguage = languages.first(where: { systemLanguage.starts(with: $0.value) })?.key {
                    selectedLanguage = defaultLanguage
                    storedLanguage = languages[defaultLanguage]
                } else {
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
