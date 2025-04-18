import Foundation
import Kingfisher
import SwiftUI

// 角色公开信息数据模型
struct CharacterPublicInfo: Codable {
    let alliance_id: Int?
    let birthday: String
    let bloodline_id: Int
    let corporation_id: Int
    let faction_id: Int?
    let gender: String
    let name: String
    let race_id: Int
    let security_status: Double?
    let title: String?

    // 添加CodingKeys来忽略API返回的description字段
    private enum CodingKeys: String, CodingKey {
        case alliance_id
        case birthday
        case bloodline_id
        case corporation_id
        case faction_id
        case gender
        case name
        case race_id
        case security_status
        case title
    }
}

// 角色雇佣历史记录数据模型
struct CharacterEmploymentHistory: Codable {
    let corporation_id: Int
    let record_id: Int
    let start_date: String
}

final class CharacterAPI: @unchecked Sendable {
    static let shared = CharacterAPI()
    private init() {
        // 配置 Kingfisher 的全局设置
        let cache = ImageCache.default
        cache.memoryStorage.config.totalCostLimit = 300 * 1024 * 1024  // 300MB
        cache.diskStorage.config.sizeLimit = 1000 * 1024 * 1024  // 1GB
        cache.diskStorage.config.expiration = .days(7)  // 7天过期

        // 配置下载器
        let downloader = ImageDownloader.default
        downloader.downloadTimeout = 15.0  // 15秒超时
    }

    // 保存角色信息到数据库
    private func saveCharacterInfoToCache(_ info: CharacterPublicInfo, characterId: Int) -> Bool {
        let query = """
                INSERT OR REPLACE INTO character_info (
                    character_id, alliance_id, birthday, bloodline_id, corporation_id,
                    faction_id, gender, name, race_id, security_status, title,
                    last_updated
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            """

        let parameters: [Any] = [
            characterId,
            info.alliance_id as Any? ?? NSNull(),
            info.birthday,
            info.bloodline_id,
            info.corporation_id,
            info.faction_id as Any? ?? NSNull(),
            info.gender,
            info.name,
            info.race_id,
            info.security_status as Any? ?? NSNull(),
            info.title as Any? ?? NSNull(),
        ]

        // 字段名称数组，与参数数组顺序对应
        let fieldNames = [
            "character_id",
            "alliance_id",
            "birthday",
            "bloodline_id",
            "corporation_id",
            "faction_id",
            "gender",
            "name",
            "race_id",
            "security_status",
            "title",
        ]

        if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: parameters
        ) {
            Logger.error("保存角色信息失败: \(error)")
            // 打印每个参数的字段名、值和类型
            for (index, value) in parameters.enumerated() {
                Logger.error("字段 '\(fieldNames[index])': 值 = \(value), 类型 = \(type(of: value))")
            }
            return false
        }

        Logger.debug("成功保存角色信息到数据库 - 角色ID: \(characterId)")
        return true
    }

    // 从数据库读取角色信息
    private func loadCharacterInfoFromCache(characterId: Int) -> CharacterPublicInfo? {
        let query = """
                SELECT * FROM character_info 
                WHERE character_id = ? 
                AND datetime(last_updated) > datetime('now', '-1 hour')
            """

        if case let .success(rows) = CharacterDatabaseManager.shared.executeQuery(
            query, parameters: [characterId]
        ),
            let row = rows.first
        {
            // 安全地处理数值类型转换
            guard let bloodlineId = (row["bloodline_id"] as? Int64).map({ Int($0) }),
                let corporationId = (row["corporation_id"] as? Int64).map({ Int($0) }),
                let raceId = (row["race_id"] as? Int64).map({ Int($0) }),
                let gender = row["gender"] as? String,
                let name = row["name"] as? String,
                let birthday = row["birthday"] as? String
            else {
                Logger.error("从数据库加载角色信息失败 - 必需字段类型转换失败")
                return nil
            }

            // 处理可选字段
            let allianceId = (row["alliance_id"] as? Int64).map { Int($0) }
            let factionId = (row["faction_id"] as? Int64).map { Int($0) }
            let securityStatus = row["security_status"] as? Double
            let title = row["title"] as? String

            return CharacterPublicInfo(
                alliance_id: allianceId,
                birthday: birthday,
                bloodline_id: bloodlineId,
                corporation_id: corporationId,
                faction_id: factionId,
                gender: gender,
                name: name,
                race_id: raceId,
                security_status: securityStatus,
                title: title
            )
        }
        return nil
    }

    // 获取角色公开信息
    func fetchCharacterPublicInfo(characterId: Int, forceRefresh: Bool = false) async throws
        -> CharacterPublicInfo
    {
        // 如果不是强制刷新，先尝试从数据库加载
        if !forceRefresh {
            if let cachedInfo = loadCharacterInfoFromCache(characterId: characterId) {
                Logger.info("使用缓存的角色信息 - 角色ID: \(characterId)")
                return cachedInfo
            }
        }

        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        var info = try JSONDecoder().decode(CharacterPublicInfo.self, from: data)

        // 获取最新的联盟和公司信息
        do {
            let affiliations = try await CharacterAffiliationAPI.shared.fetchAffiliations(
                characterIds: [characterId])
            if let affiliation = affiliations.first {
                // 更新联盟和公司信息
                info = CharacterPublicInfo(
                    alliance_id: affiliation.alliance_id,
                    birthday: info.birthday,
                    bloodline_id: info.bloodline_id,
                    corporation_id: affiliation.corporation_id,
                    faction_id: info.faction_id,
                    gender: info.gender,
                    name: info.name,
                    race_id: info.race_id,
                    security_status: info.security_status,
                    title: info.title
                )
            }
        } catch {
            Logger.error("获取角色关联信息失败: \(error)")
            // 即使获取关联信息失败，我们仍然使用原始信息
        }

        // 保存到数据库
        if saveCharacterInfoToCache(info, characterId: characterId) {
            Logger.info("成功缓存角色信息 - 角色ID: \(characterId)")
        }

        return info
    }

    // 获取角色头像URL
    private func getPortraitURL(characterId: Int, size: Int) -> URL {
        return URL(
            string: "https://images.evetech.net/characters/\(characterId)/portrait?size=\(size)")!
    }

    // 获取角色头像
    func fetchCharacterPortrait(
        characterId: Int, size: Int = 128, forceRefresh: Bool = false, catchImage: Bool = true
    ) async throws -> UIImage {
        let portraitURL = getPortraitURL(characterId: characterId, size: size)
        let cacheKey = "character_portrait_\(characterId)_\(size)"

        // 1. 首先尝试从 UserDefaults 读取
        if !forceRefresh, let cachedData = UserDefaults.standard.data(forKey: cacheKey),
            let cachedImage = UIImage(data: cachedData)
        {
            Logger.info(
                "从 UserDefaults 加载角色头像成功 - 角色ID: \(characterId), 数据大小: \(cachedData.count) bytes")
            return cachedImage
        }

        var options: KingfisherOptionsInfo = [
            .cacheOriginalImage,
            .diskCacheExpiration(.days(30)),  // 磁盘缓存30天
            .memoryCacheExpiration(.days(7)),  // 内存缓存7天
        ]

        // 如果需要强制刷新，添加相应的选项
        if forceRefresh {
            options.append(.forceRefresh)
            options.append(.fromMemoryCacheOrRefresh)
        }

        return try await withCheckedThrowingContinuation { continuation in
            _ = DispatchQueue(label: "com.eve-nexus.portrait-download")
            let taskLock = NSLock()
            var downloadTask: DownloadTask?

            let setTask: (DownloadTask?) -> Void = { task in
                taskLock.lock()
                downloadTask = task
                taskLock.unlock()
            }

            let getAndCancelTask: () -> Void = {
                taskLock.lock()
                downloadTask?.cancel()
                downloadTask = nil
                taskLock.unlock()
            }

            let task = KingfisherManager.shared.retrieveImage(with: portraitURL, options: options) {
                result in
                switch result {
                case let .success(imageResult):
                    // 保存到 UserDefaults
                    if let imageData = imageResult.image.jpegData(compressionQuality: 0.8) {
                        if catchImage {
                            UserDefaults.standard.set(imageData, forKey: cacheKey)
                            Logger.info(
                                "成功获取并缓存角色头像 - 角色ID: \(characterId), 大小: \(size), 数据大小: \(imageData.count) bytes"
                            )
                        } else {
                            Logger.info(
                                "成功获取角色头像 - 角色ID: \(characterId), 大小: \(size), 数据大小: \(imageData.count) bytes"
                            )
                        }
                    }
                    setTask(nil)
                    continuation.resume(returning: imageResult.image)
                case let .failure(error):
                    Logger.error("获取角色头像失败 - 角色ID: \(characterId), 错误: \(error)")
                    setTask(nil)
                    continuation.resume(throwing: NetworkError.invalidImageData)
                }
            }

            setTask(task)

            // 设置任务取消处理
            Task {
                try? await Task.sleep(nanoseconds: 1)  // 给予足够的时间让任务开始
                if Task.isCancelled {
                    getAndCancelTask()
                    continuation.resume(throwing: CancellationError())
                }
            }
        }
    }

    // 获取角色雇佣历史
    func fetchEmploymentHistory(characterId: Int) async throws -> [CharacterEmploymentHistory] {
        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/corporationhistory/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        let history = try JSONDecoder().decode([CharacterEmploymentHistory].self, from: data)

        // 按开始日期降序排序（最新的在前）
        return history.sorted { $0.start_date > $1.start_date }
    }
}
