//
//  SettingView.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/11/30.
//

import SwiftUI

// 定义设置项
struct SettingItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String? // 可选的详细描述
    var destination: AnyView? // 增加目标视图属性
    
    init(title: String, detail: String? = nil, destination: AnyView? = nil) {
        self.title = title
        self.detail = detail
        self.destination = destination
    }
}

// 设置项管理器
class SettingsManager {
    static let shared = SettingsManager()

    // 获取所有设置项
    func getSettingItems() -> [SettingItem] {
        return [
            SettingItem(
                title: NSLocalizedString("Main_Setting_Language", comment: "Language section"),
                detail: NSLocalizedString("Main_Setting_Select your language", comment: ""),
                destination: AnyView(SelectLanguageView())
            ),
            // 可以在此处添加更多的设置项
            // SettingItem(title: "Notifications", detail: "Enable notifications"),
        ]
    }
}

// 设置视图页面
struct SettingView: View {
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @State private var currentIcon: String = "circle.lefthalf.fill"
    
    var body: some View {
        NavigationView {
            List {
                // 设置项：外观
                Section(header: Text(NSLocalizedString("Main_Setting_Appearance", comment: ""))) {
                    Button(action: toggleAppearance) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(NSLocalizedString("Main_Setting_ColorMode", comment: ""))
                                    .font(.system(size: 16))
                                Text(getAppearanceDetail() ?? "Unknown")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Image(systemName: currentIcon)
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .foregroundColor(.blue)
                        }
                        .frame(height: 36)
                    }
                }
                
                // 设置项：其他
                Section(header: Text(NSLocalizedString("Main_Setting_Others", comment: ""))) {
                    ForEach(SettingsManager.shared.getSettingItems()) { item in
                        NavigationLink(destination: item.destination) { // 确保导航到正确的视图
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.title)
                                        .font(.system(size: 16))
                                        .fontWeight(.medium)
                                    if let detail = item.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .frame(height: 36)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
            .onAppear {
                updateCurrentIcon()
            }
        }
    }
    
    private func toggleAppearance() {
        switch selectedTheme {
        case "light":
            selectedTheme = "dark"
            currentIcon = "moon.fill"
        case "dark":
            selectedTheme = "system"
            currentIcon = "circle.lefthalf.fill"
        case "system":
            selectedTheme = "light"
            currentIcon = "sun.max.fill"
        default:
            break
        }
    }

    private func updateCurrentIcon() {
        switch selectedTheme {
        case "light":
            currentIcon = "sun.max.fill"
        case "dark":
            currentIcon = "moon.fill"
        case "system":
            currentIcon = "circle.lefthalf.fill"
        default:
            currentIcon = "circle.lefthalf.fill"
        }
    }

    private func getAppearanceDetail() -> String? {
        switch selectedTheme {
        case "light":
            return NSLocalizedString("Main_Setting_Light", comment: "")
        case "dark":
            return NSLocalizedString("Main_Setting_Dark", comment: "")
        case "system":
            return NSLocalizedString("Main_Setting_Auto", comment: "")
        default:
            return nil
        }
    }
}

#Preview {
    SettingView()
}
