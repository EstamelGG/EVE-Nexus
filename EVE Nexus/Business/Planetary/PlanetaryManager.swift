import Foundation

/// 行星开发管理器
class PlanetaryManager {
    /// 单例
    static let shared = PlanetaryManager()
    
    /// 仓库
    private let repository = PlanetaryIndustryRepository()
    
    private init() {}
    
    /// 模拟殖民地
    /// - Parameters:
    ///   - characterId: 角色ID
    ///   - planetId: 行星ID
    ///   - esiResponse: ESI API 响应内容
    ///   - startTime: 开始时间
    /// - Returns: 模拟后的殖民地状态
    func simulateColony(
        characterId: Int,
        planetId: Int,
        esiResponse: PlanetaryDetail,
        startTime: String
    ) -> Colony {
        // 1. 创建殖民地的初始数据模型
        let colony = repository.createColony(
            characterId: characterId,
            planetId: planetId,
            planetaryDetail: esiResponse,
            startTime: startTime
        )
        
        // 2. 创建模拟器
        let simulator = ColonySimulation(colony: colony)
        
        // 3. 执行模拟（默认模拟到当前时间）
        let results = simulator.simulate()
        
        // 4. 返回最后一个状态
        return results.last?.colony ?? colony
    }
} 
