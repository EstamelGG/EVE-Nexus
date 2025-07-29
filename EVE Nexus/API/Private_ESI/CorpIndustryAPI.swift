import Foundation

// 缓存数据结构
private struct CorpIndustryJobsCacheData: Codable {
    let data: [CorpIndustryAPI.CorpIndustryJob]
    let timestamp: Date

    var isExpired: Bool {
        // 设置缓存有效期为1小时
        return Date().timeIntervalSince(timestamp) > 3600
    }
}

class CorpIndustryAPI {
    static let shared = CorpIndustryAPI()
    private let databaseManager = CharacterDatabaseManager.shared

    // 军团工业项目信息模型
    struct CorpIndustryJob: Codable, Identifiable, Hashable {
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
        let location_id: Int64  // 军团接口特有字段
        let output_location_id: Int64
        let pause_date: Date?
        let probability: Float?
        let product_type_id: Int?
        let runs: Int
        let start_date: Date
        let status: String
        let successful_runs: Int?

        var id: Int { job_id }

        // 实现 Hashable
        func hash(into hasher: inout Hasher) {
            hasher.combine(job_id)
        }

        static func == (lhs: CorpIndustryJob, rhs: CorpIndustryJob) -> Bool {
            return lhs.job_id == rhs.job_id
        }
    }

    private init() {}

    func fetchCorpIndustryJobs(
        characterId: Int,
        forceRefresh: Bool = false,
        includeCompleted: Bool = true,
        progressCallback: ((Int, Int) -> Void)? = nil
    ) async throws -> [CorpIndustryJob] {
        // 1. 获取角色的军团ID
        guard
            let corporationId = try await databaseManager.getCharacterCorporationId(
                characterId: characterId)
        else {
            throw NetworkError.authenticationError("无法获取军团ID")
        }

        // 2. 如果不是强制刷新，先尝试从文件缓存加载未过期数据
        if !forceRefresh {
            if let cachedJobs = loadJobsFromCache(corporationId: corporationId) {
                Logger.info("使用缓存的军团工业项目数据 - 军团ID: \(corporationId)")
                return cachedJobs
            }
        }

        // 3. 从网络获取最新数据
        return try await fetchJobsFromServer(corporationId: corporationId, characterId: characterId, includeCompleted: includeCompleted, progressCallback: progressCallback)
    }

    private func fetchJobsFromServer(corporationId: Int, characterId: Int, includeCompleted: Bool, progressCallback: ((Int, Int) -> Void)? = nil) async throws -> [CorpIndustryJob] {
        Logger.info("开始获取军团工业项目信息 - 军团ID: \(corporationId)")

        let baseUrlString = "https://esi.evetech.net/corporations/\(corporationId)/industry/jobs/?datasource=tranquility&include_completed=\(includeCompleted)"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        let allJobs = try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 3,
            decoder: { data in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode([CorpIndustryJob].self, from: data)
            },
            progressCallback: { currentPage, totalPages in
                Logger.debug("正在获取第 \(currentPage)/\(totalPages) 页军团工业项目数据")
                progressCallback?(currentPage, totalPages)
            }
        )

        Logger.info("成功获取所有军团工业项目信息 - 军团ID: \(corporationId), 总条数: \(allJobs.count)")
        
        // 保存到文件缓存
        saveJobsToCache(allJobs, corporationId: corporationId)
        
        return allJobs
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

    private func getCacheFilePath(corporationId: Int) -> URL? {
        guard let cacheDirectory = getCacheDirectory() else { return nil }
        return cacheDirectory.appendingPathComponent("corp_\(corporationId).json")
    }

    private func loadJobsFromCache(corporationId: Int) -> [CorpIndustryJob]? {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else {
            Logger.error("获取缓存文件路径失败 - 军团ID: \(corporationId)")
            return nil
        }

        Logger.info("尝试从缓存文件读取军团工业项目数据 - 路径: \(cacheFile.path)")

        do {
            guard FileManager.default.fileExists(atPath: cacheFile.path) else {
                Logger.info("缓存文件不存在 - 军团ID: \(corporationId), 路径: \(cacheFile.path)")
                return nil
            }

            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cached = try decoder.decode(CorpIndustryJobsCacheData.self, from: data)

            if cached.isExpired {
                Logger.info("缓存已过期 - 军团ID: \(corporationId), 路径: \(cacheFile.path)")
                try? FileManager.default.removeItem(at: cacheFile)
                return nil
            }

            Logger.info("成功从缓存加载军团工业项目信息 - 军团ID: \(corporationId), 路径: \(cacheFile.path), 数据条数: \(cached.data.count)")
            return cached.data
        } catch {
            Logger.error("读取缓存文件失败 - 军团ID: \(corporationId), 路径: \(cacheFile.path), 错误: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
            return nil
        }
    }

    private func saveJobsToCache(_ jobs: [CorpIndustryJob], corporationId: Int) {
        guard let cacheFile = getCacheFilePath(corporationId: corporationId) else {
            Logger.error("获取缓存文件路径失败 - 军团ID: \(corporationId)")
            return
        }

        do {
            let cachedData = CorpIndustryJobsCacheData(data: jobs, timestamp: Date())
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encodedData = try encoder.encode(cachedData)
            try encodedData.write(to: cacheFile)
            Logger.info("军团工业项目信息已缓存到文件 - 军团ID: \(corporationId), 路径: \(cacheFile.path), 数据条数: \(jobs.count)")
        } catch {
            Logger.error("保存军团工业项目信息缓存失败 - 军团ID: \(corporationId), 路径: \(cacheFile.path), 错误: \(error)")
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }
} 
