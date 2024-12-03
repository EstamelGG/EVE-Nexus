//
//  IconManager.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/12/3.
//

import Foundation
import SwiftUI

class IconManager {
    // 单例模式，确保只有一个实例
    static let shared = IconManager()

    private init() {}

    // 获取图片路径
    private func iconFilePath(for iconFileNew: String) -> String {
        let iconFilePath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Icons")
            .appendingPathComponent(iconFileNew)
            .path
        
        return iconFilePath
    }
    
    // 加载图片
    func loadImage(for iconFileNew: String) -> Image {
        let iconFilePath = self.iconFilePath(for: iconFileNew)
        
        if FileManager.default.fileExists(atPath: iconFilePath) {
            // 使用 UIImage 来加载文件，转换为 SwiftUI 的 Image
            if let uiImage = UIImage(contentsOfFile: iconFilePath) {
                return Image(uiImage: uiImage)
            }
        }
        
        // 返回默认图标，防止文件不存在时崩溃
        return Image(systemName: "questionmark.circle")
    }
}
