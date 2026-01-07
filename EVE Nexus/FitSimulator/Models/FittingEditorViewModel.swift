import Foundation
import SwiftUI

/// 配置编辑器视图模型 - 管理配置编辑过程中的状态
@MainActor
class FittingEditorViewModel: ObservableObject {
    // 配置数据
    @Published var simulationInput: SimulationInput

    // 新的计算结果（使用输出结构）
    @Published private(set) var simulationOutput: SimulationOutput?

    // 技能选择状态（在配置生命周期内保持，但不持久化到文件）
    @Published var currentSkillsMode: String = "all5"
    @Published var currentSelectedCharacterId: Int? = nil

    // 元数据
    @Published var shipInfo: (name: String, iconFileName: String)
    @Published var isNewFitting: Bool
    @Published var isLocalFitting: Bool = true // 是否为本地配置，默认为true
    @Published var hasUnsavedChanges = false
    @Published var errorMessage: String? // 添加错误消息
    @Published var invalidModules: [(module: SimModule, reason: String)] = [] // 无效的模块列表

    // 槽位折叠状态（临时保存，退出页面时自动清除）
    @Published var hiSlotsCollapsed = false
    @Published var medSlotsCollapsed = false
    @Published var loSlotsCollapsed = false
    @Published var rigSlotsCollapsed = false

    // 计算器和数据库
    private let attributeCalculator: AttributeCalculator
    let databaseManager: DatabaseManager

    // MARK: - 无人机相关属性

    // 无人机属性计算结果
    var droneAttributes:
        (
            bandwidth: (current: Double, total: Double), capacity: (current: Double, total: Double),
            dronesCount: Int, activeDronesCount: Int
        )
    {
        // 计算无人机带宽
        let totalBandwidth: Double
        if let simulationOutput = simulationOutput {
            totalBandwidth = simulationOutput.ship.attributesByName["droneBandwidth"] ?? 0
        } else {
            totalBandwidth = simulationInput.ship.baseAttributesByName["droneBandwidth"] ?? 0
        }

        // 计算当前使用的带宽
        var currentBandwidth = 0.0
        for drone in simulationInput.drones {
            if drone.activeCount > 0 {
                // 尝试从计算后的属性中获取带宽需求
                let droneBandwidthNeed: Double
                if let simulationOutput = simulationOutput,
                   let droneIndex = simulationOutput.drones.firstIndex(where: {
                       $0.typeId == drone.typeId
                   }),
                   let bandwidth = simulationOutput.drones[droneIndex].attributesByName[
                       "droneBandwidthUsed"
                   ]
                {
                    droneBandwidthNeed = bandwidth
                } else {
                    droneBandwidthNeed = drone.attributesByName["droneBandwidthUsed"] ?? 0
                }
                currentBandwidth += droneBandwidthNeed * Double(drone.activeCount)
            }
        }

        // 计算无人机舱容量
        let totalCapacity: Double
        if let simulationOutput = simulationOutput {
            totalCapacity = simulationOutput.ship.attributesByName["droneCapacity"] ?? 0
        } else {
            totalCapacity = simulationInput.ship.baseAttributesByName["droneCapacity"] ?? 0
        }

        // 计算当前使用的容量
        var currentCapacity = 0.0
        for drone in simulationInput.drones {
            // 尝试从计算后的属性中获取无人机体积
            let droneVolume: Double
            if let simulationOutput = simulationOutput,
               let droneIndex = simulationOutput.drones.firstIndex(where: {
                   $0.typeId == drone.typeId
               }),
               let volume = simulationOutput.drones[droneIndex].attributesByName["volume"]
            {
                droneVolume = volume
            } else {
                droneVolume = drone.attributesByName["volume"] ?? 0.0
            }
            currentCapacity += droneVolume * Double(drone.quantity)
        }

        // 计算无人机数量
        let dronesCount = simulationInput.drones.reduce(0) { $0 + $1.quantity }

        // 计算激活的无人机数量
        let activeDronesCount = simulationInput.drones.reduce(0) { $0 + $1.activeCount }

        return (
            bandwidth: (current: currentBandwidth, total: totalBandwidth),
            capacity: (current: currentCapacity, total: totalCapacity),
            dronesCount: dronesCount,
            activeDronesCount: activeDronesCount
        )
    }

    // 最大可激活无人机数量
    var maxActiveDrones: Int {
        // 从角色属性中获取maxActiveDrones值（属性ID 352）
        if let simulationOutput = simulationOutput,
           let maxDrones = simulationOutput.ship.characterAttributes[352]
        {
            return Int(maxDrones)
        }
        // 如果无法获取计算后的值，从模拟输入中获取基础值
        return Int(simulationInput.character.baseAttributes[352] ?? 5)
    }

    // MARK: - 初始化方法

    /// 初始化方法（新建配置）
    init(
        shipTypeId: Int, shipInfo: (name: String, iconFileName: String),
        databaseManager: DatabaseManager
    ) {
        self.databaseManager = databaseManager
        self.shipInfo = shipInfo
        isNewFitting = true
        isLocalFitting = true // 新建配置为本地配置
        attributeCalculator = AttributeCalculator(databaseManager: databaseManager)

        // 创建初始配置
        let localFitting = FitConvert.createInitialFitting(shipTypeId: shipTypeId)

        // 获取已保存的技能设置
        let characterSkills = FittingEditorViewModel.getSkillsFromPreferences()

        // 转换为模拟输入
        simulationInput = FitConvert.localFittingToSimulationInput(
            localFitting: localFitting,
            databaseManager: databaseManager,
            characterSkills: characterSkills
        )

        // 计算初始属性
        Logger.info("新建配置，计算初始属性")
        calculateAttributes()
    }

    /// 初始化方法（加载本地配置）
    init(fittingId: Int, databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        attributeCalculator = AttributeCalculator(databaseManager: databaseManager)

        do {
            // 加载配置
            let localFitting = try FitConvert.loadLocalFitting(fittingId: fittingId)

            // 查询飞船信息
            let shipQuery = "SELECT name, icon_filename FROM types WHERE type_id = ?"
            if case let .success(rows) = databaseManager.executeQuery(
                shipQuery, parameters: [localFitting.ship_type_id]
            ),
                let row = rows.first,
                let name = row["name"] as? String,
                let iconFileName = row["icon_filename"] as? String
            {
                shipInfo = (name: name, iconFileName: iconFileName)
            } else {
                shipInfo = (
                    name: NSLocalizedString("Unknown", comment: "Unknown Ship"), iconFileName: ""
                )
            }

            isNewFitting = false
            isLocalFitting = true // 本地配置文件

            // 获取已保存的技能设置
            let characterSkills = FittingEditorViewModel.getSkillsFromPreferences()

            // 转换为模拟输入
            let simInput = FitConvert.localFittingToSimulationInput(
                localFitting: localFitting,
                databaseManager: databaseManager,
                characterSkills: characterSkills
            )

            // 验证配置中的装备是否都可以安装
            let (processedInput, invalidModules) = processConfiguration(
                simulationInput: simInput,
                databaseManager: databaseManager
            )

            // 直接使用处理后的输入，保留原始状态
            simulationInput = processedInput
            self.invalidModules = invalidModules

            // 如果有无效模块，设置错误消息
            if !invalidModules.isEmpty {
                let invalidModuleNames = invalidModules.map { $0.module.name }.joined(
                    separator: ", ")
                errorMessage = "以下装备无法安装到当前飞船，已自动移除: \(invalidModuleNames)"
                hasUnsavedChanges = true

                // 记录警告日志
                Logger.warning("配置中包含无法安装的装备，已移除: \(invalidModuleNames)")
            }

            // 计算初始属性
            Logger.info("加载本地配置，计算初始属性")
            calculateAttributes()
        } catch {
            // 错误处理
            Logger.error("加载配置失败: \(error)")

            // 初始化为默认值
            isNewFitting = true
            isLocalFitting = true // 错误情况下默认为本地配置
            shipInfo = (name: "Error", iconFileName: "")

            // 使用默认值 - 这里应该更优雅地处理
            simulationInput = SimulationInput(
                fittingId: Int(Date().timeIntervalSince1970),
                name: "",
                description: "",
                fighters: nil,
                ship: SimShip(
                    typeId: 0, baseAttributes: [:], baseAttributesByName: [:], effects: [],
                    groupID: 0, name: "Unknown", iconFileName: "not_found", requiredSkills: []
                ),
                modules: [],
                drones: [],
                cargo: SimCargo(items: []),
                implants: [],
                environmentEffects: [],
                characterSkills: [:]
            )
            Logger.info("加载本地配置失败，使用默认值计算初始属性")
            calculateAttributes()
        }
    }

    /// 初始化方法（临时装配，如DNA导入，不保存文件）
    init(temporaryFitting: LocalFitting, databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        attributeCalculator = AttributeCalculator(databaseManager: databaseManager)

        // 查询飞船信息
        let shipQuery = "SELECT name, icon_filename FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(
            shipQuery, parameters: [temporaryFitting.ship_type_id]
        ),
            let row = rows.first,
            let name = row["name"] as? String,
            let iconFileName = row["icon_filename"] as? String
        {
            shipInfo = (name: name, iconFileName: iconFileName)
        } else {
            shipInfo = (
                name: NSLocalizedString("Unknown", comment: "Unknown Ship"), iconFileName: ""
            )
        }

        isNewFitting = false
        isLocalFitting = false // 临时装配，不是真正的本地配置文件

        // 获取已保存的技能设置
        let characterSkills = FittingEditorViewModel.getSkillsFromPreferences()

        // 转换为模拟输入
        let simInput = FitConvert.localFittingToSimulationInput(
            localFitting: temporaryFitting,
            databaseManager: databaseManager,
            characterSkills: characterSkills
        )

        // 验证配置中的装备是否都可以安装
        let (processedInput, invalidModules) = processConfiguration(
            simulationInput: simInput,
            databaseManager: databaseManager
        )

        // 直接使用处理后的输入
        simulationInput = processedInput
        self.invalidModules = invalidModules

        // 如果有无效模块，设置错误消息
        if !invalidModules.isEmpty {
            let invalidModuleNames = invalidModules.map { $0.module.name }.joined(separator: ", ")
            errorMessage = "以下装备无法安装到当前飞船，已自动移除: \(invalidModuleNames)"

            Logger.warning("DNA装配中包含无法安装的装备，已移除: \(invalidModuleNames)")
        }

        Logger.info("创建临时装配视图模型，计算初始属性")
        calculateAttributes()
    }

    /// 初始化方法（加载在线配置）
    init(onlineFitting: CharacterFitting, databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        attributeCalculator = AttributeCalculator(databaseManager: databaseManager)

        // 查询飞船信息
        let shipQuery = "SELECT name, icon_filename FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(
            shipQuery, parameters: [onlineFitting.ship_type_id]
        ),
            let row = rows.first,
            let name = row["name"] as? String,
            let iconFileName = row["icon_filename"] as? String
        {
            shipInfo = (name: name, iconFileName: iconFileName)
        } else {
            shipInfo = (
                name: NSLocalizedString("Unknown", comment: "Unknown Ship"), iconFileName: ""
            )
        }

        isNewFitting = false
        isLocalFitting = false // 在线配置

        // 将在线配置转换为本地配置
        // 创建FittingItem数组
        let fittingItems = onlineFitting.items.map { item in
            FittingItem(flag: item.flag, quantity: item.quantity, type_id: item.type_id)
        }

        // 创建在线配置对象
        let onlineFittingObj = OnlineFitting(
            description: onlineFitting.description ?? "",
            fitting_id: onlineFitting.fitting_id,
            items: fittingItems,
            name: onlineFitting.name,
            ship_type_id: onlineFitting.ship_type_id
        )

        // 将在线配置转换为本地配置
        do {
            let jsonData = try JSONEncoder().encode([onlineFittingObj])
            Logger.info(
                "将在线配置转换为JSON: 飞船ID=\(onlineFitting.ship_type_id), 配置项数量=\(fittingItems.count)")
            if let localFittings = try? FitConvert.online2local(jsonData: jsonData),
               let localFitting = localFittings.first
            {
                Logger.success("成功转换为本地配置: 舰载机数量=\(localFitting.fighters?.count ?? 0)")
                // 获取已保存的技能设置
                let characterSkills = FittingEditorViewModel.getSkillsFromPreferences()

                // 转换为模拟输入
                let simInput = FitConvert.localFittingToSimulationInput(
                    localFitting: localFitting,
                    databaseManager: databaseManager,
                    characterSkills: characterSkills
                )
                Logger.info("转换为模拟输入: 舰载机数量=\(simInput.fighters?.count ?? 0)")

                // 验证配置中的装备是否都可以安装
                let (processedInput, invalidModules) = processConfiguration(
                    simulationInput: simInput,
                    databaseManager: databaseManager
                )

                // 设置合适的装备状态
                var updatedModules = processedInput.modules

                // 对每个装备设置合适的状态
                for i in 0 ..< updatedModules.count {
                    let module = updatedModules[i]

                    // 计算最大状态
                    let maxStatus = getMaxStatus(
                        itemEffects: module.effects,
                        itemAttributes: module.attributes,
                        databaseManager: databaseManager
                    )

                    // 根据最大状态设置默认状态
                    var newStatus: Int
                    switch maxStatus {
                    case 3: // 可超载
                        newStatus = 2 // 默认为激活状态
                    case 2: // 可激活
                        newStatus = 2 // 默认为激活状态
                    case 1: // 可在线
                        newStatus = 1 // 默认为在线状态
                    default:
                        newStatus = 0 // 默认为离线状态
                    }

                    // 创建临时模块列表，不包含当前处理的模块
                    var otherModules = updatedModules
                    otherModules.remove(at: i)

                    // 考虑同组装备限制
                    newStatus = setStatus(
                        itemAttributes: module.attributes,
                        itemAttributesName: module.attributesByName,
                        typeId: module.typeId,
                        typeGroupId: module.groupID,
                        currentModules: otherModules,
                        currentStatus: newStatus,
                        maxStatus: maxStatus
                    )

                    // 更新模块状态
                    updatedModules[i] = SimModule(
                        instanceId: module.instanceId, // 保留原模块的instanceId
                        typeId: module.typeId,
                        attributes: module.attributes,
                        attributesByName: module.attributesByName,
                        effects: module.effects,
                        groupID: module.groupID,
                        status: newStatus,
                        charge: module.charge,
                        flag: module.flag,
                        quantity: module.quantity,
                        name: module.name,
                        iconFileName: module.iconFileName,
                        requiredSkills: module.requiredSkills,
                        selectedMutaplasmidID: module.selectedMutaplasmidID,
                        mutatedAttributes: module.mutatedAttributes,
                        mutatedTypeId: module.mutatedTypeId,
                        mutatedName: module.mutatedName,
                        mutatedIconFileName: module.mutatedIconFileName
                    )

                    Logger.info("设置装备状态: \(module.name), 最大状态: \(maxStatus), 设置状态: \(newStatus)")
                }

                // 使用更新后的模块列表
                var finalSimInput = processedInput
                finalSimInput.modules = updatedModules

                simulationInput = finalSimInput
                self.invalidModules = invalidModules

                // 如果有无效模块，设置错误消息
                if !invalidModules.isEmpty {
                    let invalidModuleNames = invalidModules.map { $0.module.name }.joined(
                        separator: ", ")
                    errorMessage = "以下装备无法安装到当前飞船，已自动移除: \(invalidModuleNames)"
                    hasUnsavedChanges = true

                    // 记录警告日志
                    Logger.warning("在线配置中包含无法安装的装备，已移除: \(invalidModuleNames)")
                }
            } else {
                throw NSError(
                    domain: "FittingEditorViewModel", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "在线配置转换失败"]
                )
            }
        } catch {
            // 如果转换失败，使用默认值
            Logger.error("在线配置转换失败: \(error.localizedDescription)")
            simulationInput = SimulationInput(
                fittingId: onlineFitting.fitting_id,
                name: onlineFitting.name,
                description: onlineFitting.description ?? "",
                fighters: nil,
                ship: SimShip(
                    typeId: 0, baseAttributes: [:], baseAttributesByName: [:], effects: [],
                    groupID: 0, name: "Unknown", iconFileName: "not_found", requiredSkills: []
                ),
                modules: [],
                drones: [],
                cargo: SimCargo(items: []),
                implants: [],
                environmentEffects: [],
                characterSkills: [:]
            )
        }

        // 计算初始属性
        Logger.info("在线配置转换失败，使用默认数值计算初始属性")
        calculateAttributes()
    }

    // MARK: - 公共方法

    /// 保存当前配置
    func saveConfiguration() {
        do {
            let localFitting = FitConvert.simulationInputToLocalFitting(input: simulationInput)
            try FitConvert.saveLocalFitting(localFitting)
            hasUnsavedChanges = false
            Logger.info("配置保存成功")
        } catch {
            Logger.error("保存配置失败: \(error)")
        }
    }

    /// 计算动态挂点数量（考虑子系统修饰器）
    func calculateDynamicHardpoints() -> (turretHardpoints: Int, launcherHardpoints: Int) {
        // 获取基础挂点数
        let baseTurretHardpoints = Int(
            simulationInput.ship.baseAttributesByName["turretSlotsLeft"] ?? 0)
        let baseLauncherHardpoints = Int(
            simulationInput.ship.baseAttributesByName["launcherSlotsLeft"] ?? 0)

        var totalTurretHardpoints = baseTurretHardpoints
        var totalLauncherHardpoints = baseLauncherHardpoints

        // 遍历所有已安装的模块，查找子系统的挂点修饰器
        for module in simulationInput.modules {
            if let turretHardPointModifier = module.attributesByName["turretHardPointModifier"] {
                totalTurretHardpoints += Int(turretHardPointModifier)
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("子系统 \(module.name) 增加炮台挂点: \(Int(turretHardPointModifier))")
                }
            }

            if let launcherHardPointModifier = module.attributesByName["launcherHardPointModifier"] {
                totalLauncherHardpoints += Int(launcherHardPointModifier)
                if AppConfiguration.Fitting.showDebug {
                    Logger.info("子系统 \(module.name) 增加发射器挂点: \(Int(launcherHardPointModifier))")
                }
            }
        }

        // 确保挂点数不为负数
        totalTurretHardpoints = max(0, totalTurretHardpoints)
        totalLauncherHardpoints = max(0, totalLauncherHardpoints)

        if AppConfiguration.Fitting.showDebug {
            Logger.info(
                "动态挂点计算结果 - 炮台挂点: \(totalTurretHardpoints) (基础: \(baseTurretHardpoints)), 发射器挂点: \(totalLauncherHardpoints) (基础: \(baseLauncherHardpoints))"
            )
        }

        return (
            turretHardpoints: totalTurretHardpoints, launcherHardpoints: totalLauncherHardpoints
        )
    }

    /// 重新计算属性
    func calculateAttributes() {
        Logger.info("【calculateAttributes】开始重新计算属性")

        // 记录输入中的舰载机信息（仅在调试模式下）
        if AppConfiguration.Fitting.showDebug {
            if let fighters = simulationInput.fighters {
                Logger.info("【calculateAttributes】输入中有 \(fighters.count) 个舰载机")
                for fighter in fighters {
                    Logger.info(
                        "【calculateAttributes】输入舰载机: \(fighter.name), typeId: \(fighter.typeId), 属性数量: \(fighter.attributesByName.count)"
                    )
                }
            } else {
                Logger.info("【calculateAttributes】输入中没有舰载机")
            }
        }

        let output = attributeCalculator.calculateAndGenerateOutput(input: simulationInput)
        simulationOutput = output

        // 记录输出中的舰载机信息（仅在调试模式下）
        if AppConfiguration.Fitting.showDebug {
            if let outputFighters = simulationOutput?.fighters {
                Logger.info("【calculateAttributes】输出中有 \(outputFighters.count) 个舰载机")
                for fighter in outputFighters {
                    Logger.info(
                        "【calculateAttributes】输出舰载机: \(fighter.name), typeId: \(fighter.typeId), 属性数量: \(fighter.attributesByName.count)"
                    )

                    // 检查伤害属性
                    let damageAttributes = fighter.attributesByName.filter {
                        $0.key.lowercased().contains("damage")
                    }
                    if !damageAttributes.isEmpty {
                        Logger.info("【calculateAttributes】输出舰载机伤害属性数量: \(damageAttributes.count)")
                    } else {
                        Logger.warning("【calculateAttributes】输出舰载机没有伤害属性")
                    }
                }
            } else {
                Logger.info("【calculateAttributes】输出中没有舰载机")
            }
        }

        Logger.info("【calculateAttributes】属性计算完成")
    }

    /// 更新配置名称
    func updateName(_ newName: String) {
        simulationInput.name = newName
        hasUnsavedChanges = true
        // calculateAttributes()
        objectWillChange.send()
    }

    /// 更新配置使用的技能
    func updateCharacterSkills(skills: [Int: Int], sourceType: CharacterSkillsType) {
        Logger.info("更新配置使用的技能数据，来源类型: \(sourceType), 技能数量: \(skills.count)")

        // 更新技能数据
        simulationInput.characterSkills = skills

        // 重新计算属性
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()
    }

    /// 更新模块状态
    func updateModuleStatus(flag: FittingFlag, newStatus: Int) {
        // 找到指定槽位的模块
        if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
            // 获取当前模块
            let currentModule = simulationInput.modules[index]

            // 记录原始状态用于日志
            let originalStatus = currentModule.status

            // 检查是否有同组装备限制
            // 优先从计算后的输出中获取，如果没有则从原始属性中获取
            let maxGroupOnline: Int
            let maxGroupActive: Int

            if let simulationOutput = simulationOutput,
               let outputModule = simulationOutput.modules.first(where: { $0.flag == flag })
            {
                // 从计算后的输出中获取
                maxGroupOnline = Int(outputModule.attributesByName["maxGroupOnline"] ?? 0)
                maxGroupActive = Int(outputModule.attributesByName["maxGroupActive"] ?? 0)
            } else {
                // 从原始属性中获取（作为备选）
                maxGroupOnline = Int(currentModule.attributesByName["maxGroupOnline"] ?? 0)
                maxGroupActive = Int(currentModule.attributesByName["maxGroupActive"] ?? 0)
            }

            Logger.info(
                """
                装备状态更新检查:
                - 装备: \(currentModule.name)
                - 槽位: \(flag.rawValue)
                - maxGroupOnline: \(maxGroupOnline)
                - maxGroupActive: \(maxGroupActive)
                - 当前状态: \(originalStatus)
                - 新状态: \(newStatus)
                """)

            // 首先更新当前模块的状态（保留突变数据）
            let updatedModule = SimModule(
                instanceId: currentModule.instanceId, // 保留原模块的instanceId
                typeId: currentModule.typeId,
                attributes: currentModule.attributes,
                attributesByName: currentModule.attributesByName,
                effects: currentModule.effects,
                groupID: currentModule.groupID,
                status: newStatus,
                charge: currentModule.charge,
                flag: currentModule.flag,
                quantity: currentModule.quantity,
                name: currentModule.name,
                iconFileName: currentModule.iconFileName,
                requiredSkills: currentModule.requiredSkills,
                selectedMutaplasmidID: currentModule.selectedMutaplasmidID,
                mutatedAttributes: currentModule.mutatedAttributes,
                mutatedTypeId: currentModule.mutatedTypeId,
                mutatedName: currentModule.mutatedName,
                mutatedIconFileName: currentModule.mutatedIconFileName
            )

            // 更新模块列表
            simulationInput.modules[index] = updatedModule

            // 如果有同组限制，需要检查和调整其他装备的状态
            if maxGroupOnline > 0 || maxGroupActive > 0 {
                // 使用ModuleGroupManager处理同组装备的连锁降级
                ModuleGroupManager.handleGroupDowngrade(
                    modules: &simulationInput.modules,
                    groupID: currentModule.groupID,
                    maxGroupOnline: maxGroupOnline,
                    maxGroupActive: maxGroupActive,
                    excludeFlags: [flag] // 不降级当前正在设置的装备
                )
            }

            // 重新计算属性
            Logger.info("更新装备状态，重新计算属性")
            calculateAttributes()

            // 标记有未保存的更改
            hasUnsavedChanges = true

            // 通知UI更新
            objectWillChange.send()

            // 自动保存配置
            saveConfiguration()

            Logger.info("更新模块状态成功: \(currentModule.name), 从 \(originalStatus) 到 \(newStatus)")
        }
    }

    /// 批量更新模块状态（优化版本，只在最后计算一次属性）
    func batchUpdateModuleStatus(flags: [FittingFlag], newStatus: Int) {
        Logger.info("开始批量更新模块状态: \(flags.count) 个模块，目标状态: \(newStatus)")

        var updatedModules: [SimModule] = []
        var actualUpdatedFlags: [FittingFlag] = []

        for flag in flags {
            if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
                let currentModule = simulationInput.modules[index]

                // 1. 首先检查模块的最大可用状态
                let maxStatus = getMaxStatus(
                    itemEffects: currentModule.effects,
                    itemAttributes: currentModule.attributes,
                    databaseManager: databaseManager
                )

                // 2. 确保新状态不超过最大可用状态
                let clampedStatus = min(newStatus, maxStatus)

                // 3. 使用setStatus函数考虑同组装备限制
                // 创建不包含当前模块的模块列表，用于状态检查
                var otherModules = simulationInput.modules
                otherModules.remove(at: index)

                // 获取计算后的属性（如果有的话）
                let calculatedAttributesName: [String: Double]?
                if let simulationOutput = simulationOutput,
                   let outputModule = simulationOutput.modules.first(where: { $0.flag == flag })
                {
                    calculatedAttributesName = outputModule.attributesByName
                } else {
                    calculatedAttributesName = nil
                }

                let finalStatus = setStatus(
                    itemAttributes: currentModule.attributes,
                    itemAttributesName: currentModule.attributesByName,
                    typeId: currentModule.typeId,
                    typeGroupId: currentModule.groupID,
                    currentModules: otherModules,
                    currentStatus: clampedStatus,
                    maxStatus: maxStatus,
                    calculatedAttributesName: calculatedAttributesName
                )

                // 4. 只有当状态确实需要改变时才更新
                if finalStatus != currentModule.status {
                    // 创建更新后的模块（保留突变数据）
                    let updatedModule = SimModule(
                        instanceId: currentModule.instanceId, // 保留原模块的instanceId
                        typeId: currentModule.typeId,
                        attributes: currentModule.attributes,
                        attributesByName: currentModule.attributesByName,
                        effects: currentModule.effects,
                        groupID: currentModule.groupID,
                        status: finalStatus,
                        charge: currentModule.charge,
                        flag: currentModule.flag,
                        quantity: currentModule.quantity,
                        name: currentModule.name,
                        iconFileName: currentModule.iconFileName,
                        requiredSkills: currentModule.requiredSkills,
                        selectedMutaplasmidID: currentModule.selectedMutaplasmidID,
                        mutatedAttributes: currentModule.mutatedAttributes,
                        mutatedTypeId: currentModule.mutatedTypeId,
                        mutatedName: currentModule.mutatedName,
                        mutatedIconFileName: currentModule.mutatedIconFileName
                    )

                    // 更新模块列表
                    simulationInput.modules[index] = updatedModule
                    updatedModules.append(updatedModule)
                    actualUpdatedFlags.append(flag)

                    Logger.info(
                        "批量更新模块状态: \(currentModule.name), 从 \(currentModule.status) 到 \(finalStatus) (目标: \(newStatus), 最大: \(maxStatus))"
                    )
                } else {
                    Logger.info("模块状态无需更新: \(currentModule.name), 保持状态 \(currentModule.status)")
                }
            }
        }

        // 5. 处理同组装备的连锁反应
        // 如果有模块被更新，需要检查是否影响了其他同组装备
        if !updatedModules.isEmpty {
            // 按组ID分组处理
            let groupedModules = Dictionary(grouping: updatedModules) { $0.groupID }

            for (groupID, modules) in groupedModules {
                if let firstModule = modules.first {
                    // 优先从计算后的输出中获取，如果没有则从原始属性中获取
                    let maxGroupOnline: Int
                    let maxGroupActive: Int

                    if let simulationOutput = simulationOutput,
                       let outputModule = simulationOutput.modules.first(where: {
                           $0.groupID == groupID
                       })
                    {
                        // 从计算后的输出中获取
                        maxGroupOnline = Int(outputModule.attributesByName["maxGroupOnline"] ?? 0)
                        maxGroupActive = Int(outputModule.attributesByName["maxGroupActive"] ?? 0)
                    } else {
                        // 从原始属性中获取（作为备选）
                        maxGroupOnline = Int(firstModule.attributesByName["maxGroupOnline"] ?? 0)
                        maxGroupActive = Int(firstModule.attributesByName["maxGroupActive"] ?? 0)
                    }

                    // 只有当有同组限制时才处理
                    if maxGroupOnline > 0 || maxGroupActive > 0 {
                        // 使用ModuleGroupManager处理同组装备的连锁降级
                        ModuleGroupManager.handleGroupDowngrade(
                            modules: &simulationInput.modules,
                            groupID: groupID,
                            maxGroupOnline: maxGroupOnline,
                            maxGroupActive: maxGroupActive,
                            excludeFlags: actualUpdatedFlags // 不降级刚刚批量设置的装备
                        )
                    }
                }
            }
        }

        // 只在最后计算一次属性
        Logger.info("批量更新模块状态完成，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("批量更新模块状态成功: \(actualUpdatedFlags.count)/\(flags.count) 个模块实际更新")
    }

    /// 批量安装弹药（优化版本，只在最后计算一次属性）
    func batchInstallCharge(typeId: Int, name: String, iconFileName: String?, flags: [FittingFlag]) {
        Logger.info("开始批量安装弹药: \(name) 到 \(flags.count) 个模块")

        // 从数据库加载弹药属性和效果
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]
        var effects: [Int] = []
        var groupId = 0
        var volume: Double = 0

        // 查询弹药属性
        let attrQuery = """
            SELECT ta.attribute_id, ta.value, da.name 
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
            WHERE ta.type_id = ?
        """

        if case let .success(rows) = databaseManager.executeQuery(attrQuery, parameters: [typeId]) {
            for row in rows {
                if let attrId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double,
                   let name = row["name"] as? String
                {
                    attributes[attrId] = value
                    attributesByName[name] = value
                    if name == "volume" {
                        volume = value
                    }
                }
            }
        }

        // 查询弹药效果
        let effectQuery = "SELECT effect_id FROM typeEffects WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(effectQuery, parameters: [typeId]) {
            for row in rows {
                if let effectId = row["effect_id"] as? Int {
                    effects.append(effectId)
                }
            }
        }

        // 查询弹药分组和体积
        let groupQuery = "SELECT groupID, volume FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(groupQuery, parameters: [typeId]) {
            if let row = rows.first, let id = row["groupID"] as? Int,
               let typeVolume = row["volume"] as? Double, typeVolume > 0
            {
                groupId = id
                volume = typeVolume
            }
        }

        // 添加volume到属性字典中
        attributes[161] = volume
        attributesByName["volume"] = volume

        // 批量安装弹药
        for flag in flags {
            if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
                let currentModule = simulationInput.modules[index]

                // 计算弹药数量
                var chargeQuantity: Int? = nil
                if volume > 0 {
                    let capacity = currentModule.attributesByName["capacity"] ?? 0
                    if capacity > 0 {
                        chargeQuantity = Int(capacity / volume)
                        Logger.info(
                            "批量安装弹药计算: 装备=\(currentModule.name), 容量=\(capacity), 弹药体积=\(volume), 计算数量=\(chargeQuantity!)"
                        )
                    } else {
                        Logger.warning("批量安装弹药失败: 装备=\(currentModule.name), 容量为0")
                    }
                } else {
                    Logger.warning("批量安装弹药失败: 弹药体积为0")
                }

                // 创建弹药对象
                let charge = SimCharge(
                    typeId: typeId,
                    attributes: attributes,
                    attributesByName: attributesByName,
                    effects: effects,
                    groupID: groupId,
                    chargeQuantity: chargeQuantity,
                    requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
                    name: name,
                    iconFileName: iconFileName
                )

                // 创建新的模块对象，添加弹药（保留突变数据）
                let updatedModule = SimModule(
                    instanceId: currentModule.instanceId, // 保留原模块的instanceId
                    typeId: currentModule.typeId,
                    attributes: currentModule.attributes,
                    attributesByName: currentModule.attributesByName,
                    effects: currentModule.effects,
                    groupID: currentModule.groupID,
                    status: currentModule.status,
                    charge: charge,
                    flag: currentModule.flag,
                    quantity: currentModule.quantity,
                    name: currentModule.name,
                    iconFileName: currentModule.iconFileName,
                    requiredSkills: currentModule.requiredSkills,
                    selectedMutaplasmidID: currentModule.selectedMutaplasmidID,
                    mutatedAttributes: currentModule.mutatedAttributes,
                    mutatedTypeId: currentModule.mutatedTypeId,
                    mutatedName: currentModule.mutatedName,
                    mutatedIconFileName: currentModule.mutatedIconFileName
                )

                // 更新模块列表
                simulationInput.modules[index] = updatedModule

                Logger.info("批量安装弹药: \(name) 到模块 \(currentModule.name)")
            }
        }

        // 只在最后计算一次属性
        Logger.info("批量安装弹药完成，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("批量安装弹药成功: \(name) 到 \(flags.count) 个模块")
    }

    /// 批量清除弹药（优化版本，只在最后计算一次属性）
    func batchRemoveCharge(flags: [FittingFlag]) {
        Logger.info("开始批量清除弹药: \(flags.count) 个模块")

        for flag in flags {
            if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
                let currentModule = simulationInput.modules[index]

                // 创建新的模块对象，移除弹药（保留突变数据）
                let updatedModule = SimModule(
                    instanceId: currentModule.instanceId, // 保留原模块的instanceId
                    typeId: currentModule.typeId,
                    attributes: currentModule.attributes,
                    attributesByName: currentModule.attributesByName,
                    effects: currentModule.effects,
                    groupID: currentModule.groupID,
                    status: currentModule.status,
                    charge: nil, // 移除弹药
                    flag: currentModule.flag,
                    quantity: currentModule.quantity,
                    name: currentModule.name,
                    iconFileName: currentModule.iconFileName,
                    requiredSkills: currentModule.requiredSkills,
                    selectedMutaplasmidID: currentModule.selectedMutaplasmidID,
                    mutatedAttributes: currentModule.mutatedAttributes,
                    mutatedTypeId: currentModule.mutatedTypeId,
                    mutatedName: currentModule.mutatedName,
                    mutatedIconFileName: currentModule.mutatedIconFileName
                )

                // 更新模块列表
                simulationInput.modules[index] = updatedModule

                Logger.info("批量清除弹药: 模块 \(currentModule.name)")
            }
        }

        // 只在最后计算一次属性
        Logger.info("批量清除弹药完成，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("批量清除弹药成功: \(flags.count) 个模块")
    }

    /// 安装弹药到指定槽位的装备
    func installCharge(typeId: Int, name: String, iconFileName: String?, flag: FittingFlag) {
        // 找到指定槽位的模块
        if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
            // 获取当前模块
            let currentModule = simulationInput.modules[index]

            // 从数据库加载弹药属性
            var attributes: [Int: Double] = [:]
            var attributesByName: [String: Double] = [:]
            var effects: [Int] = []
            var groupId = 0
            var volume: Double = 0

            // 查询弹药属性
            let attrQuery = """
                SELECT ta.attribute_id, ta.value, da.name 
                FROM typeAttributes ta 
                JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
                WHERE ta.type_id = ?
            """

            if case let .success(rows) = databaseManager.executeQuery(
                attrQuery, parameters: [typeId]
            ) {
                for row in rows {
                    if let attrId = row["attribute_id"] as? Int,
                       let value = row["value"] as? Double,
                       let name = row["name"] as? String
                    {
                        attributes[attrId] = value
                        attributesByName[name] = value
                    }
                }
            }

            // 查询弹药效果
            let effectQuery = "SELECT effect_id FROM typeEffects WHERE type_id = ?"

            if case let .success(rows) = databaseManager.executeQuery(
                effectQuery, parameters: [typeId]
            ) {
                for row in rows {
                    if let effectId = row["effect_id"] as? Int {
                        effects.append(effectId)
                    }
                }
            }

            // 查询弹药分组
            let groupQuery = "SELECT groupID, volume FROM types WHERE type_id = ?"

            if case let .success(rows) = databaseManager.executeQuery(
                groupQuery, parameters: [typeId]
            ) {
                if let row = rows.first, let id = row["groupID"] as? Int,
                   let typeVolume = row["volume"] as? Double, typeVolume > 0
                {
                    groupId = id
                    volume = typeVolume
                }
            }

            // 添加volume到属性字典中
            attributes[161] = volume
            attributesByName["volume"] = volume

            // 计算弹药数量
            var chargeQuantity: Int? = nil
            if volume > 0 {
                // 从模块属性中获取容量
                let capacity = currentModule.attributesByName["capacity"] ?? 0
                if capacity > 0 {
                    chargeQuantity = Int(capacity / volume)
                    Logger.info(
                        "单独安装弹药计算: 装备=\(currentModule.name), 容量=\(capacity), 弹药体积=\(volume), 计算数量=\(chargeQuantity!)"
                    )
                } else {
                    Logger.warning("单独安装弹药失败: 装备=\(currentModule.name), 容量为0")
                }
            } else {
                Logger.warning("单独安装弹药失败: 弹药体积为0")
            }

            // 创建弹药对象
            let charge = SimCharge(
                typeId: typeId,
                attributes: attributes,
                attributesByName: attributesByName,
                effects: effects,
                groupID: groupId,
                chargeQuantity: chargeQuantity,
                requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
                name: name,
                iconFileName: iconFileName
            )

            // 创建新的模块对象，添加弹药（保留突变数据）
            let updatedModule = SimModule(
                instanceId: currentModule.instanceId, // 保留原模块的instanceId
                typeId: currentModule.typeId,
                attributes: currentModule.attributes,
                attributesByName: currentModule.attributesByName,
                effects: currentModule.effects,
                groupID: currentModule.groupID,
                status: currentModule.status,
                charge: charge,
                flag: currentModule.flag,
                quantity: currentModule.quantity,
                name: currentModule.name,
                iconFileName: currentModule.iconFileName,
                requiredSkills: currentModule.requiredSkills,
                selectedMutaplasmidID: currentModule.selectedMutaplasmidID,
                mutatedAttributes: currentModule.mutatedAttributes,
                mutatedTypeId: currentModule.mutatedTypeId,
                mutatedName: currentModule.mutatedName,
                mutatedIconFileName: currentModule.mutatedIconFileName
            )

            // 更新模块列表
            simulationInput.modules[index] = updatedModule

            // 重新计算属性
            Logger.info("设置弹药，重新计算属性")
            calculateAttributes()

            // 标记有未保存的更改
            hasUnsavedChanges = true

            // 通知UI更新
            objectWillChange.send()

            // 自动保存配置
            saveConfiguration()

            Logger.info("安装弹药成功: \(name) 到 \(currentModule.name), 弹药数量: \(chargeQuantity ?? 0)")
        }
    }

    /// 移除指定槽位装备的弹药
    func removeCharge(flag: FittingFlag) {
        // 找到指定槽位的模块
        if let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
            // 获取当前模块
            let currentModule = simulationInput.modules[index]

            // 如果当前没有弹药，直接返回
            guard currentModule.charge != nil else { return }

            // 创建新的模块对象，移除弹药（保留突变数据）
            let updatedModule = SimModule(
                instanceId: currentModule.instanceId, // 保留原模块的instanceId
                typeId: currentModule.typeId,
                attributes: currentModule.attributes,
                attributesByName: currentModule.attributesByName,
                effects: currentModule.effects,
                groupID: currentModule.groupID,
                status: currentModule.status,
                charge: nil,
                flag: currentModule.flag,
                quantity: currentModule.quantity,
                name: currentModule.name,
                iconFileName: currentModule.iconFileName,
                requiredSkills: currentModule.requiredSkills,
                selectedMutaplasmidID: currentModule.selectedMutaplasmidID,
                mutatedAttributes: currentModule.mutatedAttributes,
                mutatedTypeId: currentModule.mutatedTypeId,
                mutatedName: currentModule.mutatedName,
                mutatedIconFileName: currentModule.mutatedIconFileName
            )

            // 更新模块列表
            simulationInput.modules[index] = updatedModule

            // 重新计算属性
            Logger.info("移除装备，重新计算属性")
            calculateAttributes()

            // 标记有未保存的更改
            hasUnsavedChanges = true

            // 通知UI更新
            objectWillChange.send()

            // 自动保存配置
            saveConfiguration()

            Logger.info("移除弹药成功: 从 \(currentModule.name)")
        }
    }

    /// 安装装备到指定的槽位
    func installModule(typeId: Int, flag: FittingFlag, status: Int = 0) {
        // 清除之前的错误消息
        errorMessage = nil

        // 从数据库加载装备属性和效果
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]
        var effects: [Int] = []
        var groupId = 0
        var model_name = ""
        var model_iconFilename = ""
        var volume: Double = 0

        // 查询装备属性
        let attrQuery = """
            SELECT ta.attribute_id, ta.value, da.name 
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
            WHERE ta.type_id = ?
        """

        if case let .success(rows) = databaseManager.executeQuery(attrQuery, parameters: [typeId]) {
            for row in rows {
                if let attrId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double,
                   let name = row["name"] as? String
                {
                    attributes[attrId] = value
                    attributesByName[name] = value
                }
            }
        }

        // 查询装备效果
        let effectQuery = "SELECT effect_id FROM typeEffects WHERE type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(effectQuery, parameters: [typeId]) {
            for row in rows {
                if let effectId = row["effect_id"] as? Int {
                    effects.append(effectId)
                }
            }
        }

        // 查询装备分组和体积
        let groupQuery =
            "SELECT name, icon_filename, groupID, volume, capacity FROM types WHERE type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(groupQuery, parameters: [typeId]) {
            if let row = rows.first {
                if let name = row["name"] as? String {
                    model_name = name
                }
                if let iconFilename = row["icon_filename"] as? String {
                    model_iconFilename = iconFilename
                }
                if let id = row["groupID"] as? Int {
                    groupId = id
                }
                if let vol = row["volume"] as? Double {
                    volume = vol

                    // 添加volume到属性字典中
                    attributes[161] = volume
                    attributesByName["volume"] = volume
                }
                // 获取capacity字段
                if let capacity = row["capacity"] as? Double, capacity > 0 {
                    attributes[38] = capacity
                    attributesByName["capacity"] = capacity
                    Logger.info("单独安装装备: \(model_name), capacity=\(capacity)")
                }
            }
        }

        // 获取飞船的炮台和发射器槽位数量
        let (turretSlotsNum, launcherSlotsNum) = calculateDynamicHardpoints()

        // 执行装配检查
        let canInstall = canFit(
            simulationInput: simulationInput,
            itemAttributes: attributes,
            itemAttributesName: attributesByName,
            itemEffects: effects,
            volume: volume,
            typeId: typeId,
            itemGroupID: groupId,
            databaseManager: databaseManager,
            turretSlotsNum: turretSlotsNum,
            launcherSlotsNum: launcherSlotsNum
        )

        // 如果不能安装，设置错误消息并返回
        if !canInstall {
            errorMessage = "无法安装装备: \(model_name)。该装备不适合当前飞船。"
            Logger.error("装备安装失败: \(model_name) - 无法安装到当前飞船")
            return
        }

        // 如果状态为0（默认值），则计算合适的默认状态
        var moduleStatus = status
        if status == 0 {
            // 计算最大状态
            let maxStatus = getMaxStatus(
                itemEffects: effects,
                itemAttributes: attributes,
                databaseManager: databaseManager
            )

            // 根据最大状态设置默认状态
            switch maxStatus {
            case 3: // 可超载
                moduleStatus = 2 // 默认为激活状态
            case 2: // 可激活
                moduleStatus = 2 // 默认为激活状态
            case 1: // 可在线
                moduleStatus = 1 // 默认为在线状态
            default:
                moduleStatus = 0 // 默认为离线状态
            }

            // 考虑同组装备限制
            moduleStatus = setStatus(
                itemAttributes: attributes,
                itemAttributesName: attributesByName,
                typeId: typeId,
                typeGroupId: groupId,
                currentModules: simulationInput.modules,
                currentStatus: moduleStatus,
                maxStatus: maxStatus
            )

            Logger.info("计算装备默认状态: \(model_name), 最大状态: \(maxStatus), 设置状态: \(moduleStatus)")
        }

        // 添加volume到属性字典中
        attributes[161] = volume
        attributesByName["volume"] = volume

        // 创建新模块
        let newModule = SimModule(
            typeId: typeId,
            attributes: attributes,
            attributesByName: attributesByName,
            effects: effects,
            groupID: groupId,
            status: moduleStatus,
            charge: nil,
            flag: flag,
            quantity: 1,
            name: model_name,
            iconFileName: model_iconFilename,
            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes)
        )

        // 移除相同槽位的旧模块（如果有）
        simulationInput.modules.removeAll(where: { $0.flag == flag })

        // 添加新模块
        simulationInput.modules.append(newModule)

        // 计算新属性
        Logger.info("安装装备，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("安装装备成功: \(model_name) 到 \(flag.rawValue), 状态: \(moduleStatus)")
    }

    /// 移除指定槽位的装备
    func removeModule(flag: FittingFlag) {
        // 检查是否有装备
        let initialCount = simulationInput.modules.count

        // 移除指定槽位的模块
        simulationInput.modules.removeAll(where: { $0.flag == flag })

        // 如果数量没变，说明没有移除任何模块
        if simulationInput.modules.count == initialCount {
            return
        }

        // 计算新属性
        Logger.info("移除属性，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("移除槽位\(flag.rawValue)的装备成功")
    }

    /// 更新模块的突变数据
    func updateModuleMutation(flag: FittingFlag, mutaplasmidID: Int?, mutatedAttributes: [Int: Double]) {
        guard let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) else {
            Logger.warning("更新模块突变数据失败: 未找到槽位 \(flag.rawValue)")
            return
        }

        let currentModule = simulationInput.modules[index]

        // 查询突变后的typeID、名称和图标
        var mutatedTypeId: Int? = nil
        var mutatedName: String? = nil
        var mutatedIconFileName: String? = nil

        if let mutaplasmidID = mutaplasmidID {
            if let resultingTypeId = databaseManager.getMutatedTypeID(
                applicableTypeID: currentModule.typeId,
                mutaplasmidID: mutaplasmidID
            ) {
                mutatedTypeId = resultingTypeId

                // 查询突变后的名称和图标
                let typeQuery = "SELECT name, icon_filename FROM types WHERE type_id = ?"
                if case let .success(rows) = databaseManager.executeQuery(
                    typeQuery, parameters: [resultingTypeId]
                ), let row = rows.first {
                    mutatedName = row["name"] as? String
                    mutatedIconFileName = row["icon_filename"] as? String
                }
            }
        }

        let updatedModule = SimModule(
            instanceId: currentModule.instanceId,
            typeId: currentModule.typeId,
            attributes: currentModule.attributes,
            attributesByName: currentModule.attributesByName,
            effects: currentModule.effects,
            groupID: currentModule.groupID,
            status: currentModule.status,
            charge: currentModule.charge,
            flag: currentModule.flag,
            quantity: currentModule.quantity,
            name: currentModule.name,
            iconFileName: currentModule.iconFileName,
            requiredSkills: currentModule.requiredSkills,
            selectedMutaplasmidID: mutaplasmidID,
            mutatedAttributes: mutatedAttributes,
            mutatedTypeId: mutatedTypeId,
            mutatedName: mutatedName,
            mutatedIconFileName: mutatedIconFileName
        )

        simulationInput.modules[index] = updatedModule

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 重新计算属性（突变会影响属性值）
        Logger.info("更新模块突变数据，重新计算属性")
        calculateAttributes()

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("更新模块突变数据成功: \(currentModule.name), 突变质体ID: \(mutaplasmidID?.description ?? "nil"), 突变属性数量: \(mutatedAttributes.count)")
    }

    /// 批量更新模块的突变数据
    func batchUpdateModuleMutation(flags: [FittingFlag], mutaplasmidID: Int?, mutatedAttributes: [Int: Double]) {
        Logger.info("开始批量更新模块突变数据: \(flags.count) 个模块")

        var updatedCount = 0
        for flag in flags {
            guard let index = simulationInput.modules.firstIndex(where: { $0.flag == flag }) else {
                Logger.warning("批量更新突变失败: 未找到槽位 \(flag.rawValue)")
                continue
            }

            let currentModule = simulationInput.modules[index]

            // 查询突变后的typeID、名称和图标
            var mutatedTypeId: Int? = nil
            var mutatedName: String? = nil
            var mutatedIconFileName: String? = nil

            if let mutaplasmidID = mutaplasmidID {
                if let resultingTypeId = databaseManager.getMutatedTypeID(
                    applicableTypeID: currentModule.typeId,
                    mutaplasmidID: mutaplasmidID
                ) {
                    mutatedTypeId = resultingTypeId

                    // 查询突变后的名称和图标
                    let typeQuery = "SELECT name, icon_filename FROM types WHERE type_id = ?"
                    if case let .success(rows) = databaseManager.executeQuery(
                        typeQuery, parameters: [resultingTypeId]
                    ), let row = rows.first {
                        mutatedName = row["name"] as? String
                        mutatedIconFileName = row["icon_filename"] as? String
                    }
                }
            }

            let updatedModule = SimModule(
                instanceId: currentModule.instanceId,
                typeId: currentModule.typeId,
                attributes: currentModule.attributes,
                attributesByName: currentModule.attributesByName,
                effects: currentModule.effects,
                groupID: currentModule.groupID,
                status: currentModule.status,
                charge: currentModule.charge,
                flag: currentModule.flag,
                quantity: currentModule.quantity,
                name: currentModule.name,
                iconFileName: currentModule.iconFileName,
                requiredSkills: currentModule.requiredSkills,
                selectedMutaplasmidID: mutaplasmidID,
                mutatedAttributes: mutatedAttributes,
                mutatedTypeId: mutatedTypeId,
                mutatedName: mutatedName,
                mutatedIconFileName: mutatedIconFileName
            )

            simulationInput.modules[index] = updatedModule
            updatedCount += 1
        }

        if updatedCount > 0 {
            // 标记有未保存的更改
            hasUnsavedChanges = true

            // 重新计算属性（突变会影响属性值）
            Logger.info("批量更新模块突变数据完成，重新计算属性")
            calculateAttributes()

            // 通知UI更新
            objectWillChange.send()

            // 自动保存配置
            saveConfiguration()

            Logger.info("批量更新模块突变数据成功: \(updatedCount)/\(flags.count) 个模块")
        }
    }

    /// 安全替换指定槽位的装备（先删除旧装备再安装新装备，如果安装失败则恢复旧装备）
    func replaceModule(typeId: Int, flag: FittingFlag, status: Int = 0) -> Bool {
        // 清除之前的错误消息
        errorMessage = nil

        // 保存旧模块
        let oldModule = simulationInput.modules.first(where: { $0.flag == flag })

        // 如果没有旧模块，直接安装新模块
        if oldModule == nil {
            installModule(typeId: typeId, flag: flag, status: status)
            return true
        }

        // 先删除旧模块
        simulationInput.modules.removeAll(where: { $0.flag == flag })

        // 从数据库加载装备属性和效果
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]
        var effects: [Int] = []
        var groupId = 0
        var model_name = ""
        var model_iconFilename = ""
        var volume: Double = 0

        // 查询装备属性
        let attrQuery = """
            SELECT ta.attribute_id, ta.value, da.name 
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
            WHERE ta.type_id = ?
        """

        if case let .success(rows) = databaseManager.executeQuery(attrQuery, parameters: [typeId]) {
            for row in rows {
                if let attrId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double,
                   let name = row["name"] as? String
                {
                    attributes[attrId] = value
                    attributesByName[name] = value
                }
            }
        }

        // 查询装备效果
        let effectQuery = "SELECT effect_id FROM typeEffects WHERE type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(effectQuery, parameters: [typeId]) {
            for row in rows {
                if let effectId = row["effect_id"] as? Int {
                    effects.append(effectId)
                }
            }
        }

        // 查询装备分组和体积
        let groupQuery =
            "SELECT name, icon_filename, groupID, volume, capacity FROM types WHERE type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(groupQuery, parameters: [typeId]) {
            if let row = rows.first {
                if let name = row["name"] as? String {
                    model_name = name
                }
                if let iconFilename = row["icon_filename"] as? String {
                    model_iconFilename = iconFilename
                }
                if let id = row["groupID"] as? Int {
                    groupId = id
                }
                if let vol = row["volume"] as? Double {
                    volume = vol

                    // 添加volume到属性字典中
                    attributes[161] = volume
                    attributesByName["volume"] = volume
                }
                // 获取capacity字段
                if let capacity = row["capacity"] as? Double, capacity > 0 {
                    attributes[38] = capacity
                    attributesByName["capacity"] = capacity
                    Logger.info("替换装备: \(model_name), capacity=\(capacity)")
                }
            }
        }

        // 获取飞船的炮台和发射器槽位数量
        let (turretSlotsNum, launcherSlotsNum) = calculateDynamicHardpoints()

        // 执行装配检查
        let canInstall = canFit(
            simulationInput: simulationInput,
            itemAttributes: attributes,
            itemAttributesName: attributesByName,
            itemEffects: effects,
            volume: volume,
            typeId: typeId,
            itemGroupID: groupId,
            databaseManager: databaseManager,
            turretSlotsNum: turretSlotsNum,
            launcherSlotsNum: launcherSlotsNum
        )

        // 如果不能安装，恢复旧模块并返回失败
        if !canInstall {
            errorMessage = "无法安装装备: \(model_name)。该装备不适合当前飞船。"
            Logger.error("装备替换失败: \(model_name) - 无法安装到当前飞船")

            // 恢复旧模块
            if let oldModule = oldModule {
                simulationInput.modules.append(oldModule)
                Logger.info("撤回装备替换，重新计算属性")
                calculateAttributes()
                objectWillChange.send()
            }

            return false
        }

        // 如果状态为0（默认值），则计算合适的默认状态
        var moduleStatus = status
        if status == 0 {
            // 计算最大状态
            let maxStatus = getMaxStatus(
                itemEffects: effects,
                itemAttributes: attributes,
                databaseManager: databaseManager
            )

            // 根据最大状态设置默认状态
            switch maxStatus {
            case 3: // 可超载
                moduleStatus = 2 // 默认为激活状态
            case 2: // 可激活
                moduleStatus = 2 // 默认为激活状态
            case 1: // 可在线
                moduleStatus = 1 // 默认为在线状态
            default:
                moduleStatus = 0 // 默认为离线状态
            }

            // 考虑同组装备限制
            moduleStatus = setStatus(
                itemAttributes: attributes,
                itemAttributesName: attributesByName,
                typeId: typeId,
                typeGroupId: groupId,
                currentModules: simulationInput.modules,
                currentStatus: moduleStatus,
                maxStatus: maxStatus
            )

            Logger.info("计算装备默认状态: \(model_name), 最大状态: \(maxStatus), 设置状态: \(moduleStatus)")
        }

        // 添加volume到属性字典中
        attributes[161] = volume
        attributesByName["volume"] = volume

        // 创建新模块（装备更换后清除突变信息）
        let newModule = SimModule(
            typeId: typeId,
            attributes: attributes,
            attributesByName: attributesByName,
            effects: effects,
            groupID: groupId,
            status: moduleStatus,
            charge: nil,
            flag: flag,
            quantity: 1,
            name: model_name,
            iconFileName: model_iconFilename,
            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
            selectedMutaplasmidID: nil, // 装备更换后清除突变信息
            mutatedAttributes: [:] // 装备更换后清除突变信息
        )

        // 尝试保留原有装备的弹药
        if let oldCharge = oldModule?.charge {
            // 检查新装备是否可以装载旧弹药
            let canLoadOldCharge = canLoadCharge(
                moduleTypeId: typeId, chargeTypeId: oldCharge.typeId
            )
            if canLoadOldCharge {
                // 重新计算弹药数量（基于新装备的容量）
                var updatedChargeQuantity: Int? = oldCharge.chargeQuantity
                let chargeVolume = oldCharge.attributesByName["volume"] ?? 0
                if chargeVolume > 0 {
                    let newModuleCapacity = attributesByName["capacity"] ?? 0
                    if newModuleCapacity > 0 {
                        updatedChargeQuantity = Int(newModuleCapacity / chargeVolume)
                    }
                }

                // 创建更新后的弹药对象
                let updatedCharge = SimCharge(
                    typeId: oldCharge.typeId,
                    attributes: oldCharge.attributes,
                    attributesByName: oldCharge.attributesByName,
                    effects: oldCharge.effects,
                    groupID: oldCharge.groupID,
                    chargeQuantity: updatedChargeQuantity, // 使用重新计算的数量
                    requiredSkills: oldCharge.requiredSkills,
                    name: oldCharge.name,
                    iconFileName: oldCharge.iconFileName
                )

                // 创建带有更新弹药的新模块（装备更换后清除突变信息）
                let updatedModule = SimModule(
                    instanceId: oldModule?.instanceId ?? UUID(), // 保留原模块的instanceId
                    typeId: typeId,
                    attributes: attributes,
                    attributesByName: attributesByName,
                    effects: effects,
                    groupID: groupId,
                    status: moduleStatus,
                    charge: updatedCharge, // 使用更新后的弹药
                    flag: flag,
                    quantity: 1,
                    name: model_name,
                    iconFileName: model_iconFilename,
                    requiredSkills: newModule.requiredSkills,
                    selectedMutaplasmidID: nil, // 装备更换后清除突变信息
                    mutatedAttributes: [:] // 装备更换后清除突变信息
                )

                // 使用带有弹药的模块
                simulationInput.modules.append(updatedModule)
                Logger.info(
                    "替换装备成功并保留弹药: \(model_name) 到 \(flag.rawValue), 弹药: \(oldCharge.name), 重新计算数量: \(updatedChargeQuantity ?? 0)"
                )
            } else {
                // 如果不能装载原有弹药，使用无弹药的模块
                simulationInput.modules.append(newModule)
                Logger.info("替换装备成功但无法保留原有弹药: \(model_name) 到 \(flag.rawValue)")
            }
        } else {
            // 如果原来没有弹药，直接添加新模块
            simulationInput.modules.append(newModule)
        }

        // 计算新属性
        Logger.info("替换装备，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("替换装备成功: \(model_name) 到 \(flag.rawValue), 状态: \(moduleStatus)")
        return true
    }

    // MARK: - 无人机相关方法

    /// 添加无人机到配置中
    func addDrone(
        typeId: Int, name: String, iconFileName: String?, quantity: Int, activeCount: Int = 0
    ) {
        // 获取无人机信息
        let droneInfo = getDroneInfo(typeId: typeId)

        // 如果无法获取无人机信息，直接返回
        guard let droneInfo = droneInfo else {
            Logger.error("无法获取无人机信息: \(typeId)")
            return
        }

        // 检查是否已存在相同类型的无人机
        if let index = simulationInput.drones.firstIndex(where: { $0.typeId == typeId }) {
            // 更新现有无人机数量
            let existingDrone = simulationInput.drones[index]
            let newQuantity = existingDrone.quantity + quantity
            let newActiveCount = existingDrone.activeCount + activeCount

            // 创建更新后的无人机对象（保留突变数据）
            var updatedDrone = SimDrone(
                typeId: existingDrone.typeId,
                attributes: existingDrone.attributes,
                attributesByName: existingDrone.attributesByName,
                effects: existingDrone.effects,
                quantity: newQuantity,
                activeCount: newActiveCount,
                groupID: existingDrone.groupID,
                requiredSkills: existingDrone.requiredSkills,
                name: existingDrone.name,
                iconFileName: existingDrone.iconFileName
            )
            // 保留突变数据（包括显示信息）
            updatedDrone.selectedMutaplasmidID = existingDrone.selectedMutaplasmidID
            updatedDrone.mutatedAttributes = existingDrone.mutatedAttributes
            updatedDrone.mutatedTypeId = existingDrone.mutatedTypeId
            updatedDrone.mutatedName = existingDrone.mutatedName
            updatedDrone.mutatedIconFileName = existingDrone.mutatedIconFileName

            // 更新无人机列表
            simulationInput.drones[index] = updatedDrone
        } else {
            // 添加新的无人机
            let newDrone = SimDrone(
                typeId: typeId,
                attributes: droneInfo.attributes,
                attributesByName: droneInfo.attributesByName,
                effects: droneInfo.effects,
                quantity: quantity,
                activeCount: activeCount,
                groupID: droneInfo.groupID,
                requiredSkills: FitConvert.extractRequiredSkills(attributes: droneInfo.attributes),
                name: name,
                iconFileName: iconFileName
            )

            // 添加到无人机列表
            simulationInput.drones.append(newDrone)
        }

        // 重新计算属性
        Logger.info("添加无人机，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("添加无人机成功: \(name), 数量: \(quantity), 激活数量: \(activeCount)")
    }

    /// 移除指定类型的无人机
    func removeDrone(typeId: Int) {
        // 检查是否存在该类型的无人机
        let initialCount = simulationInput.drones.count

        // 移除指定类型的无人机
        simulationInput.drones.removeAll(where: { $0.typeId == typeId })

        // 如果数量没变，说明没有移除任何无人机
        if simulationInput.drones.count == initialCount {
            return
        }

        // 重新计算属性
        Logger.info("移除无人机，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("移除无人机成功，类型ID: \(typeId)")
    }

    /// 移除指定索引的无人机
    func removeDrone(at index: Int) {
        // 检查索引是否有效
        guard index >= 0, index < simulationInput.drones.count else {
            return
        }

        // 移除指定索引的无人机
        simulationInput.drones.remove(at: index)

        // 重新计算属性
        Logger.info("移除无人机，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("移除索引为\(index)的无人机成功")
    }

    /// 获取无人机信息
    func getDroneInfo(typeId: Int) -> (
        attributes: [Int: Double], attributesByName: [String: Double], effects: [Int],
        volume: Double, bandwidth: Double, groupID: Int
    )? {
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]
        var effects: [Int] = []
        var volume: Double = 0
        var bandwidth: Double = 0
        let groupID = getDroneGroupID(typeId: typeId)

        // 查询无人机属性
        let attrQuery = """
            SELECT ta.attribute_id, ta.value, da.name 
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
            WHERE ta.type_id = ?
        """

        if case let .success(rows) = databaseManager.executeQuery(attrQuery, parameters: [typeId]) {
            for row in rows {
                if let attrId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double,
                   let name = row["name"] as? String
                {
                    attributes[attrId] = value
                    attributesByName[name] = value

                    // 如果是带宽属性，记录下来
                    if name == "droneBandwidthUsed" {
                        bandwidth = value
                    }
                }
            }
        }

        // 查询无人机效果
        let effectQuery = "SELECT effect_id FROM typeEffects WHERE type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(effectQuery, parameters: [typeId]) {
            for row in rows {
                if let effectId = row["effect_id"] as? Int {
                    effects.append(effectId)
                }
            }
        }

        // 查询无人机体积
        let volumeQuery = "SELECT volume FROM types WHERE type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(volumeQuery, parameters: [typeId]) {
            if let row = rows.first, let typeVolume = row["volume"] as? Double, typeVolume > 0 {
                volume = typeVolume

                // 将volume添加到属性字典中
                attributes[161] = volume
                attributesByName["volume"] = volume
            }
        }

        return (
            attributes: attributes, attributesByName: attributesByName, effects: effects,
            volume: volume, bandwidth: bandwidth, groupID: groupID
        )
    }

    /// 更新无人机数量和激活数量
    func updateDroneQuantity(typeId: Int, quantity: Int, activeCount: Int) {
        // 检查是否存在该类型的无人机
        guard let index = simulationInput.drones.firstIndex(where: { $0.typeId == typeId }) else {
            return
        }

        // 获取当前无人机
        let drone = simulationInput.drones[index]

        // 创建更新后的无人机对象（保留突变数据）
        var updatedDrone = SimDrone(
            typeId: drone.typeId,
            attributes: drone.attributes,
            attributesByName: drone.attributesByName,
            effects: drone.effects,
            quantity: quantity,
            activeCount: activeCount,
            groupID: drone.groupID,
            requiredSkills: drone.requiredSkills,
            name: drone.name,
            iconFileName: drone.iconFileName
        )
        // 保留突变数据（包括显示信息）
        updatedDrone.selectedMutaplasmidID = drone.selectedMutaplasmidID
        updatedDrone.mutatedAttributes = drone.mutatedAttributes
        updatedDrone.mutatedTypeId = drone.mutatedTypeId
        updatedDrone.mutatedName = drone.mutatedName
        updatedDrone.mutatedIconFileName = drone.mutatedIconFileName

        // 更新无人机列表
        simulationInput.drones[index] = updatedDrone

        // 移除重新计算属性的调用，只更新无人机相关的UI
        // calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("更新无人机成功: \(drone.name), 数量: \(quantity), 激活数量: \(activeCount)")
    }

    /// 更新无人机的突变数据
    func updateDroneMutation(typeId: Int, mutaplasmidID: Int?, mutatedAttributes: [Int: Double]) {
        guard let index = simulationInput.drones.firstIndex(where: { $0.typeId == typeId }) else {
            Logger.warning("更新无人机突变数据失败: 未找到无人机 typeId \(typeId)")
            return
        }

        let currentDrone = simulationInput.drones[index]

        // 查询突变后的typeID、名称和图标
        var mutatedTypeId: Int? = nil
        var mutatedName: String? = nil
        var mutatedIconFileName: String? = nil

        if let mutaplasmidID = mutaplasmidID {
            if let resultingTypeId = databaseManager.getMutatedTypeID(
                applicableTypeID: currentDrone.typeId,
                mutaplasmidID: mutaplasmidID
            ) {
                mutatedTypeId = resultingTypeId

                // 查询突变后的名称和图标
                let typeQuery = "SELECT name, icon_filename FROM types WHERE type_id = ?"
                if case let .success(rows) = databaseManager.executeQuery(
                    typeQuery, parameters: [resultingTypeId]
                ), let row = rows.first {
                    mutatedName = row["name"] as? String
                    mutatedIconFileName = row["icon_filename"] as? String
                }
            }
        }

        var updatedDrone = currentDrone
        updatedDrone.selectedMutaplasmidID = mutaplasmidID
        updatedDrone.mutatedAttributes = mutatedAttributes
        updatedDrone.mutatedTypeId = mutatedTypeId
        updatedDrone.mutatedName = mutatedName
        updatedDrone.mutatedIconFileName = mutatedIconFileName

        simulationInput.drones[index] = updatedDrone

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 重新计算属性（突变会影响属性值）
        Logger.info("更新无人机突变数据，重新计算属性")
        calculateAttributes()

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("更新无人机突变数据成功: \(currentDrone.name), 突变质体ID: \(mutaplasmidID?.description ?? "nil"), 突变属性数量: \(mutatedAttributes.count)")
    }

    /// 替换无人机（保持数量和激活数量）
    func replaceDrone(oldTypeId: Int, newTypeId: Int) {
        // 检查是否存在旧无人机
        guard let index = simulationInput.drones.firstIndex(where: { $0.typeId == oldTypeId })
        else {
            return
        }

        // 获取旧无人机信息
        let oldDrone = simulationInput.drones[index]
        let oldQuantity = oldDrone.quantity
        let oldActiveCount = oldDrone.activeCount

        // 如果新旧ID相同，无需替换
        if oldTypeId == newTypeId {
            return
        }

        // 检查新类型无人机是否已存在
        if let existingIndex = simulationInput.drones.firstIndex(where: { $0.typeId == newTypeId }) {
            // 已存在新类型无人机，将旧的数量合并到新的上
            let existingDrone = simulationInput.drones[existingIndex]
            let newQuantity = existingDrone.quantity + oldQuantity
            let newActiveCount = existingDrone.activeCount + oldActiveCount

            // 创建更新后的无人机对象（保留突变数据）
            var updatedDrone = SimDrone(
                typeId: existingDrone.typeId,
                attributes: existingDrone.attributes,
                attributesByName: existingDrone.attributesByName,
                effects: existingDrone.effects,
                quantity: newQuantity,
                activeCount: newActiveCount,
                groupID: existingDrone.groupID,
                requiredSkills: existingDrone.requiredSkills,
                name: existingDrone.name,
                iconFileName: existingDrone.iconFileName
            )
            // 保留突变数据（包括显示信息）
            updatedDrone.selectedMutaplasmidID = existingDrone.selectedMutaplasmidID
            updatedDrone.mutatedAttributes = existingDrone.mutatedAttributes
            updatedDrone.mutatedTypeId = existingDrone.mutatedTypeId
            updatedDrone.mutatedName = existingDrone.mutatedName
            updatedDrone.mutatedIconFileName = existingDrone.mutatedIconFileName

            // 更新已存在的无人机
            simulationInput.drones[existingIndex] = updatedDrone

            // 移除旧无人机
            simulationInput.drones.remove(at: index)
        } else {
            // 获取新无人机信息
            guard let newDroneInfo = getDroneInfo(typeId: newTypeId) else {
                Logger.error("无法获取新无人机信息: \(newTypeId)")
                return
            }

            // 查询新无人机的名称和图标
            let query = "SELECT name, icon_filename FROM types WHERE type_id = ?"
            var newName = "无人机"
            var newIconFileName: String? = nil

            if case let .success(rows) = databaseManager.executeQuery(
                query, parameters: [newTypeId]
            ),
                let row = rows.first
            {
                if let name = row["name"] as? String {
                    newName = name
                }
                if let iconFileName = row["icon_filename"] as? String {
                    newIconFileName = iconFileName
                }
            }

            // 创建新无人机（无人机更换后清除突变信息）
            var newDrone = SimDrone(
                typeId: newTypeId,
                attributes: newDroneInfo.attributes,
                attributesByName: newDroneInfo.attributesByName,
                effects: newDroneInfo.effects,
                quantity: oldQuantity,
                activeCount: oldActiveCount,
                groupID: newDroneInfo.groupID,
                requiredSkills: FitConvert.extractRequiredSkills(
                    attributes: newDroneInfo.attributes),
                name: newName,
                iconFileName: newIconFileName
            )
            // 清除突变信息
            newDrone.selectedMutaplasmidID = nil
            newDrone.mutatedAttributes = [:]

            // 替换无人机
            simulationInput.drones[index] = newDrone
        }

        // 重新计算属性
        Logger.info("替换无人机，重新计算属性")
        calculateAttributes()

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("替换无人机成功: 从ID \(oldTypeId) 到 ID \(newTypeId)")
    }

    // MARK: - 货舱相关方法

    /// 添加物品到货舱
    func addCargoItem(typeId: Int, name: String, iconFileName: String?, quantity: Int) {
        // 获取物品体积
        let volume = getItemVolume(typeId: typeId)

        // 检查是否已存在相同类型的物品
        if let index = simulationInput.cargo.items.firstIndex(where: { $0.typeId == typeId }) {
            // 更新现有物品数量
            let existingItem = simulationInput.cargo.items[index]
            let newQuantity = existingItem.quantity + quantity

            // 创建更新后的物品对象
            let updatedItem = SimCargoItem(
                typeId: existingItem.typeId,
                quantity: newQuantity,
                volume: existingItem.volume,
                name: existingItem.name,
                iconFileName: existingItem.iconFileName
            )

            // 更新物品列表
            var updatedItems = simulationInput.cargo.items
            updatedItems[index] = updatedItem

            // 直接更新货舱，不调用updateCargo来避免重新计算属性
            simulationInput.cargo = SimCargo(items: updatedItems)
        } else {
            // 添加新的物品
            let newItem = SimCargoItem(
                typeId: typeId,
                quantity: quantity,
                volume: volume,
                name: name,
                iconFileName: iconFileName
            )

            // 添加到物品列表
            var updatedItems = simulationInput.cargo.items
            updatedItems.append(newItem)

            // 直接更新货舱，不调用updateCargo来避免重新计算属性
            simulationInput.cargo = SimCargo(items: updatedItems)
        }

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("添加货舱物品成功: \(name), 数量: \(quantity)")
    }

    /// 移除指定类型的货舱物品
    func removeCargoItem(typeId: Int) {
        // 检查是否存在该类型的物品
        let initialCount = simulationInput.cargo.items.count

        // 移除指定类型的物品
        var updatedItems = simulationInput.cargo.items
        updatedItems.removeAll(where: { $0.typeId == typeId })

        // 如果数量没变，说明没有移除任何物品
        if updatedItems.count == initialCount {
            return
        }

        // 直接更新货舱，不调用updateCargo来避免重新计算属性
        simulationInput.cargo = SimCargo(items: updatedItems)

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("移除货舱物品成功，类型ID: \(typeId)")
    }

    /// 移除指定索引的货舱物品
    func removeCargoItem(at index: Int) {
        // 检查索引是否有效
        guard index >= 0, index < simulationInput.cargo.items.count else {
            return
        }

        // 移除指定索引的物品
        var updatedItems = simulationInput.cargo.items
        updatedItems.remove(at: index)

        // 直接更新货舱，不调用updateCargo来避免重新计算属性
        simulationInput.cargo = SimCargo(items: updatedItems)

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("移除索引为\(index)的货舱物品成功")
    }

    /// 更新货舱物品数量
    func updateCargoItemQuantity(typeId: Int, quantity: Int) {
        // 检查是否存在该类型的物品
        guard let index = simulationInput.cargo.items.firstIndex(where: { $0.typeId == typeId })
        else {
            return
        }

        // 获取当前物品
        let item = simulationInput.cargo.items[index]

        // 如果数量为0或负数，移除物品
        if quantity <= 0 {
            removeCargoItem(typeId: typeId)
            return
        }

        // 创建更新后的物品对象
        let updatedItem = SimCargoItem(
            typeId: item.typeId,
            quantity: quantity,
            volume: item.volume,
            name: item.name,
            iconFileName: item.iconFileName
        )

        // 更新物品列表
        var updatedItems = simulationInput.cargo.items
        updatedItems[index] = updatedItem

        // 直接更新货舱，不调用updateCargo来避免重新计算属性
        simulationInput.cargo = SimCargo(items: updatedItems)

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 通知UI更新
        objectWillChange.send()

        // 自动保存配置
        saveConfiguration()

        Logger.info("更新货舱物品成功: \(item.name), 数量: \(quantity)")
    }

    /// 获取物品体积
    private func getItemVolume(typeId: Int) -> Double {
        // 查询物品体积
        let volumeQuery = "SELECT volume FROM types WHERE type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(volumeQuery, parameters: [typeId]) {
            if let row = rows.first, let volume = row["volume"] as? Double, volume > 0 {
                return volume
            }
        }

        // 如果查询失败或体积为0，返回默认值
        return 1.0
    }

    // MARK: - 私有辅助方法

    /// 检查指定模块是否可以装载指定弹药
    func canLoadCharge(moduleTypeId: Int, chargeTypeId: Int) -> Bool {
        // 获取模块可装载的弹药组
        var chargeGroupIDs: [Int] = []
        var chargeSize: Double? = nil

        // 获取模块的所有属性
        let attrQuery = """
            SELECT ta.attribute_id, ta.value, da.name 
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
            WHERE ta.type_id = ?
        """

        // 执行查询获取模块属性
        if case let .success(rows) = databaseManager.executeQuery(
            attrQuery, parameters: [moduleTypeId]
        ) {
            for row in rows {
                if let name = row["name"] as? String,
                   let value = row["value"] as? Double
                {
                    // 收集chargeGroup属性
                    if name.hasPrefix("chargeGroup") && value > 0 {
                        chargeGroupIDs.append(Int(value))
                    }

                    // 收集chargeSize属性
                    if name == "chargeSize" {
                        chargeSize = value
                    }
                }
            }
        }

        // 如果没有弹药组，表示不能装载弹药
        if chargeGroupIDs.isEmpty {
            return false
        }

        // 获取弹药的组ID和大小
        var chargeGroupID = 0
        var chargeSizeValue: Double? = nil

        // 查询弹药组ID
        let chargeGroupQuery = "SELECT groupID FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(
            chargeGroupQuery, parameters: [chargeTypeId]
        ),
            let row = rows.first,
            let groupID = row["groupID"] as? Int
        {
            chargeGroupID = groupID
        }

        // 查询弹药大小
        let chargeSizeQuery = """
            SELECT ta.value 
            FROM typeAttributes ta
            JOIN dogmaAttributes dat ON ta.attribute_id = dat.attribute_id
            WHERE ta.type_id = ? AND dat.name = 'chargeSize'
        """

        if case let .success(rows) = databaseManager.executeQuery(
            chargeSizeQuery, parameters: [chargeTypeId]
        ),
            let row = rows.first,
            let value = row["value"] as? Double
        {
            chargeSizeValue = value
        }

        // 检查弹药组是否匹配
        let groupMatches = chargeGroupIDs.contains(chargeGroupID)

        // 检查弹药大小是否匹配
        let sizeMatches: Bool
        if let moduleSize = chargeSize, let ammoSize = chargeSizeValue {
            sizeMatches = moduleSize == ammoSize
        } else {
            // 如果没有大小限制，则认为大小匹配
            sizeMatches = true
        }

        // 同时满足组和大小匹配才能装载
        return groupMatches && sizeMatches
    }

    /// 从用户偏好设置中获取技能数据
    static func getSkillsFromPreferences() -> [Int: Int] {
        // 从UserDefaults获取当前选择的技能模式
        let skillsMode =
            UserDefaults.standard.string(forKey: "skillsModePreference") ?? "current_char"

        // 根据技能模式获取对应的技能类型
        var skillType: CharacterSkillsType

        switch skillsMode {
        case "all5":
            skillType = .all5
        case "all4":
            skillType = .all4
        case "all3":
            skillType = .all3
        case "all2":
            skillType = .all2
        case "all1":
            skillType = .all1
        case "all0":
            skillType = .all0
        case "character":
            // 指定角色的情况，获取保存的角色ID
            let charId = UserDefaults.standard.integer(forKey: "selectedSkillCharacterId")

            // 【修复3】检查角色是否还在已登录列表中，且 token 未过期
            if charId != 0,
               let characterAuth = EVELogin.shared.getCharacterByID(charId),
               !characterAuth.character.refreshTokenExpired
            {
                // 角色存在且 token 有效
                skillType = .character(charId)
                Logger.info("【getSkillsFromPreferences】使用指定角色技能 - 角色ID: \(charId)")
            } else {
                // 角色不存在、已删除或 token 已过期
                if charId != 0 {
                    if EVELogin.shared.getCharacterByID(charId) == nil {
                        Logger.warning("【getSkillsFromPreferences】角色不存在或已删除 (ID: \(charId))，自动切换为 all5")
                    } else {
                        Logger.warning("【getSkillsFromPreferences】角色 token 已过期 (ID: \(charId))，自动切换为 all5 避免阻塞主线程")
                    }
                }
                // 自动修正为 all5，避免阻塞主线程等待网络请求
                UserDefaults.standard.removeObject(forKey: "selectedSkillCharacterId")
                UserDefaults.standard.set("all5", forKey: "skillsModePreference")
                UserDefaults.standard.synchronize()
                skillType = .all5
            }
        default:
            // 默认为当前角色
            skillType = .current_char
        }

        // 获取技能数据
        let skills = CharacterSkillsUtils.getCharacterSkills(type: skillType)
        Logger.info("从用户偏好设置加载技能数据，模式: \(skillsMode)，技能数量: \(skills.count)")

        return skills
    }

    /// 获取无人机的分组ID
    func getDroneGroupID(typeId: Int) -> Int {
        let query = "SELECT groupID FROM types WHERE type_id = ?"
        var groupID = 0

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeId]) {
            if let row = rows.first, let id = row["groupID"] as? Int {
                groupID = id
            }
        }

        return groupID
    }

    // MARK: - 舰载机相关方法

    /// 根据ID获取数据库物品信息
    func getDatabaseItemInfo(typeId: Int) -> DatabaseListItem? {
        let whereClause = "t.type_id = ?"
        let results = databaseManager.loadMarketItems(
            whereClause: whereClause, parameters: [typeId], limit: 1
        )
        return results.first
    }

    /// 获取舰载机信息
    func getFighterInfo(typeId: Int) -> (typeId: Int, groupID: Int?)? {
        let query = "SELECT type_id, groupID FROM types WHERE type_id = ? LIMIT 1"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let id = row["type_id"] as? Int
        {
            let groupID = row["groupID"] as? Int

            return (typeId: id, groupID: groupID)
        }

        return nil
    }

    /// 添加或更新舰载机
    func addOrUpdateFighter(_ fighter: SimFighterSquad, name: String, iconFileName: String?) {
        // 获取舰载机的完整信息（包括属性和效果）
        let fighterInfo = getFighterInfo(typeId: fighter.typeId)

        // 获取舰载机的基础属性
        let (attributes, attributesByName) = loadFighterBaseAttributes(typeId: fighter.typeId)

        // 创建包含完整属性的舰载机对象
        let updatedFighter = SimFighterSquad(
            typeId: fighter.typeId,
            attributes: attributes,
            attributesByName: attributesByName,
            effects: [], // 效果将在属性计算过程中加载
            quantity: fighter.quantity,
            tubeId: fighter.tubeId,
            groupID: fighterInfo?.groupID ?? 0,
            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes),
            name: name,
            iconFileName: iconFileName
        )

        // 检查是否已存在该发射管中的舰载机
        if let fighters = simulationInput.fighters,
           let index = fighters.firstIndex(where: { $0.tubeId == fighter.tubeId })
        {
            // 更新现有舰载机
            var updatedFighters = fighters
            updatedFighters[index] = updatedFighter
            simulationInput.fighters = updatedFighters
        } else {
            // 添加新舰载机
            var fighters = simulationInput.fighters ?? []
            fighters.append(updatedFighter)
            simulationInput.fighters = fighters
        }

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 重新计算属性
        calculateAttributes()

        // 自动保存配置
        saveConfiguration()

        Logger.info("添加/更新舰载机: typeId=\(fighter.typeId), tubeId=\(fighter.tubeId)")
    }

    /// 移除舰载机
    func removeFighter(tubeId: Int) {
        guard let fighters = simulationInput.fighters else { return }

        Logger.info("开始移除舰载机: tubeId=\(tubeId), 当前舰载机数量: \(fighters.count)")

        // 筛选出要保留的舰载机（移除指定tubeId的舰载机）
        let updatedFighters = fighters.filter { $0.tubeId != tubeId }

        Logger.info("过滤后舰载机数量: \(updatedFighters.count)")

        // 如果移除后列表为空，则设置为nil
        if updatedFighters.isEmpty {
            simulationInput.fighters = nil
            Logger.info("所有舰载机都被移除，fighters设置为nil")
        } else {
            simulationInput.fighters = updatedFighters
        }

        // 标记有未保存的更改
        hasUnsavedChanges = true

        Logger.info("开始重新计算属性...")
        // 重新计算属性
        calculateAttributes()

        Logger.info("开始保存配置...")
        // 自动保存配置
        saveConfiguration()

        Logger.info("舰载机移除完成: tubeId=\(tubeId)")
    }

    // MARK: - 舰载机相关属性

    // 舰载机属性计算结果
    var fighterAttributes:
        (
            light: (used: Int, total: Int), heavy: (used: Int, total: Int),
            support: (used: Int, total: Int)
        )
    {
        // 获取各类型舰载机槽位数量
        let lightTotal = Int(simulationInput.ship.baseAttributesByName["fighterLightSlots"] ?? 0)
        let heavyTotal = Int(simulationInput.ship.baseAttributesByName["fighterHeavySlots"] ?? 0)
        let supportTotal = Int(
            simulationInput.ship.baseAttributesByName["fighterSupportSlots"] ?? 0)

        // 获取飞船总的舰载机管数
        let totalFighterTubes = Int(simulationInput.ship.baseAttributesByName["fighterTubes"] ?? 0)

        // 初始化使用数量
        var lightUsed = 0
        var heavyUsed = 0
        var supportUsed = 0

        // 自动检查和清理超额的舰载机
        if let fighters = simulationInput.fighters, totalFighterTubes > 0 {
            var validFighters: [SimFighterSquad] = []
            var currentCount = 0

            for fighter in fighters {
                // 修改此处，直接使用tubeId而不是进行可选绑定
                let tubeId = fighter.tubeId
                // 如果超过总管数限制，跳过该舰载机
                if currentCount >= totalFighterTubes {
                    continue
                }

                validFighters.append(fighter)
                currentCount += 1

                // 统计各类型舰载机数量
                if tubeId >= 0, tubeId < 100 {
                    // 轻型舰载机
                    lightUsed += 1
                } else if tubeId >= 100, tubeId < 200 {
                    // 重型舰载机
                    heavyUsed += 1
                } else if tubeId >= 200 {
                    // 辅助舰载机
                    supportUsed += 1
                }
            }

            // 如果有舰载机被移除，更新simulationInput
            if fighters.count != validFighters.count {
                Logger.info("自动移除了 \(fighters.count - validFighters.count) 个超额舰载机")
                simulationInput.fighters = validFighters.isEmpty ? nil : validFighters

                // 异步保存配置，避免在计算属性中同步保存
                DispatchQueue.main.async { [weak self] in
                    self?.saveConfiguration()
                }
            }
        } else {
            // 统计舰载机数量（无需清理的情况）
            if let fighters = simulationInput.fighters {
                for fighter in fighters {
                    // 修改此处，直接使用tubeId而不是进行可选绑定
                    let tubeId = fighter.tubeId
                    if tubeId >= 0, tubeId < 100 {
                        // 轻型舰载机
                        lightUsed += 1
                    } else if tubeId >= 100, tubeId < 200 {
                        // 重型舰载机
                        heavyUsed += 1
                    } else if tubeId >= 200 {
                        // 辅助舰载机
                        supportUsed += 1
                    }
                }
            }
        }

        return (
            light: (used: lightUsed, total: lightTotal),
            heavy: (used: heavyUsed, total: heavyTotal),
            support: (used: supportUsed, total: supportTotal)
        )
    }

    /// 更新舰载机数量
    func updateFighterQuantity(tubeId: Int, quantity: Int) {
        guard let fighters = simulationInput.fighters,
              let index = fighters.firstIndex(where: { $0.tubeId == tubeId })
        else { return }

        // 获取现有舰载机
        let fighter = fighters[index]

        // 如果数量没有变化，直接返回
        if fighter.quantity == quantity {
            return
        }

        // 创建更新后的舰载机对象
        let updatedFighter = SimFighterSquad(
            typeId: fighter.typeId,
            attributes: fighter.attributes,
            attributesByName: fighter.attributesByName,
            effects: fighter.effects,
            quantity: quantity,
            tubeId: fighter.tubeId,
            groupID: fighter.groupID,
            requiredSkills: fighter.requiredSkills,
            name: fighter.name,
            iconFileName: fighter.iconFileName
        )

        // 更新舰载机列表
        var updatedFighters = fighters
        updatedFighters[index] = updatedFighter
        simulationInput.fighters = updatedFighters

        // 标记有未保存的更改
        hasUnsavedChanges = true

        // 仅记录日志，不重新计算属性和保存配置
        // 这部分会在舰载机设置页面关闭时执行
        Logger.info("更新舰载机数量: typeId=\(fighter.typeId), tubeId=\(fighter.tubeId), 数量=\(quantity)")
    }

    /// 加载舰载机的基础属性
    private func loadFighterBaseAttributes(typeId: Int) -> ([Int: Double], [String: Double]) {
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]

        // 查询舰载机的基础属性
        let query = """
            SELECT ta.attribute_id, ta.value, da.name as attribute_name
            FROM typeAttributes ta
            LEFT JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id
            WHERE ta.type_id = ?
        """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeId]) {
            for row in rows {
                if let attributeId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double
                {
                    // 添加到ID映射字典
                    attributes[attributeId] = value

                    // 如果有属性名，添加到名称映射字典
                    if let attributeName = row["attribute_name"] as? String {
                        attributesByName[attributeName] = value
                    }
                }
            }
        }

        return (attributes, attributesByName)
    }
}
