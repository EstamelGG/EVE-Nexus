import Foundation
import SwiftUI

class IconManager {
    // 单例模式，确保只有一个实例
    static let shared = IconManager()
    
    // 缓存已加载的图像
    private var imageCache = NSCache<NSString, UIImage>()
    
    // 设置缓存的最大容量（单位：字节）
    private let maxCacheSize = 50 * 1024 * 1024  // 50MB
    
    // 设置缓存的最大数量
    private let maxCacheCount = 1000
    
    private init() {
        // 配置缓存
        imageCache.totalCostLimit = maxCacheSize
        imageCache.countLimit = maxCacheCount
        
        // 注册内存警告通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // 注册语言变更通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: NSNotification.Name("LanguageChanged"),
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // 清除缓存
    @objc func clearCache() {
        imageCache.removeAllObjects()
        print("图片缓存已清空")
    }

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
        // 如果文件名为空，直接返回默认图标
        guard !iconFileNew.isEmpty else {
            return loadDefaultImage()
        }
        
        // 先检查缓存
        if let cachedImage = imageCache.object(forKey: iconFileNew as NSString) {
            print("从缓存加载图片: \(iconFileNew)")
            return Image(uiImage: cachedImage)
        }
        
        let iconFilePath = self.iconFilePath(for: iconFileNew)
        
        if FileManager.default.fileExists(atPath: iconFilePath),
           let uiImage = UIImage(contentsOfFile: iconFilePath) {
            // 计算图片大小作为缓存成本
            let cost = Int(uiImage.size.width * uiImage.size.height * 4)  // 假设每个像素4字节
            // 缓存加载的图像
            imageCache.setObject(uiImage, forKey: iconFileNew as NSString, cost: cost)
            print("缓存新图片: \(iconFileNew), 大小: \(cost/1024)KB")
            return Image(uiImage: uiImage)
        }
        
        // 如果找不到图片，返回默认图片
        return loadDefaultImage()
    }
    
    // 加载默认图片
    private func loadDefaultImage() -> Image {
        let defaultIconFile = "items_7_64_15.png"
        
        // 检查缓存中是否有默认图片
        if let cachedDefaultImage = imageCache.object(forKey: defaultIconFile as NSString) {
            return Image(uiImage: cachedDefaultImage)
        }
        
        // 加载默认图片文件
        let defaultIconFilePath = self.iconFilePath(for: defaultIconFile)
        if FileManager.default.fileExists(atPath: defaultIconFilePath),
           let defaultImage = UIImage(contentsOfFile: defaultIconFilePath) {
            // 缓存默认图像
            let cost = Int(defaultImage.size.width * defaultImage.size.height * 4)
            imageCache.setObject(defaultImage, forKey: defaultIconFile as NSString, cost: cost)
            return Image(uiImage: defaultImage)
        }
        
        // 如果都没有找到，返回系统默认图标
        return Image(systemName: "questionmark.circle")
    }
    
    // 预加载常用图标
    func preloadCommonIcons(icons: [String]) {
        DispatchQueue.global(qos: .background).async {
            for icon in icons {
                if self.imageCache.object(forKey: icon as NSString) == nil {
                    let iconFilePath = self.iconFilePath(for: icon)
                    if let uiImage = UIImage(contentsOfFile: iconFilePath) {
                        let cost = Int(uiImage.size.width * uiImage.size.height * 4)
                        self.imageCache.setObject(uiImage, forKey: icon as NSString, cost: cost)
                    }
                }
            }
            print("预加载完成 \(icons.count) 个图标")
        }
    }
}
