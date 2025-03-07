import Foundation
import Kingfisher
import SwiftUI
import UIKit
import Zip

class IconManager {
    static let shared = IconManager()
    private let fileManager = FileManager.default
    private var imageCache = NSCache<NSString, UIImage>()
    private var iconsDirectory: URL?
    private var typeIconsDirectory: URL?
    private let defaults = UserDefaults.standard
    private let extractionStateKey = "IconExtractionComplete"

    private init() {
        setupIconsDirectory()
        setupTypeIconsDirectory()
    }

    private func setupIconsDirectory() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let iconsDir = documentsURL.appendingPathComponent("Icons")

        // 如果图标目录不存在，创建它
        if !fileManager.fileExists(atPath: iconsDir.path) {
            try? fileManager.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        }

        iconsDirectory = iconsDir
        Logger.info("Icons directory setup at: \(iconsDir.path)")
    }

    private func setupTypeIconsDirectory() {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let typeIconsDir = documentsURL.appendingPathComponent("type_icons")

        // 如果类型图标目录不存在，创建它
        if !fileManager.fileExists(atPath: typeIconsDir.path) {
            try? fileManager.createDirectory(at: typeIconsDir, withIntermediateDirectories: true)
        }

        typeIconsDirectory = typeIconsDir
        Logger.info("Type icons directory setup at: \(typeIconsDir.path)")
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

    // 从图标名称中提取ID
    private func extractTypeID(from iconName: String) -> Int? {
        // 检查是否以"icon_"开头
        guard iconName.hasPrefix("icon_") else {
            return nil
        }

        // 使用正则表达式提取ID
        let pattern = "icon_(\\d+)_"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsString = iconName as NSString
        let matches = regex.matches(
            in: iconName, options: [], range: NSRange(location: 0, length: nsString.length)
        )

        guard let match = matches.first, match.numberOfRanges > 1 else {
            return nil
        }

        let idRange = match.range(at: 1)
        let idString = nsString.substring(with: idRange)

        return Int(idString)
    }

    // 从在线API获取图标
    func loadTypeIconFromAPI(typeID: Int, size: Int = 64) async -> UIImage? {
        let iconName = "icon_\(typeID)_\(size).png"

        // 检查缓存目录中是否已存在
        if let image = loadTypeIconFromDisk(iconName: iconName) {
            return image
        }

        // 构建API URL
        let urlString = "https://images.evetech.net/types/\(typeID)/icon?size=\(size)"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL: \(urlString)")
            return nil
        }

        // 使用Kingfisher下载图像
        let destination = typeIconsDirectory?.appendingPathComponent(iconName)
        guard let destination = destination else {
            Logger.error("Type icons directory is not set")
            return nil
        }

        do {
            // 创建下载任务
            let resource = KF.ImageResource(downloadURL: url, cacheKey: iconName)
            let result = try await KingfisherManager.shared.retrieveImage(with: resource)

            // 保存到磁盘
            if let data = result.image.pngData() {
                try data.write(to: destination)
                Logger.info("Saved type icon to disk: \(iconName)")
            }

            return result.image
        } catch {
            Logger.error("Failed to download type icon: \(error.localizedDescription)")
            return nil
        }
    }

    // 从磁盘加载类型图标
    private func loadTypeIconFromDisk(iconName: String) -> UIImage? {
        guard let typeIconsDirectory = typeIconsDirectory else {
            return nil
        }

        let iconURL = typeIconsDirectory.appendingPathComponent(iconName)
        if let imageData = try? Data(contentsOf: iconURL),
            let image = UIImage(data: imageData)
        {
            return image
        }

        return nil
    }

    // 同步从在线API获取图标
    func loadTypeIconFromAPISync(typeID: Int, size: Int = 64) -> UIImage? {
        let iconName = "icon_\(typeID)_\(size).png"

        // 检查缓存目录中是否已存在
        if let image = loadTypeIconFromDisk(iconName: iconName) {
            return image
        }

        // 构建API URL
        let urlString = "https://images.evetech.net/types/\(typeID)/icon?size=\(size)"
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL: \(urlString)")
            return nil
        }

        // 使用同步方式下载图像
        var resultImage: UIImage?
        let destination = typeIconsDirectory?.appendingPathComponent(iconName)
        guard let destination = destination else {
            Logger.error("Type icons directory is not set")
            return nil
        }

        // 为每次下载创建新的信号量
        let semaphore = DispatchSemaphore(value: 0)

        // 创建同步下载任务
        let downloadTask = URLSession.shared.dataTask(with: url) { data, response, error in
            defer {
                semaphore.signal()
            }

            if let error = error {
                Logger.error("Failed to download type icon: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                Logger.error("Invalid response for type icon download")
                return
            }

            guard let data = data, let image = UIImage(data: data) else {
                Logger.error("Failed to create image from downloaded data")
                return
            }

            // 保存到磁盘
            do {
                try data.write(to: destination)
                Logger.info("Saved type icon to disk: \(iconName)")
                resultImage = image
            } catch {
                Logger.error("Failed to save type icon to disk: \(error.localizedDescription)")
            }
        }

        // 启动下载任务并等待完成
        downloadTask.resume()

        // 设置超时时间为5秒
        let timeout = DispatchTime.now() + .seconds(5)
        if case .timedOut = semaphore.wait(timeout: timeout) {
            Logger.warning("Download timed out for type icon: \(iconName)")
            return UIImage(named: "not_found") ?? UIImage()
        }

        return resultImage ?? UIImage(named: "not_found") ?? UIImage()
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
            return UIImage(named: "not_found") ?? UIImage()
        }

        // 尝试不同的扩展名组合
        let possibleNames = [
            iconName,
            iconName.lowercased(),
            iconName.replacingOccurrences(of: ".png", with: ".PNG"),
        ]

        for name in possibleNames {
            let iconURL = iconsDirectory.appendingPathComponent(name)
            if let imageData = try? Data(contentsOf: iconURL),
                let image = UIImage(data: imageData)
            {
                // 缓存图片
                imageCache.setObject(image, forKey: cacheKey)
                // Logger.info("Load image from disk \(cacheKey).")
                return image
            }
        }

        // 检查是否是类型图标（以"icon_"开头）
        if extractTypeID(from: iconName) != nil,
            let typeIcon = loadTypeIconFromDisk(iconName: iconName)
        {
            // 缓存图片
            imageCache.setObject(typeIcon, forKey: cacheKey)
            return typeIcon
        }

        // 如果是类型图标但未找到，尝试同步加载
        if let typeID = extractTypeID(from: iconName) {
            if let downloadedImage = loadTypeIconFromAPISync(typeID: typeID) {
                // 缓存图片
                imageCache.setObject(downloadedImage, forKey: cacheKey)
                return downloadedImage
            }
        }

        Logger.warning("Failed to load image: \(iconName)")
        return UIImage(named: "not_found") ?? UIImage()
    }

    // 异步加载图标，支持在线获取
    func loadUIImageAsync(for iconName: String) async -> UIImage {
        // 如果缓存中有，直接返回
        let cacheKey = NSString(string: iconName)
        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        // 检查是否是类型图标（以"icon_"开头）
        if let typeID = extractTypeID(from: iconName) {
            // 先尝试从磁盘加载
            if let typeIcon = loadTypeIconFromDisk(iconName: iconName) {
                imageCache.setObject(typeIcon, forKey: cacheKey)
                return typeIcon
            }

            // 如果磁盘没有，从API加载
            if let downloadedImage = await loadTypeIconFromAPI(typeID: typeID) {
                imageCache.setObject(downloadedImage, forKey: cacheKey)
                return downloadedImage
            }
        }

        // 如果不是类型图标或无法从API获取，使用同步方法加载
        return loadUIImage(for: iconName)
    }

    func loadImage(for iconName: String) -> Image {
        // 先尝试从 Assets 加载
        if let uiImage = UIImage(named: iconName.replacingOccurrences(of: ".png", with: "")) {
            return Image(uiImage: uiImage)
        }

        // 如果 Assets 中找不到，从本地文件加载
        return Image(uiImage: loadUIImage(for: iconName))
    }

    // 异步加载SwiftUI Image
    func loadImageAsync(for iconName: String) async -> Image {
        // 先尝试从 Assets 加载
        if let uiImage = UIImage(named: iconName.replacingOccurrences(of: ".png", with: "")) {
            return Image(uiImage: uiImage)
        }

        // 如果 Assets 中找不到，异步加载
        let uiImage = await loadUIImageAsync(for: iconName)
        return Image(uiImage: uiImage)
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

    func clearTypeIconsCache() throws {
        if let typeIconsDirectory = typeIconsDirectory {
            try fileManager.removeItem(at: typeIconsDirectory)
            setupTypeIconsDirectory()
        }
    }

    func unzipIcons(
        from sourceURL: URL, to destinationURL: URL, progress: @escaping (Double) -> Void
    ) async throws {
        Logger.debug("Starting icon extraction from \(sourceURL.path) to \(destinationURL.path)")

        // 重置解压状态
        isExtractionComplete = false

        try? fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        try Zip.unzipFile(sourceURL, destination: destinationURL, overwrite: true, password: nil) {
            progressValue in
            progress(progressValue)
        }

        // 更新内部的 iconsDirectory
        iconsDirectory = destinationURL

        // 验证解压是否成功
        if let contents = try? fileManager.contentsOfDirectory(atPath: destinationURL.path),
            !contents.isEmpty
        {
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
