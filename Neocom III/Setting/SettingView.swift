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

struct SettingView: View {
    // 使用 @AppStorage 存储主题模式，自动与 UserDefaults 绑定
    @AppStorage("selectedTheme") private var selectedTheme: String = "system" // 默认为系统模式
    @State private var currentIcon: String = "sun.max.fill" // 初始图标为白天模式

    init() {
        // 根据保存的主题模式设置初始图标
        if selectedTheme == "light" {
            _currentIcon = State(initialValue: "sun.max.fill")
        } else if selectedTheme == "dark" {
            _currentIcon = State(initialValue: "moon.fill")
        } else {
            _currentIcon = State(initialValue: "circle.lefthalf.fill")
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // 设置项：外观
                Section(header: Text("Appearance")) {
                    Button(action: toggleAppearance) {
                        HStack {
                            Text("Appearance")
                            Spacer()
                            Image(systemName: currentIcon)
                                .font(.system(size: 15))
                                .frame(width: 36, height: 36)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // 其他设置项
                ForEach([SettingItem(title: "Language", detail: "Select your language")]) { item in
                    NavigationLink(destination: Text("\(item.title) Details")) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                    .font(.system(size: 15))
                                    .fontWeight(.medium)
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                            }
                            .frame(height: 36)
                        }
                        .frame(height: 36)
                    }
                }
            }
            .navigationTitle("Settings")
            .preferredColorScheme(selectedTheme == "light" ? .light : (selectedTheme == "dark" ? .dark : nil))
        }
    }

    private func toggleAppearance() {
        // 切换主题模式的操作
        switch currentIcon {
        case "sun.max.fill":
            selectedTheme = "dark"
            currentIcon = "moon.fill"
        case "moon.fill":
            selectedTheme = "system"
            currentIcon = "circle.lefthalf.fill"
        case "circle.lefthalf.fill":
            selectedTheme = "light"
            currentIcon = "sun.max.fill"
        default:
            break
        }
    }
}

#Preview {
    SettingView()
}
