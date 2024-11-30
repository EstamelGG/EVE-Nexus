//
//  SelectLanguageView.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/11/30.
//

import SwiftUI

struct SelectLanguageView: View {
    // 语言列表
    let languages = ["English", "中文"]
    // 跟踪用户选择的语言
    @State private var selectedLanguageIndex: Int? = nil
    
    var body: some View {
        NavigationView {
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
                    if selectedLanguageIndex == index {
                        selectedLanguageIndex = nil  // 如果点击已选中项，取消选择
                    } else {
                        selectedLanguageIndex = index  // 否则设置为新的选择
                    }
                }
            }
            .navigationBarTitle("Select Language")  // 设置标题
        }
    }
}

#Preview {
    SelectLanguageView()
}
