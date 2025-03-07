import Foundation
import UIKit

@NetworkManagerActor
class UniverseIconAPI {
    static let shared = UniverseIconAPI()
    private let networkManager = NetworkManager.shared

    private init() {}

    /// 获取实体的图标
    /// - Parameters:
    ///   - id: 实体ID
    ///   - category: 实体类型（character/corporation/alliance）
    ///   - forceRefresh: 是否强制从网络获取
    /// - Returns: 图标图片
    func fetchIcon(id: Int, category: String, forceRefresh: Bool = false) async throws -> UIImage {
        // 构建本地文件路径
        let fileName = "\(category)_\(id).png"
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let iconDirectory = documentsPath.appendingPathComponent("StaticDataSet/Universe_icon")
        let filePath = iconDirectory.appendingPathComponent(fileName)

        // 确保目录存在
        try? fileManager.createDirectory(at: iconDirectory, withIntermediateDirectories: true)

        // 如果不是强制刷新且文件存在，则从文件系统读取
        if !forceRefresh && fileManager.fileExists(atPath: filePath.path) {
            if let data = try? Data(contentsOf: filePath),
                let image = UIImage(data: data)
            {
                Logger.debug("从文件系统加载图标 - 类型: \(category), ID: \(id)")
                return image
            }
        }

        // 构建API URL
        var urlString: String
        switch category.lowercased() {
        case "character":
            urlString = "https://images.evetech.net/characters/\(id)/portrait?size=64"
        case "corporation":
            urlString = "https://images.evetech.net/corporations/\(id)/logo?size=64"
        case "alliance":
            urlString = "https://images.evetech.net/alliances/\(id)/logo?size=64"
        default:
            throw NetworkError.invalidURL
        }

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 从网络获取图标
        Logger.info("从网络获取图标 - 类型: \(category), ID: \(id)")
        let data = try await networkManager.fetchData(from: url)

        guard let image = UIImage(data: data) else {
            throw NetworkError.invalidImageData
        }

        // 保存到文件系统
        if let pngData = image.pngData() {
            try? pngData.write(to: filePath)
            Logger.debug("保存图标到文件系统 - 路径: \(filePath.path)")
        }

        return image
    }

    /// 清理图标缓存
    func clearIconCache() {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let iconDirectory = documentsPath.appendingPathComponent("StaticDataSet/Universe_icon")

        try? fileManager.removeItem(at: iconDirectory)
        try? fileManager.createDirectory(at: iconDirectory, withIntermediateDirectories: true)

        Logger.info("清理图标缓存完成")
    }
}
