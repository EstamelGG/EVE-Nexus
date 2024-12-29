import Foundation

// 定义工业项目API错误类型
enum IndustryAPIError: Error {
    case databaseError(String)
    case transactionError(String)
    case dataError(String)
}

class CharacterIndustryAPI {
    static let shared = CharacterIndustryAPI()
    private let databaseManager = CharacterDatabaseManager.shared
    
    // 缓存相关常量
    private let lastIndustryQueryKey = "LastIndustryJobsQuery_"
    private let queryInterval: TimeInterval = 3600 // 1小时的查询间隔
    
    // 获取最后查询时间
    private func getLastQueryTime(characterId: Int) -> Date? {
        let key = lastIndustryQueryKey + String(characterId)
        let lastQuery = UserDefaults.standard.object(forKey: key) as? Date
        
        if let lastQuery = lastQuery {
            let timeInterval = Date().timeIntervalSince(lastQuery)
            let remainingTime = queryInterval - timeInterval
            let remainingMinutes = Int(remainingTime / 60)
            let remainingSeconds = Int(remainingTime.truncatingRemainder(dividingBy: 60))
            
            if remainingTime > 0 {
                Logger.debug("工业项目数据下次刷新剩余时间: \(remainingMinutes)分\(remainingSeconds)秒")
            } else {
                Logger.debug("工业项目数据已过期，需要刷新")
            }
        } else {
            Logger.debug("没有找到工业项目的最后更新时间记录")
        }
        
        return lastQuery
    }
    
    // 更新最后查询时间
    private func updateLastQueryTime(characterId: Int) {
        let key = lastIndustryQueryKey + String(characterId)
        UserDefaults.standard.set(Date(), forKey: key)
    }
    
    // 检查是否需要刷新数据
    private func shouldRefreshData(characterId: Int) -> Bool {
        guard let lastQuery = getLastQueryTime(characterId: characterId) else {
            return true
        }
        return Date().timeIntervalSince(lastQuery) >= queryInterval
    }
    
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
        forceRefresh: Bool = false,
        progressCallback: ((Bool) -> Void)? = nil
    ) async throws -> [IndustryJob] {
        // 如果不是强制刷新，先尝试从数据库加载
        if !forceRefresh {
            let jobs = try await loadJobsFromDB(characterId: characterId)
            if !jobs.isEmpty {
                // 检查是否需要后台刷新
                if !shouldRefreshData(characterId: characterId) {
                    return jobs
                }
                
                // 如果数据过期，启动后台刷新
                Task {
                    progressCallback?(true)
                    do {
                        let newJobs = try await fetchFromNetwork(characterId: characterId)
                        
                        // 获取已存在的工业项目ID
                        let existingJobIds = Set(jobs.map { $0.job_id })
                        
                        // 过滤出新的工业项目
                        let newJobsToSave = newJobs.filter { !existingJobIds.contains($0.job_id) }
                        
                        if !newJobsToSave.isEmpty {
                            try await saveJobsToDB(jobs: newJobsToSave, characterId: characterId)
                            // 发送通知以刷新UI
                            await MainActor.run {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("IndustryJobsUpdated"),
                                    object: nil,
                                    userInfo: ["characterId": characterId]
                                )
                            }
                        }
                        // 更新最后查询时间
                        updateLastQueryTime(characterId: characterId)
                    } catch {
                        Logger.error("后台更新工业项目数据失败: \(error)")
                    }
                    progressCallback?(false)
                }
                return jobs
            }
        }
        
        // 如果需要强制刷新或没有缓存数据
        progressCallback?(true)
        let newJobs = try await fetchFromNetwork(characterId: characterId)
        
        // 如果是强制刷新，也要检查是否有重复数据
        if forceRefresh {
            let existingJobs = try await loadJobsFromDB(characterId: characterId)
            let existingJobIds = Set(existingJobs.map { $0.job_id })
            let newJobsToSave = newJobs.filter { !existingJobIds.contains($0.job_id) }
            
            if !newJobsToSave.isEmpty {
                try await saveJobsToDB(jobs: newJobsToSave, characterId: characterId)
            }
        } else {
            // 如果是首次加载，直接保存所有数据
            try await saveJobsToDB(jobs: newJobs, characterId: characterId)
        }
        
        // 更新最后查询时间
        updateLastQueryTime(characterId: characterId)
        progressCallback?(false)
        return try await loadJobsFromDB(characterId: characterId)
    }
    
    private func loadJobsFromDB(characterId: Int) async throws -> [IndustryJob] {
        let query = """
            SELECT * FROM industry_jobs 
            WHERE character_id = ? 
            ORDER BY start_date DESC
        """
        
        let result = databaseManager.executeQuery(query, parameters: [characterId])
        switch result {
        case .success(let rows):
            Logger.debug("从数据库加载到 \(rows.count) 条工业项目记录")
            var jobs: [IndustryJob] = []
            for row in rows {
                
                // 尝试转换必需字段
                do {
                    let jobId = try getInt(from: row, field: "job_id")
                    let activityId = try getInt(from: row, field: "activity_id")
                    let blueprintId = try getInt64(from: row, field: "blueprint_id")
                    let blueprintLocationId = try getInt64(from: row, field: "blueprint_location_id")
                    let blueprintTypeId = try getInt(from: row, field: "blueprint_type_id")
                    let cost = try getDouble(from: row, field: "cost")
                    let duration = try getInt(from: row, field: "duration")
                    let facilityId = try getInt64(from: row, field: "facility_id")
                    let installerId = try getInt(from: row, field: "installer_id")
                    let outputLocationId = try getInt64(from: row, field: "output_location_id")
                    let runs = try getInt(from: row, field: "runs")
                    let stationId = try getInt64(from: row, field: "station_id")
                    let status = try getString(from: row, field: "status")
                    let startDateStr = try getString(from: row, field: "start_date")
                    let endDateStr = try getString(from: row, field: "end_date")
                    
                    let dateFormatter = ISO8601DateFormatter()
                    guard let startDate = dateFormatter.date(from: startDateStr),
                          let endDate = dateFormatter.date(from: endDateStr) else {
                        Logger.error("日期格式转换失败: start_date=\(startDateStr), end_date=\(endDateStr)")
                        throw IndustryAPIError.dataError("日期格式转换失败")
                    }
                    
                    // 处理可选字段
                    let completedCharacterId = getOptionalInt(from: row, field: "completed_character_id")
                    let completedDate = (row["completed_date"] as? String).flatMap { dateFormatter.date(from: $0) }
                    let licensedRuns = getOptionalInt(from: row, field: "licensed_runs")
                    let pauseDate = (row["pause_date"] as? String).flatMap { dateFormatter.date(from: $0) }
                    let probability = getOptionalFloat(from: row, field: "probability")
                    let productTypeId = getOptionalInt(from: row, field: "product_type_id")
                    let successfulRuns = getOptionalInt(from: row, field: "successful_runs")
                    
                    let job = IndustryJob(
                        activity_id: activityId,
                        blueprint_id: blueprintId,
                        blueprint_location_id: blueprintLocationId,
                        blueprint_type_id: blueprintTypeId,
                        completed_character_id: completedCharacterId,
                        completed_date: completedDate,
                        cost: cost,
                        duration: duration,
                        end_date: endDate,
                        facility_id: facilityId,
                        installer_id: installerId,
                        job_id: jobId,
                        licensed_runs: licensedRuns,
                        output_location_id: outputLocationId,
                        pause_date: pauseDate,
                        probability: probability,
                        product_type_id: productTypeId,
                        runs: runs,
                        start_date: startDate,
                        station_id: stationId,
                        status: status,
                        successful_runs: successfulRuns
                    )
                    jobs.append(job)
                } catch {
                    Logger.error("工业项目数据转换失败: \(error)")
                    // 继续处理下一条记录
                    continue
                }
            }
            return jobs
            
        case .error(let error):
            Logger.error("从数据库加载工业项目失败: \(error)")
            throw IndustryAPIError.databaseError("从数据库加载工业项目失败: \(error)")
        }
    }
    
    // 辅助方法：安全地获取整数值
    private func getInt(from row: [String: Any], field: String) throws -> Int {
        if let value = row[field] as? Int {
            return value
        }
        if let value = row[field] as? Int64 {
            return Int(value)
        }
        Logger.error("字段[\(field)]类型转换失败: \(String(describing: row[field]))")
        throw IndustryAPIError.dataError("字段[\(field)]类型转换失败")
    }
    
    // 辅助方法：安全地获取 Int64 值
    private func getInt64(from row: [String: Any], field: String) throws -> Int64 {
        if let value = row[field] as? Int64 {
            return value
        }
        if let value = row[field] as? Int {
            return Int64(value)
        }
        Logger.error("字段[\(field)]类型转换失败: \(String(describing: row[field]))")
        throw IndustryAPIError.dataError("字段[\(field)]类型转换失败")
    }
    
    // 辅助方法：安全地获取浮点值
    private func getDouble(from row: [String: Any], field: String) throws -> Double {
        if let value = row[field] as? Double {
            return value
        }
        if let value = row[field] as? Int {
            return Double(value)
        }
        if let value = row[field] as? Int64 {
            return Double(value)
        }
        Logger.error("字段[\(field)]类型转换失败: \(String(describing: row[field]))")
        throw IndustryAPIError.dataError("字段[\(field)]类型转换失败")
    }
    
    // 辅助方法：安全地获取字符串值
    private func getString(from row: [String: Any], field: String) throws -> String {
        if let value = row[field] as? String {
            return value
        }
        Logger.error("字段[\(field)]类型转换失败: \(String(describing: row[field]))")
        throw IndustryAPIError.dataError("字段[\(field)]类型转换失败")
    }
    
    // 辅助方法：安全地获取可选整数值
    private func getOptionalInt(from row: [String: Any], field: String) -> Int? {
        if let value = row[field] as? Int {
            return value
        }
        if let value = row[field] as? Int64 {
            return Int(value)
        }
        return nil
    }
    
    // 辅助方法：安全地获取可选浮点值
    private func getOptionalFloat(from row: [String: Any], field: String) -> Float? {
        if let value = row[field] as? Float {
            return value
        }
        if let value = row[field] as? Double {
            return Float(value)
        }
        return nil
    }
    
    private func saveJobsToDB(jobs: [IndustryJob], characterId: Int) async throws {
        let dateFormatter = ISO8601DateFormatter()
        
        // 开始一个事务
        if case .error(let error) = databaseManager.executeQuery("BEGIN TRANSACTION") {
            throw IndustryAPIError.transactionError("开始事务失败: \(error)")
        }
        
        do {
            // 获取已存在的工业项目ID
            let checkQuery = "SELECT job_id FROM industry_jobs WHERE character_id = ?"
            let existingResult = databaseManager.executeQuery(checkQuery, parameters: [characterId])
            var existingJobIds = Set<Int>()
            if case .success(let rows) = existingResult {
                existingJobIds = Set(rows.compactMap { $0["job_id"] as? Int })
            }
            
            // 插入新数据
            let insertQuery = """
                INSERT INTO industry_jobs (
                    character_id, job_id, activity_id, blueprint_id, blueprint_location_id,
                    blueprint_type_id, completed_character_id, completed_date, cost, duration,
                    end_date, facility_id, installer_id, licensed_runs, output_location_id,
                    pause_date, probability, product_type_id, runs, start_date,
                    station_id, status, successful_runs, last_updated
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            """
            
            var insertedCount = 0
            for job in jobs {
                // 如果工业项目已存在，跳过
                if existingJobIds.contains(job.job_id) {
                    Logger.debug("跳过已存在的工业项目: characterId=\(characterId), jobId=\(job.job_id)")
                    continue
                }
                
                // 处理可选类型，将 nil 转换为 NSNull()
                let completedCharacterId = job.completed_character_id.map { $0 as Any } ?? NSNull()
                let completedDate = job.completed_date.map { dateFormatter.string(from: $0) as Any } ?? NSNull()
                let licensedRuns = job.licensed_runs.map { $0 as Any } ?? NSNull()
                let pauseDate = job.pause_date.map { dateFormatter.string(from: $0) as Any } ?? NSNull()
                let probability = job.probability.map { Double($0) as Any } ?? NSNull()
                let productTypeId = job.product_type_id.map { $0 as Any } ?? NSNull()
                let successfulRuns = job.successful_runs.map { $0 as Any } ?? NSNull()
                
                let parameters: [Any] = [
                    characterId,
                    job.job_id,
                    job.activity_id,
                    job.blueprint_id,
                    job.blueprint_location_id,
                    job.blueprint_type_id,
                    completedCharacterId,
                    completedDate,
                    job.cost,
                    job.duration,
                    dateFormatter.string(from: job.end_date),
                    job.facility_id,
                    job.installer_id,
                    licensedRuns,
                    job.output_location_id,
                    pauseDate,
                    probability,
                    productTypeId,
                    job.runs,
                    dateFormatter.string(from: job.start_date),
                    job.station_id,
                    job.status,
                    successfulRuns
                ]
                
                Logger.debug("正在插入新的工业项目数据: characterId=\(characterId), jobId=\(job.job_id)")
                if case .error(let error) = databaseManager.executeQuery(insertQuery, parameters: parameters) {
                    Logger.error("插入数据失败: characterId=\(characterId), jobId=\(job.job_id), error=\(error)")
                    throw IndustryAPIError.databaseError("插入数据失败: \(error)")
                }
                insertedCount += 1
            }
            
            // 提交事务
            if case .error(let error) = databaseManager.executeQuery("COMMIT") {
                throw IndustryAPIError.transactionError("提交事务失败: \(error)")
            }
            
            Logger.debug("成功保存工业项目数据: characterId=\(characterId), 新增数量=\(insertedCount)")
        } catch {
            // 如果发生任何错误，回滚事务
            _ = databaseManager.executeQuery("ROLLBACK")
            Logger.error("保存工业项目数据失败，已回滚: \(error)")
            throw error
        }
    }
    
    private func fetchFromNetwork(characterId: Int) async throws -> [IndustryJob] {
        let url = URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/industry/jobs/?datasource=tranquility&include_completed=true")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(from: url, characterId: characterId)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([IndustryJob].self, from: data)
    }
    
    // 清除所有缓存
    func clearAllCache() {
        // 只清除 UserDefaults 中的查询时间记录
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(lastIndustryQueryKey) {
                defaults.removeObject(forKey: key)
            }
        }
        
        Logger.debug("清除工业项目查询时间记录")
    }
} 
