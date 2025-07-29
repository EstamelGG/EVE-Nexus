import SwiftUI

struct LanguageMapSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguages: [String] = []
    
    init() {
        // 从UserDefaults读取选中的语言，如果没有则使用默认值
        let savedLanguages = UserDefaults.standard.stringArray(forKey: LanguageMapConstants.userDefaultsKey) ?? LanguageMapConstants.languageMapDefaultLanguages
        _selectedLanguages = State(initialValue: savedLanguages)
    }
    
    let availableLanguages = LanguageMapConstants.availableLanguages
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(NSLocalizedString("Language_Map_Settings_Description", comment: "选择要在语言映射中显示的语言。英文是默认语言，您需要至少选择一种其他语言。"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
                
                Section {
                    ForEach(Array(availableLanguages.keys).sorted(), id: \.self) { langCode in
                        HStack {
                            Text(availableLanguages[langCode] ?? langCode)
                            Spacer()
                            if selectedLanguages.contains(langCode) {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleLanguage(langCode)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Language_Map_Settings_Select_Languages", comment: "选择语言"))
                } footer: {
                    if selectedLanguages.count < 2 {
                        Text(NSLocalizedString("Language_Map_Settings_Minimum_Languages", comment: "请至少选择2种语言"))
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Language_Map_Settings_Title", comment: "语言映射设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Common_Cancel", comment: "取消")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                    .disabled(selectedLanguages.count < 2)
                }
            }
        }
    }
    
    private func toggleLanguage(_ langCode: String) {
        if langCode == "en" {
            // 英文不能取消选择
            return
        }
        
        if selectedLanguages.contains(langCode) {
            // 如果只有2种语言，不允许取消选择
            if selectedLanguages.count <= 2 {
                return
            }
            selectedLanguages.removeAll { $0 == langCode }
        } else {
            selectedLanguages.append(langCode)
        }
        
        // 保存到UserDefaults
        UserDefaults.standard.set(selectedLanguages, forKey: LanguageMapConstants.userDefaultsKey)
    }
} 
