import Foundation

/// 计算动态挂点数量（考虑子系统修饰器）
private func calculateDynamicHardpoints(simulationInput: SimulationInput) -> (turretHardpoints: Int, launcherHardpoints: Int) {
    // 获取基础挂点数
    let baseTurretHardpoints = Int(simulationInput.ship.baseAttributesByName["turretSlotsLeft"] ?? 0)
    let baseLauncherHardpoints = Int(simulationInput.ship.baseAttributesByName["launcherSlotsLeft"] ?? 0)
    
    var totalTurretHardpoints = baseTurretHardpoints
    var totalLauncherHardpoints = baseLauncherHardpoints
    
    // 遍历所有已安装的模块，查找子系统的挂点修饰器
    for module in simulationInput.modules {
        if let turretHardPointModifier = module.attributesByName["turretHardPointModifier"] {
            totalTurretHardpoints += Int(turretHardPointModifier)
            Logger.info("子系统 \(module.name) 增加炮台挂点: \(Int(turretHardPointModifier))")
        }
        
        if let launcherHardPointModifier = module.attributesByName["launcherHardPointModifier"] {
            totalLauncherHardpoints += Int(launcherHardPointModifier)
            Logger.info("子系统 \(module.name) 增加发射器挂点: \(Int(launcherHardPointModifier))")
        }
    }
    
    // 确保挂点数不为负数
    totalTurretHardpoints = max(0, totalTurretHardpoints)
    totalLauncherHardpoints = max(0, totalLauncherHardpoints)
    
    Logger.info("动态挂点计算结果 - 炮台挂点: \(totalTurretHardpoints) (基础: \(baseTurretHardpoints)), 发射器挂点: \(totalLauncherHardpoints) (基础: \(baseLauncherHardpoints))")
    
    return (turretHardpoints: totalTurretHardpoints, launcherHardpoints: totalLauncherHardpoints)
}

/// 处理配置中的装备，逐个检查是否可以安装到飞船上
/// - Parameters:
///   - simulationInput: 模拟输入数据
///   - databaseManager: 数据库管理器
/// - Returns: (处理后的配置, 被跳过的模块列表)
func processConfiguration(simulationInput: SimulationInput, databaseManager: DatabaseManager) -> (SimulationInput, [(module: SimModule, reason: String)]) {
    // 创建空的模拟输入作为起点
    var processedInput = simulationInput
    processedInput.modules = []
    
    // 跟踪被跳过的模块
    var skippedModules: [(module: SimModule, reason: String)] = []
    
    // 按优先级对模块进行分类
    let modulesByPriority = categorizeModulesByPriority(modules: simulationInput.modules)
    
    // 按优先级顺序逐个尝试安装模块
    let allModulesInOrder = modulesByPriority.subsystems + 
                           modulesByPriority.rigs + 
                           modulesByPriority.hiSlots + 
                           modulesByPriority.medSlots + 
                           modulesByPriority.lowSlots + 
                           modulesByPriority.others
    
    for module in allModulesInOrder {
        // 获取当前配置的动态挂点数量
        let (turretSlotsNum, launcherSlotsNum) = calculateDynamicHardpoints(simulationInput: processedInput)
        
        // 执行装配检查
        let canInstall = canFit(
            simulationInput: processedInput,  // 使用已处理的配置进行检查
            itemAttributes: module.attributes,
            itemAttributesName: module.attributesByName,
            itemEffects: module.effects,
            volume: module.attributesByName["volume"] ?? 0,
            typeId: module.typeId,
            itemGroupID: module.groupID,
            databaseManager: databaseManager,
            turretSlotsNum: turretSlotsNum,
            launcherSlotsNum: launcherSlotsNum
        )
        
        if canInstall {
            // 如果可以安装，添加到处理后的配置中
            processedInput.modules.append(module)
            Logger.info("成功安装装备: \(module.name) 到槽位 \(module.flag?.rawValue ?? "未知")")
        } else {
            // 如果不能安装，记录到被跳过模块列表
            let reason = "该装备无法安装到当前飞船: \(module.name)"
            Logger.fault(reason)
            skippedModules.append((module: module, reason: reason))
        }
    }
    
    return (processedInput, skippedModules)
}

/// 按优先级对模块进行分类
/// - Parameter modules: 模块列表
/// - Returns: 按优先级分类的模块
private func categorizeModulesByPriority(modules: [SimModule]) -> (
    subsystems: [SimModule],
    rigs: [SimModule], 
    hiSlots: [SimModule],
    medSlots: [SimModule],
    lowSlots: [SimModule],
    others: [SimModule]
) {
    var subsystems: [SimModule] = []
    var rigs: [SimModule] = []
    var hiSlots: [SimModule] = []
    var medSlots: [SimModule] = []
    var lowSlots: [SimModule] = []
    var others: [SimModule] = []
    
    for module in modules {
        guard let flag = module.flag else {
            others.append(module)
            continue
        }
        
        switch flag {
        // 子系统槽位 (最高优先级)
        case .subSystemSlot0, .subSystemSlot1, .subSystemSlot2, .subSystemSlot3:
            subsystems.append(module)
            
        // 改装槽位 (第二优先级)
        case .rigSlot0, .rigSlot1, .rigSlot2:
            rigs.append(module)
            
        // 高槽位 (第三优先级)
        case .hiSlot0, .hiSlot1, .hiSlot2, .hiSlot3, .hiSlot4, .hiSlot5, .hiSlot6, .hiSlot7:
            hiSlots.append(module)
            
        // 中槽位 (第四优先级)
        case .medSlot0, .medSlot1, .medSlot2, .medSlot3, .medSlot4, .medSlot5, .medSlot6, .medSlot7:
            medSlots.append(module)
            
        // 低槽位 (第五优先级)
        case .loSlot0, .loSlot1, .loSlot2, .loSlot3, .loSlot4, .loSlot5, .loSlot6, .loSlot7:
            lowSlots.append(module)
            
        default:
            others.append(module)
        }
    }
    
    // 对每个分类内的模块按槽位索引排序
    subsystems.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
    rigs.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
    hiSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
    medSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
    lowSlots.sort { getSlotIndex(from: $0.flag) < getSlotIndex(from: $1.flag) }
    
    Logger.info("装备分类完成 - 子系统: \(subsystems.count), 改装: \(rigs.count), 高槽: \(hiSlots.count), 中槽: \(medSlots.count), 低槽: \(lowSlots.count), 其他: \(others.count)")
    
    return (subsystems: subsystems, rigs: rigs, hiSlots: hiSlots, medSlots: medSlots, lowSlots: lowSlots, others: others)
}

/// 从槽位标识中提取槽位索引
/// - Parameter flag: 槽位标识
/// - Returns: 槽位索引
private func getSlotIndex(from flag: FittingFlag?) -> Int {
    guard let flag = flag else { return 999 }
    
    switch flag {
    case .subSystemSlot0, .rigSlot0, .hiSlot0, .medSlot0, .loSlot0: return 0
    case .subSystemSlot1, .rigSlot1, .hiSlot1, .medSlot1, .loSlot1: return 1
    case .subSystemSlot2, .rigSlot2, .hiSlot2, .medSlot2, .loSlot2: return 2
    case .subSystemSlot3, .hiSlot3, .medSlot3, .loSlot3: return 3
    case .hiSlot4, .medSlot4, .loSlot4: return 4
    case .hiSlot5, .medSlot5, .loSlot5: return 5
    case .hiSlot6, .medSlot6, .loSlot6: return 6
    case .hiSlot7, .medSlot7, .loSlot7: return 7
    default: return 999
    }
} 
