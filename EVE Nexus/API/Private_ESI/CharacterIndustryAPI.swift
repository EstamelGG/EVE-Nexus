import Foundation

class CharacterIndustryAPI {
    static let shared = CharacterIndustryAPI()

    /// 缓存过期时间（1小时）
    private let cacheExpirationInterval: TimeInterval = 3600

    /// 工业项目信息模型
    struct IndustryJob: Codable, Identifiable, Hashable {
        let activity_id: Int
        let blueprint_id: Int64
        let blueprint_location_id: Int64
        let blueprint_type_id: Int
        let completed_character_id: Int?
        let completed_date: Date?
        let cost: Double
        let duration: Int
        let end_date: Date
        let facility_id: Int64
        let installer_id: Int
        let job_id: Int
        let licensed_runs: Int?
        let output_location_id: Int64
        let pause_date: Date?
        let probability: Float?
        let product_type_id: Int?
        let runs: Int
        let start_date: Date
        let station_id: Int64
        let status: String
        let successful_runs: Int?

        var id: Int {
            job_id
        }

        /// 实现 Hashable
        func hash(into hasher: inout Hasher) {
            hasher.combine(job_id)
        }

        static func == (lhs: IndustryJob, rhs: IndustryJob) -> Bool {
            return lhs.job_id == rhs.job_id
        }
    }

    private init() {}

    func fetchIndustryJobs(
        characterId: Int,
        forceRefresh: Bool = false,
        includeCompleted: Bool = true
    ) async throws -> [IndustryJob] {
        // 如果不是强制刷新，先尝试从文件缓存加载未过期数据
        if !forceRefresh {
            if let cachedJobs = loadJobsFromCache(characterId: characterId) {
                Logger.info("使用缓存的工业项目数据 - 角色ID: \(characterId)")
                return cachedJobs
            }
        }

        // 从网络获取最新数据
        let url = URL(
            string:
            "https://esi.evetech.net/characters/\(characterId)/industry/jobs/?datasource=tranquility&include_completed=\(includeCompleted)"
        )!

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url, characterId: characterId
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let jobs = try decoder.decode([IndustryJob].self, from: data)

        Logger.debug("从 API 获取到 \(jobs.count) 个工业项目")

        // 保存到文件缓存
        saveJobsToCache(jobs, characterId: characterId)

        return jobs
    }

    // MARK: - Cache Methods

    private func getCacheDirectory() -> URL? {
        guard
            let documentsDirectory = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first
        else {
            return nil
        }
        let cacheDirectory = documentsDirectory.appendingPathComponent(
            "IndustryJobs", isDirectory: true
        )

        // 确保缓存目录存在
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true, attributes: nil
        )

        return cacheDirectory
    }

    private func getCacheFilePath(characterId: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("char_\(characterId).json")
    }

    private func loadJobsFromCache(characterId: Int) -> [IndustryJob]? {
        guard let cacheFile = getCacheFilePath(characterId: characterId) else {
            Logger.error("获取缓存文件路径失败 - 角色ID: \(characterId)")
            return nil
        }

        Logger.info("尝试从缓存文件读取工业项目数据 - 路径: \(cacheFile.path)")

        do {
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                Logger.info("缓存文件不存在 - 角色ID: \(characterId), 路径: \(cacheFile.path)")
                return nil
            }

            // 检查文件修改时间是否过期
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: cacheFile.path)
            if let modificationDate = fileAttributes[.modificationDate] as? Date {
                let timeSinceModification = Date().timeIntervalSince(modificationDate)
                if timeSinceModification > cacheExpirationInterval {
                    Logger.info(
                        "缓存文件已过期 - 角色ID: \(characterId), 路径: \(cacheFile.path), 修改时间: \(modificationDate)"
                    )
                    try? FileManager.default.removeItem(at: cacheFile)
                    return nil
                }
            }

            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let jobs = try decoder.decode([IndustryJob].self, from: data)

            Logger.info(
                "成功从缓存加载工业项目信息 - 角色ID: \(characterId), 路径: \(cacheFile.path), 数据条数: \(jobs.count)"
            )
            return jobs
        } catch {
            Logger.error("读取缓存文件失败 - 角色ID: \(characterId), 路径: \(cacheFile.path), 错误: \(error)")
            // 删除损坏的缓存文件
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }

    private func saveJobsToCache(_ jobs: [IndustryJob], characterId: Int) {
        guard let cacheFile = getCacheFilePath(characterId: characterId) else {
            Logger.error("获取缓存文件路径失败 - 角色ID: \(characterId)")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encodedData = try encoder.encode(jobs)
            try encodedData.write(to: cacheFile)
            Logger.info(
                "工业项目信息已缓存到文件 - 角色ID: \(characterId), 路径: \(cacheFile.path), 数据条数: \(jobs.count)"
            )
        } catch {
            Logger.error("保存工业项目信息缓存失败 - 角色ID: \(characterId), 路径: \(cacheFile.path), 错误: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }
}
