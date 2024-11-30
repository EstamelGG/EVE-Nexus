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
    
    init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
}

// 设置项管理器
class SettingsManager {
    static let shared = SettingsManager()

    // 获取所有设置项
    func getSettingItems() -> [SettingItem] {
        return [
            SettingItem(title: "Language", detail: "Select your language"),
            // 可以在此处添加更多的设置项
            // SettingItem(title: "Notifications", detail: "Enable notifications"),
        ]
    }
}

// 设置视图页面
struct SettingView: View {
    // 使用 @AppStorage 存储主题模式，自动与 UserDefaults 绑定
    @AppStorage("selectedTheme") private var selectedTheme: String = "system" // 默认为系统模式
    @State private var currentIcon: String = "circle.lefthalf.fill" // 初始图标为跟随系统
    
    var body: some View {
        NavigationView {
            List {
                // 设置项：外观
                Section(header: Text("Appearance")) {
                    Button(action: toggleAppearance) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Appearance")
                                    .font(.system(size: 16))
                                // 显示当前颜色模式的详细信息
                                Text(getAppearanceDetail() ?? "Unknown")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            // 图标，显示在右侧
                            Image(systemName: currentIcon)
                                .font(.system(size: 20))
                                .frame(width: 36, height: 36)
                                .foregroundColor(.blue)
                        }.frame(height: 36)
                    }
                }
                
                // 获取动态生成的设置项
                Section(header: Text("Other Settings")) {
                    ForEach(SettingsManager.shared.getSettingItems()) { item in
                        NavigationLink(destination: Text("\(item.title) Details")) {
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
            .navigationTitle("Settings")
            .onAppear {
                // 根据 selectedTheme 设置 currentIcon
                updateCurrentIcon()
            }
        }
    }

    private func toggleAppearance() {
        // 切换主题模式的操作
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
        // 根据 selectedTheme 设置 currentIcon
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
    
    // 获取当前颜色模式的详细信息
    private func getAppearanceDetail() -> String? {
        switch selectedTheme {
        case "light":
            return "Light"
        case "dark":
            return "Dark"
        case "system":
            return "Auto"
        default:
            return nil
        }
    }
}

#Preview {
    SettingView()
}
