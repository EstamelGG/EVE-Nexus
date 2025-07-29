import Foundation

/// 静态资源管理器（用于管理图片资源的本地缓存）
class StaticResourceManager {
    static let shared = StaticResourceManager()
    private let fileManager = FileManager.default

    private init() {}

    /// 获取静态资源目录路径
    func getStaticDataSetPath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let staticPath = paths[0].appendingPathComponent("StaticDataSet")

        if !FileManager.default.fileExists(atPath: staticPath.path) {
            try? FileManager.default.createDirectory(
                at: staticPath, withIntermediateDirectories: true
            )
        }

        return staticPath
    }

    /// 清理所有静态资源数据
    func clearAllStaticData() throws {
        let staticDataSetPath = getStaticDataSetPath()
        if fileManager.fileExists(atPath: staticDataSetPath.path) {
            try fileManager.removeItem(at: staticDataSetPath)

            // 重新创建必要的目录
            try fileManager.createDirectory(
                at: staticDataSetPath, withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: getCharacterPortraitsPath(), withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: getNetRendersPath(), withIntermediateDirectories: true
            )
        }

        Logger.info("Cleared all static data")
    }

    /// 获取渲染图目录路径
    func getNetRendersPath() -> URL {
        let renderPath = getStaticDataSetPath().appendingPathComponent("NetRenders")
        if !fileManager.fileExists(atPath: renderPath.path) {
            try? fileManager.createDirectory(at: renderPath, withIntermediateDirectories: true)
        }
        return renderPath
    }

    // MARK: - 角色头像管理

    /// 获取角色头像目录路径
    func getCharacterPortraitsPath() -> URL {
        let portraitsPath = getStaticDataSetPath().appendingPathComponent("CharacterPortraits")
        if !fileManager.fileExists(atPath: portraitsPath.path) {
            try? fileManager.createDirectory(at: portraitsPath, withIntermediateDirectories: true)
        }
        return portraitsPath
    }
}
