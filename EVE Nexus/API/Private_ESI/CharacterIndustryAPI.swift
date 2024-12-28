import Foundation

class CharacterIndustryAPI {
    static let shared = CharacterIndustryAPI()
    
    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("IndustryCache")
    }()
    
    private let cacheValidityDuration: TimeInterval = 60 * 60 // 60 分钟的缓存有效期
    
    private init() {
        // 创建缓存目录
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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
    
    private func getCacheFilePath(for characterId: Int) -> URL {
        return cacheDirectory.appendingPathComponent("industry_jobs_\(characterId).json")
    }
    
    private func loadFromCache(characterId: Int) -> [IndustryJob]? {
        let cacheFile = getCacheFilePath(for: characterId)
        
        do {
            let data = try Data(contentsOf: cacheFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let jobs = try decoder.decode([IndustryJob].self, from: data)
            Logger.debug("从缓存加载工业项目数据成功 - 角色ID: \(characterId), 项目数量: \(jobs.count)")
            return jobs
        } catch {
            Logger.error("读取工业项目缓存失败 - 角色ID: \(characterId), 错误: \(error)")
            return nil
        }
    }
    
    private func saveToCache(jobs: [IndustryJob], characterId: Int) {
        let cacheFile = getCacheFilePath(for: characterId)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(jobs)
            try data.write(to: cacheFile)
            Logger.debug("保存工业项目数据到缓存成功 - 角色ID: \(characterId), 项目数量: \(jobs.count)")
        } catch {
            Logger.error("保存工业项目缓存失败 - 角色ID: \(characterId), 错误: \(error)")
        }
    }
    
    func fetchIndustryJobs(
        characterId: Int,
        forceRefresh: Bool = false,
        progressCallback: ((Bool) -> Void)? = nil
    ) async throws -> [IndustryJob] {
        var shouldRefreshInBackground = false
        
        // 尝试从缓存加载
        if let cachedJobs = loadFromCache(characterId: characterId) {
            // 检查缓存是否过期
            if let attributes = try? FileManager.default.attributesOfItem(atPath: getCacheFilePath(for: characterId).path),
               let modificationDate = attributes[.modificationDate] as? Date {
                if Date().timeIntervalSince(modificationDate) > cacheValidityDuration {
                    shouldRefreshInBackground = true
                }
            }
            
            if !forceRefresh {
                // 如果缓存过期，启动后台刷新
                if shouldRefreshInBackground {
                    Task {
                        do {
                            progressCallback?(true)
                            let newJobs = try await fetchFromNetwork(characterId: characterId)
                            // 合并新旧工业项目并去重
                            let mergedJobs = Set(cachedJobs).union(newJobs)
                            let finalJobs = Array(mergedJobs).sorted { $0.start_date > $1.start_date }
                            // 更新缓存
                            saveToCache(jobs: finalJobs, characterId: characterId)
                            progressCallback?(false)
                            // 在主线程发送通知以刷新UI
                            await MainActor.run {
                                NotificationCenter.default.post(name: NSNotification.Name("IndustryJobsUpdated"), object: nil, userInfo: ["characterId": characterId])
                            }
                        } catch {
                            Logger.error("后台更新工业项目数据失败: \(error)")
                            progressCallback?(false)
                        }
                    }
                }
                return cachedJobs
            }
        }
        
        // 如果没有缓存或强制刷新
        progressCallback?(true)
        let newJobs = try await fetchFromNetwork(characterId: characterId)
        
        // 如果有缓存，合并新旧数据
        if let cachedJobs = loadFromCache(characterId: characterId) {
            let mergedJobs = Set(cachedJobs).union(newJobs)
            let finalJobs = Array(mergedJobs).sorted { $0.start_date > $1.start_date }
            saveToCache(jobs: finalJobs, characterId: characterId)
            progressCallback?(false)
            return finalJobs
        }
        
        // 如果没有缓存，直接保存新数据
        saveToCache(jobs: newJobs, characterId: characterId)
        progressCallback?(false)
        return newJobs
    }
    
    private func fetchFromNetwork(characterId: Int) async throws -> [IndustryJob] {
        let url = URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/industry/jobs/?datasource=tranquility&include_completed=true")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(from: url, characterId: characterId)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([IndustryJob].self, from: data)
    }
    
    // 清除指定角色的缓存
    func clearCache(for characterId: Int) {
        let cacheFile = getCacheFilePath(for: characterId)
        try? FileManager.default.removeItem(at: cacheFile)
        Logger.debug("清除工业项目缓存 - 角色ID: \(characterId)")
    }
    
    // 清除所有缓存
    func clearAllCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        Logger.debug("清除所有工业项目缓存")
    }
} 
