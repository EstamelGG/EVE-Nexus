import Foundation

// 定义工业项目API错误类型
enum IndustryAPIError: Error {
    case databaseError(String)
    case dataError(String)
}

class CharacterIndustryAPI {
    static let shared = CharacterIndustryAPI()
    private let databaseManager = CharacterDatabaseManager.shared

    // 缓存相关常量
    private let lastIndustryQueryKey = "LastIndustryJobsQuery_"
    private let queryInterval: TimeInterval = 3600  // 1小时的查询间隔

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
                        let existingJobs = try await loadJobsFromDB(characterId: characterId)
                        let existingJobsMap = Dictionary(
                            uniqueKeysWithValues: existingJobs.map {
                                ($0.job_id, $0.completed_date)
                            })

                        // 过滤出需要保存的工业项目：新的项目或已存在但未完成的项目
                        let newJobsToSave = newJobs.filter { job in
                            if let existingCompletedDate = existingJobsMap[job.job_id] {
                                // 如果已存在此项目，只有当它之前未完成时才需要更新
                                return existingCompletedDate == nil
                            }
                            // 新项目需要保存
                            return true
                        }

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

        // 检查已存在的工业项目
        let existingJobs = try await loadJobsFromDB(characterId: characterId)
        let existingJobsMap = Dictionary(
            uniqueKeysWithValues: existingJobs.map { ($0.job_id, $0.completed_date) })

        // 过滤出需要保存的工业项目：新的项目或已存在但未完成的项目
        let newJobsToSave = newJobs.filter { job in
            if let existingCompletedDate = existingJobsMap[job.job_id] {
                // 如果已存在此项目，只有当它之前未完成时才需要更新
                return existingCompletedDate == nil
            }
            // 新项目需要保存
            return true
        }

        if !newJobsToSave.isEmpty {
            try await saveJobsToDB(jobs: newJobsToSave, characterId: characterId)
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
        case let .success(rows):
            Logger.debug("从数据库加载到 \(rows.count) 条工业项目记录")
            var jobs: [IndustryJob] = []
            for row in rows {
                // 尝试转换必需字段
                do {
                    let jobId = try getInt(from: row, field: "job_id")
                    let activityId = try getInt(from: row, field: "activity_id")
                    let blueprintId = try getInt64(from: row, field: "blueprint_id")
                    let blueprintLocationId = try getInt64(
                        from: row, field: "blueprint_location_id"
                    )
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
                        let endDate = dateFormatter.date(from: endDateStr)
                    else {
                        Logger.error("日期格式转换失败: start_date=\(startDateStr), end_date=\(endDateStr)")
                        throw IndustryAPIError.dataError("日期格式转换失败")
                    }

                    // 处理可选字段
                    let completedCharacterId = getOptionalInt(
                        from: row, field: "completed_character_id"
                    )
                    let completedDate = (row["completed_date"] as? String).flatMap {
                        dateFormatter.date(from: $0)
                    }
                    let licensedRuns = getOptionalInt(from: row, field: "licensed_runs")
                    let pauseDate = (row["pause_date"] as? String).flatMap {
                        dateFormatter.date(from: $0)
                    }
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

        case let .error(error):
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

        // 获取已存在的工业项目ID
        let checkQuery = "SELECT job_id FROM industry_jobs WHERE character_id = ?"
        let existingResult = databaseManager.executeQuery(checkQuery, parameters: [characterId])
        var existingJobIds = Set<Int>()
        if case let .success(rows) = existingResult {
            Logger.debug("查询已存在工业项目SQL: \(checkQuery), characterId: \(characterId)")
            Logger.debug("查询结果行数: \(rows.count)")
            existingJobIds = Set(
                rows.compactMap { row -> Int? in
                    if let jobId = row["job_id"] as? Int {
                        return jobId
                    }
                    if let jobId = row["job_id"] as? Int64 {
                        return Int(jobId)
                    }
                    return nil
                })
            Logger.debug("数据库中已存在的工业项目ID数量: \(existingJobIds.count)")
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
        var updatedCount = 0
        for job in jobs {
            Logger.debug(
                "处理工业项目: jobId=\(job.job_id), completed_date=\(String(describing: job.completed_date))"
            )

            // 处理可选类型，将 nil 转换为 NSNull()
            let completedCharacterId = job.completed_character_id.map { $0 as Any } ?? NSNull()
            let completedDate =
                job.completed_date.map { dateFormatter.string(from: $0) as Any } ?? NSNull()
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
                successfulRuns,
            ]

            if existingJobIds.contains(job.job_id) {
                // 如果项目已存在但未完成，更新它
                let updateQuery = """
                        UPDATE industry_jobs SET
                            activity_id = ?, blueprint_id = ?, blueprint_location_id = ?,
                            blueprint_type_id = ?, completed_character_id = ?, completed_date = ?,
                            cost = ?, duration = ?, end_date = ?, facility_id = ?,
                            installer_id = ?, licensed_runs = ?, output_location_id = ?,
                            pause_date = ?, probability = ?, product_type_id = ?,
                            runs = ?, start_date = ?, station_id = ?, status = ?,
                            successful_runs = ?, last_updated = datetime('now')
                        WHERE character_id = ? AND job_id = ?
                    """

                // 重新排列参数以匹配 UPDATE 语句
                var updateParameters = Array(parameters[2...22])  // 跳过 characterId 和 job_id
                updateParameters.append(characterId)
                updateParameters.append(job.job_id)

                Logger.debug("正在更新工业项目: characterId=\(characterId), jobId=\(job.job_id)")
                if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                    updateQuery, parameters: updateParameters
                ) {
                    Logger.error(
                        "更新数据失败: characterId=\(characterId), jobId=\(job.job_id), error=\(error)")
                    throw IndustryAPIError.databaseError("更新数据失败: \(error)")
                }
                updatedCount += 1
            } else {
                // 如果项目不存在，插入它
                Logger.debug("正在插入新的工业项目数据: characterId=\(characterId), jobId=\(job.job_id)")
                if case let .error(error) = CharacterDatabaseManager.shared.executeQuery(
                    insertQuery, parameters: parameters
                ) {
                    Logger.error(
                        "插入数据失败: characterId=\(characterId), jobId=\(job.job_id), error=\(error)")
                    throw IndustryAPIError.databaseError("插入数据失败: \(error)")
                }
                insertedCount += 1
            }
        }

        Logger.debug(
            "成功保存工业项目数据: characterId=\(characterId), 新增数量=\(insertedCount), 更新数量=\(updatedCount)")
    }

    private func fetchFromNetwork(characterId: Int) async throws -> [IndustryJob] {
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
        for job in jobs {
            Logger.debug(
                "API 工业项目: jobId=\(job.job_id), status=\(job.status), completed_date=\(String(describing: job.completed_date))"
            )
        }

        return jobs
    }
}
