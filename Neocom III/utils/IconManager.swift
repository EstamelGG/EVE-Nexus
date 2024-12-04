import Foundation
import SwiftUI

class IconManager {
    // 单例模式，确保只有一个实例
    static let shared = IconManager()
    
    // 缓存已加载的图像
    private var imageCache = NSCache<NSString, UIImage>()

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
        // 先检查缓存
        if let cachedImage = imageCache.object(forKey: iconFileNew as NSString) {
            // 如果缓存中有图像，直接返回
            return Image(uiImage: cachedImage)
        }
        
        let iconFilePath = self.iconFilePath(for: iconFileNew)
        
        if FileManager.default.fileExists(atPath: iconFilePath) {
            // 使用 UIImage 来加载文件，转换为 SwiftUI 的 Image
            if let uiImage = UIImage(contentsOfFile: iconFilePath) {
                // 缓存加载的图像
                imageCache.setObject(uiImage, forKey: iconFileNew as NSString)
                return Image(uiImage: uiImage)
            }
        }
        
        // 默认图像文件路径
        let defaultIconFile = "items_7_64_15.png"
        let defaultIconFilePath = self.iconFilePath(for: defaultIconFile)
        
        // 检查默认图像是否存在
        if FileManager.default.fileExists(atPath: defaultIconFilePath) {
            if let defaultImage = UIImage(contentsOfFile: defaultIconFilePath) {
                // 缓存默认图像
                imageCache.setObject(defaultImage, forKey: defaultIconFile as NSString)
                return Image(uiImage: defaultImage)
            }
        }
        
        // 如果都没有找到，返回系统默认图标
        return Image(systemName: "questionmark.circle")
    }
}
