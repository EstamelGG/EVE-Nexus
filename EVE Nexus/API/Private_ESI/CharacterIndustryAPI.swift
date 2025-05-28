import Foundation

// 定义工业项目API错误类型
enum IndustryAPIError: Error {
    case databaseError(String)
    case dataError(String)
    case jsonError(String)
}

class CharacterIndustryAPI {
    static let shared = CharacterIndustryAPI()
    private let databaseManager = CharacterDatabaseManager.shared

    // 工业项目信息模型
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

        var id: Int { job_id }

        // 实现 Hashable
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
        forceRefresh: Bool = false
    ) async throws -> [IndustryJob] {
        // 如果不是强制刷新，先尝试从数据库加载未过期数据
        if !forceRefresh {
            if let cachedJobs = loadJobsFromDatabase(characterId: characterId) {
                Logger.info("使用缓存的工业项目数据 - 角色ID: \(characterId)")
                return cachedJobs
            }
        }

        // 从网络获取最新数据
        let url = URL(
            string:
                "https://esi.evetech.net/latest/characters/\(characterId)/industry/jobs/?datasource=tranquility&include_completed=true"
        )!

        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url, characterId: characterId
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let jobs = try decoder.decode([IndustryJob].self, from: data)

        Logger.debug("从 API 获取到 \(jobs.count) 个工业项目")
        
        // 保存到数据库
        if saveJobsToDatabase(characterId: characterId, jobs: jobs) {
            Logger.info("成功缓存工业项目数据 - 角色ID: \(characterId), 数量: \(jobs.count)")
        }
        
        return jobs
    }

    // 从数据库加载工业项目数据（仅加载1小时内有效的数据）
    private func loadJobsFromDatabase(characterId: Int) -> [IndustryJob]? {
        let query = """
            SELECT jobs_data FROM industry_jobs_data 
            WHERE character_id = ? 
            AND datetime(last_updated) > datetime('now', '-1 hour')
            LIMIT 1
        """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [characterId]),
           rows.count > 0,
           let row = rows.first,
           let jsonString = row["jobs_data"] as? String,
           let jsonData = jsonString.data(using: .utf8)
        {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let jobs = try decoder.decode([IndustryJob].self, from: jsonData)
                Logger.debug("成功从数据库加载工业项目数据 - 角色ID: \(characterId), 数量: \(jobs.count)")
                return jobs
            } catch {
                Logger.error("解析工业项目数据失败: \(error)")
                return nil
            }
        }
        return nil
    }

    // 保存工业项目数据到数据库
    private func saveJobsToDatabase(characterId: Int, jobs: [IndustryJob]) -> Bool {
        do {
            // 转换为JSON字符串
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(jobs)
            
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                Logger.error("工业项目数据JSON编码失败")
                return false
            }
            
            // 使用INSERT OR REPLACE语句
            let query = """
                INSERT OR REPLACE INTO industry_jobs_data 
                (character_id, jobs_data, last_updated) 
                VALUES (?, ?, datetime('now'))
            """
            
            if case let .error(error) = databaseManager.executeQuery(query, parameters: [characterId, jsonString]) {
                Logger.error("保存工业项目数据失败: \(error)")
                return false
            }
            
            return true
        } catch {
            Logger.error("保存工业项目数据失败: \(error)")
            return false
        }
    }
}
