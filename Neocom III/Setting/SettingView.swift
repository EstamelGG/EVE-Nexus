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
    let iconName: String
    let detail: String? // 可选的详细描述
}


struct SettingView: View {
    // 模拟数据
    private let settings: [SettingItem] = [
        SettingItem(
            title: "Account",
            iconName: "person.fill",
            detail: "Manage your account"
        ),
        SettingItem(
            title: "Notifications",
            iconName: "bell.fill",
            detail: "Configure notifications"
        ),
        SettingItem(
            title: "Privacy",
            iconName: "lock.fill",
            detail: "Privacy settings"
        ),
        SettingItem(
            title: "General",
            iconName: "gearshape.fill",
            detail: "General application settings"
        )
    ]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(settings) { item in
                    NavigationLink(destination: Text("\(item.title) Details")) {
                        HStack {
                            // 图标
                            Image(systemName: item.iconName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                // 标题
                                Text(item.title)
                                    .font(.system(size: 16))
                                    .fontWeight(.medium)
                                // 详细信息（如果有）
                                if let detail = item.detail {
                                    Text(detail)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.vertical, 6) // 设置单元格垂直内边距
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingView()
}
