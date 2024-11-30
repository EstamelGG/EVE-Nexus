import SwiftUI

struct SelectLanguageView: View {
    // 语言列表
    let languages = [
        "English",
        "中文"
    ]
    
    // 跟踪用户选择的语言
    @State private var selectedLanguageIndex: Int?
    
    // 使用 @AppStorage 来持久化存储用户选择的语言
    @AppStorage("selectedLanguage") var selectedLanguage: String?
    
    var body: some View {
        List(languages.indices, id: \.self) { index in
            HStack {
                Text(languages[index])
                
                Spacer()
                
                // 显示勾选标记
                if index == selectedLanguageIndex {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(Rectangle())  // 确保点击区域完整
            .onTapGesture {
                // 用户点击时更新选择的语言
                selectedLanguage = languages[index]
                selectedLanguageIndex = index
            }
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Select Language", comment: ""))
        .onAppear {
            // 默认选择当前存储的语言
            if let language = selectedLanguage {
                if let index = languages.firstIndex(of: language) {
                    selectedLanguageIndex = index
                }
            } else {
                // 如果没有选择语言，则根据系统语言设置默认值
                let systemLanguage = Locale.preferredLanguages.first ?? "en"
                selectedLanguage = systemLanguage.starts(with: "zh") ? "中文" : "English"
                selectedLanguageIndex = systemLanguage.starts(with: "zh") ? 1 : 0
            }
        }
    }
}

#Preview {
    SelectLanguageView()
}
