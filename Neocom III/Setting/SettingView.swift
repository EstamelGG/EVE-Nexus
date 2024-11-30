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
    // 模拟数据
    private let settings: [SettingItem] = [
        SettingItem(title: "Appearance"),
        SettingItem(title: "Language", detail: "Select your language")
    ]
    
    // 管理当前的主题模式
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedColorScheme: ColorScheme? = nil
    @State private var currentIcon: String = "sun.max.fill" // 初始图标为白天模式
    
    var body: some View {
        NavigationView {
            List {
                // 设置项：外观
                ForEach(settings) { item in
                    if item.title == "Appearance" {
                        Section(header: Text(item.title).font(.system(size: 16))) {
                            HStack {
                                Text("Appearance")
                                Spacer()
                                // 切换主题模式的按钮
                                Button(action: toggleAppearance) {
                                    Image(systemName: currentIcon)
                                        .font(.system(size: 15))
                                        .frame(width: 36, height: 36)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    } else {
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
            }
            .navigationTitle("Settings")
            .preferredColorScheme(selectedColorScheme ?? colorScheme)
        }
    }
    
    // 切换主题模式的操作
    private func toggleAppearance() {
        // 按顺序循环切换图标和主题模式
        switch currentIcon {
        case "sun.max.fill":
            // 当前是白天模式，切换到黑暗模式
            selectedColorScheme = .dark
            currentIcon = "moon.fill"
        case "moon.fill":
            // 当前是黑暗模式，切换到系统跟随模式
            selectedColorScheme = nil
            currentIcon = "circle.lefthalf.fill"
        case "circle.lefthalf.fill":
            // 当前是系统跟随模式，切换到白天模式
            selectedColorScheme = .light
            currentIcon = "sun.max.fill"
        default:
            break
        }
    }
}

#Preview {
    SettingView()
}
