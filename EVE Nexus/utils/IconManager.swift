import Foundation
import UIKit
import SwiftUI
import Zip

class IconManager {
    static let shared = IconManager()
    private let fileManager = FileManager.default
    private var imageCache = NSCache<NSString, UIImage>()
    private var iconsDirectory: URL?
    private let defaults = UserDefaults.standard
    private let extractionStateKey = "IconExtractionComplete"
    
    private init() {
        setupIconsDirectory()
    }
    
    private func setupIconsDirectory() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let iconsDir = documentsURL.appendingPathComponent("Icons")
        
        // 如果图标目录不存在，创建它
        if !fileManager.fileExists(atPath: iconsDir.path) {
            try? fileManager.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        }
        
        self.iconsDirectory = iconsDir
        Logger.info("Icons directory setup at: \(iconsDir.path)")
    }
    
    var isExtractionComplete: Bool {
        get {
            Logger.debug("正在从 UserDefaults 读取键: \(extractionStateKey)")
            return defaults.bool(forKey: extractionStateKey)
        }
        set {
            Logger.debug("正在写入 UserDefaults，键: \(extractionStateKey), 值: \(newValue)")
            defaults.set(newValue, forKey: extractionStateKey)
        }
    }
    
    func loadUIImage(for iconName: String) -> UIImage {
        // 如果缓存中有，直接返回
        let cacheKey = NSString(string: iconName)
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            // Logger.info("Load image from cache \(cacheKey).")
            return cachedImage
        }
        
        // 从解压后的目录中读取图片
        guard let iconsDirectory = iconsDirectory else {
            Logger.error("Icons directory is not set")
            return UIImage()
        }
        
        // 尝试不同的扩展名组合
        let possibleNames = [
            iconName,
            iconName.lowercased(),
            iconName.replacingOccurrences(of: ".png", with: ".PNG")
        ]
        
        for name in possibleNames {
            let iconURL = iconsDirectory.appendingPathComponent(name)
            if let imageData = try? Data(contentsOf: iconURL),
               let image = UIImage(data: imageData) {
                // 缓存图片
                imageCache.setObject(image, forKey: cacheKey)
                // Logger.info("Load image from disk \(cacheKey).")
                return image
            }
        }
        
        Logger.warning("Failed to load image: \(iconName)")
        return UIImage()
    }
    
    func loadImage(for iconName: String) -> Image {
        // 先尝试从 Assets 加载
        if let uiImage = UIImage(named: iconName.replacingOccurrences(of: ".png", with: "")) {
            return Image(uiImage: uiImage)
        }
        
        // 如果 Assets 中找不到，从本地文件加载
        return Image(uiImage: loadUIImage(for: iconName))
    }
    
    func preloadCommonIcons(icons: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            for iconName in icons {
                _ = self.loadUIImage(for: iconName)
            }
        }
    }
    
    func clearCache() throws {
        imageCache.removeAllObjects()
        if let iconsDirectory = iconsDirectory {
            try fileManager.removeItem(at: iconsDirectory)
            setupIconsDirectory()
            // 重置解压状态
            isExtractionComplete = false
        }
    }
    
    func unzipIcons(from sourceURL: URL, to destinationURL: URL, progress: @escaping (Double) -> Void) async throws {
        Logger.debug("Starting icon extraction from \(sourceURL.path) to \(destinationURL.path)")
        
        // 重置解压状态
        isExtractionComplete = false
        
        try? fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try Zip.unzipFile(sourceURL, destination: destinationURL, overwrite: true, password: nil) { progressValue in
            progress(progressValue)
        }
        
        // 更新内部的 iconsDirectory
        self.iconsDirectory = destinationURL
        
        // 验证解压是否成功
        if let contents = try? fileManager.contentsOfDirectory(atPath: destinationURL.path),
           !contents.isEmpty {
            // 设置解压完成状态
            isExtractionComplete = true
            Logger.info("Successfully extracted \(contents.count) icons to \(destinationURL.path)")
        } else {
            throw IconManagerError.readError("Extraction failed: directory is empty")
        }
    }
    
    enum IconManagerError: Error {
        case readError(String)
    }
}
