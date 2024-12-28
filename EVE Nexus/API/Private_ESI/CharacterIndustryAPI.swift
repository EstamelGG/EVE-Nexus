import Foundation

class CharacterIndustryAPI {
    static let shared = CharacterIndustryAPI()
    
    private let cacheDirectory: URL = {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("IndustryCache")
    }()
    
    private let cacheValidityDuration: TimeInterval = 5 * 60 // 5分钟的缓存有效期
    
    private init() {
        // 创建缓存目录
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    // 工业项目信息模型
    struct IndustryJob: Codable, Identifiable {
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
    }
    
    private func getCacheFilePath(for characterId: Int) -> URL {
        return cacheDirectory.appendingPathComponent("industry_jobs_\(characterId).json")
    }
    
    private func loadFromCache(characterId: Int) -> [IndustryJob]? {
        let cacheFile = getCacheFilePath(for: characterId)
        
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        
        // 检查缓存是否过期
        if Date().timeIntervalSince(modificationDate) > cacheValidityDuration {
            Logger.debug("工业项目缓存已过期 - 角色ID: \(characterId)")
            return nil
        }
        
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
    
    func fetchIndustryJobs(characterId: Int, forceRefresh: Bool = false) async throws -> [IndustryJob] {
        // 如果不是强制刷新，尝试从缓存加载
        if !forceRefresh {
            if let cachedJobs = loadFromCache(characterId: characterId) {
                return cachedJobs
            }
        }
        
        let url = URL(string: "https://esi.evetech.net/latest/characters/\(characterId)/industry/jobs/?datasource=tranquility&include_completed=true")!
        
        let data = try await NetworkManager.shared.fetchDataWithToken(from: url, characterId: characterId)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let jobs = try decoder.decode([IndustryJob].self, from: data)
        
        // 保存到缓存
        saveToCache(jobs: jobs, characterId: characterId)
        
        return jobs
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
