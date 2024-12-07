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
        guard let bundleURL = Bundle.main.url(forResource: "icons", withExtension: "zip") else {
            print("Failed to find icons.zip in bundle")
            return
        }
        
        do {
            let cacheURL = try fileManager.url(for: .cachesDirectory,
                                             in: .userDomainMask,
                                             appropriateFor: nil,
                                             create: true)
            let iconsDir = cacheURL.appendingPathComponent("Icons")
            
            // 如果图标目录不存在，解压图标
            if !fileManager.fileExists(atPath: iconsDir.path) {
                try? fileManager.createDirectory(at: iconsDir, withIntermediateDirectories: true)
                try Zip.unzipFile(bundleURL, destination: iconsDir, overwrite: true, password: nil)
            }
            
            self.iconsDirectory = iconsDir
            print("Successfully setup icons directory")
        } catch {
            print("Error setting up icons directory: \(error)")
        }
    }
    
    func loadUIImage(for iconName: String) -> UIImage {
        // 如果缓存中有，直接返回
        let cacheKey = NSString(string: iconName)
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        // 从解压后的目录中读取图片
        guard let iconsDirectory = iconsDirectory else {
            return UIImage()
        }
        
        let iconURL = iconsDirectory.appendingPathComponent(iconName)
        guard let imageData = try? Data(contentsOf: iconURL),
              let image = UIImage(data: imageData) else {
            print("Failed to load image: \(iconName)")
            return UIImage()
        }
        
        // 缓存图片
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }
    
    func loadImage(for iconName: String) -> Image {
        Image(uiImage: loadUIImage(for: iconName))
    }
    
    func preloadCommonIcons(icons: [String]) {
        DispatchQueue.global(qos: .background).async {
            for iconName in icons {
                _ = self.loadUIImage(for: iconName)
            }
        }
    }
    
    func clearCache() {
        imageCache.removeAllObjects()
        if let iconsDirectory = iconsDirectory {
            try? fileManager.removeItem(at: iconsDirectory)
            setupIconsDirectory()
        }
    }
    
    func unzipIcons(from sourceURL: URL, to destinationURL: URL, progress: @escaping (Double) -> Void) async throws {
        try? fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try Zip.unzipFile(sourceURL, destination: destinationURL, overwrite: true, password: nil) { progressValue in
            progress(progressValue)
        }
    }
}
