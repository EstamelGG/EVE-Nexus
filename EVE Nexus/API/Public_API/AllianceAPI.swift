import Foundation
import SwiftUI

/// 联盟信息数据模型
struct AllianceInfo: Codable {
    let name: String
    let ticker: String
    let creator_corporation_id: Int
    let creator_id: Int
    let date_founded: String
    let executor_corporation_id: Int
    let faction_id: Int?
}

@globalActor actor AllianceAPIActor {
    static let shared = AllianceAPIActor()
}

@AllianceAPIActor
class AllianceAPI {
    static let shared = AllianceAPI()

    private init() {
        // 使用 ImageCacheManager，无需初始化配置
    }

    /// 获取联盟图标URL
    private func getLogoURL(allianceId: Int, size: Int = 64) -> URL {
        return URL(string: "https://images.evetech.net/alliances/\(allianceId)/logo?size=\(size)")!
    }

    /// 获取联盟图标
    func fetchAllianceLogo(allianceID: Int, size: Int = 64, forceRefresh: Bool = false) async throws
        -> UIImage
    {
        let logoURL = getLogoURL(allianceId: allianceID, size: size)

        do {
            // 使用 ImageCacheManager
            // backgroundUpdate: true 表示先返回缓存，后台验证ETag并更新
            let image = try await ImageCacheManager.shared.fetchImage(
                from: logoURL,
                forceRefresh: forceRefresh,
                backgroundUpdate: true
            )

            Logger.info("成功获取联盟图标 - 联盟ID: \(allianceID), 大小: \(size)")
            return image

        } catch {
            Logger.error("获取联盟图标失败 - 联盟ID: \(allianceID) - URL: \(logoURL), 错误: \(error)")

            // 尝试获取默认图标
            if let defaultImage = UIImage(named: "not_found") {
                Logger.info("使用默认图标替代 - 联盟ID: \(allianceID)")
                return defaultImage
            }

            throw error
        }
    }

    // MARK: - 文件缓存相关方法

    /// 获取联盟信息缓存目录
    private func getCacheDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheDirectory = documentsPath.appendingPathComponent("AllianceCache")

        // 确保缓存目录存在
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: cacheDirectory, withIntermediateDirectories: true
                )
                Logger.info("创建联盟缓存目录: \(cacheDirectory.path)")
            } catch {
                Logger.error("创建联盟缓存目录失败: \(error)")
            }
        }

        return cacheDirectory
    }

    /// 从文件加载联盟信息
    private func loadAllianceInfoFromFile(filePath: URL) -> AllianceInfo? {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }

        do {
            // 检查文件修改时间，如果超过7天则视为过期
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let daysSinceModification = Date().timeIntervalSince(modificationDate) / (24 * 3600)
                if daysSinceModification > 7 {
                    Logger.info("联盟缓存文件已过期 - 联盟ID: \(filePath.lastPathComponent)")
                    return nil
                } else {
                    let remainingDays = 7 - daysSinceModification
                    Logger.info(
                        "联盟缓存文件有效 - 联盟ID: \(filePath.lastPathComponent), 剩余时间: \(String(format: "%.1f", remainingDays))天"
                    )
                }
            }

            let data = try Data(contentsOf: filePath)
            let info = try JSONDecoder().decode(AllianceInfo.self, from: data)
            Logger.info("成功从文件加载联盟信息 - 文件: \(filePath.lastPathComponent)")
            return info
        } catch {
            Logger.error("加载联盟缓存文件失败: \(error) - 文件: \(filePath.lastPathComponent)")
            return nil
        }
    }

    /// 保存联盟信息到文件
    private func saveAllianceInfoToFile(info: AllianceInfo, filePath: URL) {
        do {
            let data = try JSONEncoder().encode(info)
            try data.write(to: filePath)
            Logger.info(
                "成功保存联盟信息到文件 - 文件: \(filePath.lastPathComponent), 大小: \(data.count) bytes"
            )
        } catch {
            Logger.error(
                "保存联盟信息到文件失败: \(error) - 文件: \(filePath.lastPathComponent)"
            )
        }
    }

    func fetchAllianceInfo(allianceId: Int, forceRefresh: Bool = false) async throws -> AllianceInfo {
        // 创建缓存目录
        let cacheDirectory = getCacheDirectory()
        let cacheFilePath = cacheDirectory.appendingPathComponent("\(allianceId).json")

        // 检查文件缓存
        if !forceRefresh, let cachedInfo = loadAllianceInfoFromFile(filePath: cacheFilePath) {
            Logger.info("使用文件缓存的联盟信息 - 联盟ID: \(allianceId)")
            return cachedInfo
        }

        // 从网络获取数据
        let urlString =
            "https://esi.evetech.net/alliances/\(allianceId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        let info = try JSONDecoder().decode(AllianceInfo.self, from: data)

        // 保存到文件缓存
        saveAllianceInfoToFile(info: info, filePath: cacheFilePath)

        Logger.info("成功获取联盟信息 - 联盟ID: \(allianceId)")
        return info
    }
}
