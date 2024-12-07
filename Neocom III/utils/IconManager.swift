import Foundation
import UIKit
import SwiftUI
import Zip

class IconManager {
    static let shared = IconManager()
    private let fileManager = FileManager.default
    private var imageCache = NSCache<NSString, UIImage>()
    private var iconsDirectory: URL?
    
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
        print("Icons directory setup at: \(iconsDir.path)")
    }
    
    func loadUIImage(for iconName: String) -> UIImage {
        // 如果缓存中有，直接返回
        let cacheKey = NSString(string: iconName)
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        // 从解压后的目录中读取图片
        guard let iconsDirectory = iconsDirectory else {
            print("Icons directory is not set")
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
                return image
            }
        }
        
        print("Failed to load image: \(iconName)")
        return UIImage()
    }
    
    func loadImage(for iconName: String) -> Image {
        Image(uiImage: loadUIImage(for: iconName))
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
        }
    }
    
    func unzipIcons(from sourceURL: URL, to destinationURL: URL, progress: @escaping (Double) -> Void) async throws {
        print("Starting icon extraction from \(sourceURL.path)")
        print("Extracting to: \(destinationURL.path)")
        
        try? fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try Zip.unzipFile(sourceURL, destination: destinationURL, overwrite: true, password: nil) { progressValue in
            progress(progressValue)
        }
        
        // 更新内部的 iconsDirectory
        self.iconsDirectory = destinationURL
        print("Successfully extracted icons to \(destinationURL.path)")
    }
}
