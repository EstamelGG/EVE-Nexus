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
    
    // 初始化时可以提供 detail 或使用默认值 nil
    init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }
}

struct SettingView: View {
    // 模拟数据
    private let settings: [SettingItem] = [
        SettingItem(title: "Appearance"),
        // SettingItem(title: "Notifications"),
        SettingItem(title: "Language", detail: "Select your language")
    ]
    
    var body: some View {
        NavigationView {
            List {
                ForEach(settings) { item in
                    NavigationLink(destination: Text("\(item.title) Details")) {
                        HStack {
                            VStack(alignment: .leading) {
                                // 标题
                                Text(item.title)
                                    .font(.system(size: 15))
                                    .fontWeight(.medium)
                                // 详细信息（如果有）
                                if let detail = item.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                            }.frame(height: 36) // 确保单元格最大高度为 20
                        }.frame(height: 36) // 确保单元格最大高度为 20
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
