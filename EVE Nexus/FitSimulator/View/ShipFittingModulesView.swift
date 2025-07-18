import SwiftUI

// 添加槽位类型枚举
enum FittingSlotType: String, CaseIterable {
    case subSystemSlots = "SubSystemSlots"
    case hiSlots = "HiSlots"
    case medSlots = "MedSlots"
    case loSlots = "LoSlots"
    case rigSlots = "RigSlots"
    case t3dModeSlot = "T3DModeSlot"
    
    var localizedName: String {
        switch self {
        case .subSystemSlots:
            return NSLocalizedString("Location_Flag_SubSystemSlots", comment: "")
        case .hiSlots:
            return NSLocalizedString("Location_Flag_HiSlots", comment: "")
        case .medSlots:
            return NSLocalizedString("Location_Flag_MedSlots", comment: "")
        case .loSlots:
            return NSLocalizedString("Location_Flag_LoSlots", comment: "")
        case .rigSlots:
            return NSLocalizedString("Location_Flag_RigSlots", comment: "")
        case .t3dModeSlot:
            return NSLocalizedString("Location_Flag_T3DModeSlot", comment: "")
        }
    }
    
    // 获取指定索引的槽位flag标识
    func getSlotFlag(index: Int) -> FittingFlag {
        switch self {
        case .hiSlots:
            switch index {
            case 0: return .hiSlot0
            case 1: return .hiSlot1
            case 2: return .hiSlot2
            case 3: return .hiSlot3
            case 4: return .hiSlot4
            case 5: return .hiSlot5
            case 6: return .hiSlot6
            case 7: return .hiSlot7
            default: return .invalid
            }
        case .medSlots:
            switch index {
            case 0: return .medSlot0
            case 1: return .medSlot1
            case 2: return .medSlot2
            case 3: return .medSlot3
            case 4: return .medSlot4
            case 5: return .medSlot5
            case 6: return .medSlot6
            case 7: return .medSlot7
            default: return .invalid
            }
        case .loSlots:
            switch index {
            case 0: return .loSlot0
            case 1: return .loSlot1
            case 2: return .loSlot2
            case 3: return .loSlot3
            case 4: return .loSlot4
            case 5: return .loSlot5
            case 6: return .loSlot6
            case 7: return .loSlot7
            default: return .invalid
            }
        case .rigSlots:
            switch index {
            case 0: return .rigSlot0
            case 1: return .rigSlot1
            case 2: return .rigSlot2
            default: return .invalid
            }
        case .subSystemSlots:
            switch index {
            case 0: return .subSystemSlot0
            case 1: return .subSystemSlot1
            case 2: return .subSystemSlot2
            case 3: return .subSystemSlot3
            default: return .invalid
            }
        case .t3dModeSlot:
            return .t3dModeSlot0 // T3D模式的flag
        }
    }
}

// 装备分组数据结构
struct ModuleGroup {
    let typeId: Int
    let name: String
    let iconFileName: String?
    var modules: [SimModule]
    let emptySlots: [FittingFlag]
    
    var totalCount: Int {
        return modules.count + emptySlots.count
    }
}

struct ShipFittingModulesView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    
    // 为各类型选择器创建专用的状态对象
    @StateObject private var moduleSettingsState = SlotState()
    @StateObject private var hiSlotSelectorState = SlotState()
    @StateObject private var medSlotSelectorState = SlotState()
    @StateObject private var lowSlotSelectorState = SlotState()
    @StateObject private var rigSlotSelectorState = SlotState()
    @StateObject private var subSysSlotSelectorState = SlotState()
    @StateObject private var t3dModeSelectorState = SlotState()
    
    // 辅助函数：获取用于显示的模块（只使用计算后的数据）
    private func getDisplayModule(for flag: FittingFlag) -> SimModule? {
        // 只使用计算后的模块数据进行显示
        guard let outputModules = viewModel.simulationOutput?.modules,
              let outputModule = outputModules.first(where: { $0.flag == flag }) else {
            return nil
        }
        
        // 从输出模块创建显示用的SimModule对象
        return SimModule(
            instanceId: outputModule.instanceId,
            typeId: outputModule.typeId,
            attributes: outputModule.attributes,
            attributesByName: outputModule.attributesByName,
            effects: outputModule.effects,
            groupID: outputModule.groupID,
            status: outputModule.status,
            charge: outputModule.charge.map { outputCharge in
                SimCharge(
                    typeId: outputCharge.typeId,
                    attributes: outputCharge.attributes,
                    attributesByName: outputCharge.attributesByName,
                    effects: outputCharge.effects,
                    groupID: outputCharge.groupID,
                    chargeQuantity: outputCharge.chargeQuantity,
                    requiredSkills: outputCharge.requiredSkills,
                    name: outputCharge.name,
                    iconFileName: outputCharge.iconFileName
                )
            },
            flag: outputModule.flag,
            quantity: outputModule.quantity,
            name: outputModule.name,
            iconFileName: outputModule.iconFileName,
            requiredSkills: FitConvert.extractRequiredSkills(attributes: outputModule.attributes)
        )
    }
    
    // 计算动态槽位数（考虑子系统修饰器）
    private func calculateDynamicSlots() -> (hiSlots: Int, medSlots: Int, lowSlots: Int) {
        // 获取基础槽位数 - 只使用计算后的数据
        guard let outputShip = viewModel.simulationOutput?.ship else {
            // 如果没有计算后的数据，返回默认值
            return (hiSlots: 0, medSlots: 0, lowSlots: 0)
        }
        
        let baseHiSlots = Int(outputShip.attributesByName["hiSlots"] ?? 0)
        let baseMedSlots = Int(outputShip.attributesByName["medSlots"] ?? 0)
        let baseLowSlots = Int(outputShip.attributesByName["lowSlots"] ?? 0)
        Logger.info("动态槽位计算结果 - 高槽: \(baseHiSlots), 中槽: \(baseMedSlots), 低槽: \(baseLowSlots)")
        
        return (hiSlots: baseHiSlots, medSlots: baseMedSlots, lowSlots: baseLowSlots)
    }
    
    // 获取模块状态图标
    private func getStatusIcon(status: Int) -> some View {
        switch status {
        case 0:
            return IconManager.shared.loadImage(for: "offline")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case 1:
            return IconManager.shared.loadImage(for: "online")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case 2:
            return IconManager.shared.loadImage(for: "active")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case 3:
            return IconManager.shared.loadImage(for: "overheating")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        default:
            return IconManager.shared.loadImage(for: "offline")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
    }
    
    // 统一所有打开选择器的函数
    private func openHiSlotSelector(flag: FittingFlag) {
        hiSlotSelectorState.slotFlag = flag
        Logger.info("打开高槽装备选择器，槽位标识：\(flag.rawValue)")
    }
    
    private func openMedSlotSelector(flag: FittingFlag) {
        medSlotSelectorState.slotFlag = flag
        Logger.info("打开中槽装备选择器，槽位标识：\(flag.rawValue)")
    }
    
    private func openLowSlotSelector(flag: FittingFlag) {
        lowSlotSelectorState.slotFlag = flag
        Logger.info("打开低槽装备选择器，槽位标识：\(flag.rawValue)")
    }
    
    private func openRigSlotSelector(flag: FittingFlag) {
        rigSlotSelectorState.slotFlag = flag
        Logger.info("打开改装槽装备选择器，槽位标识：\(flag.rawValue)")
    }
    
    private func openSubSysSlotSelector(flag: FittingFlag) {
        subSysSlotSelectorState.slotFlag = flag
        Logger.info("打开子系统选择器，槽位标识：\(flag.rawValue)")
    }
    
    private func openT3DModeSelector(flag: FittingFlag) {
        t3dModeSelectorState.slotFlag = flag
        Logger.info("打开T3D模式选择器，槽位标识：\(flag.rawValue)")
    }
    
    // 打开装备设置视图
    private func openModuleSettings(flag: FittingFlag, moduleName: String) {
        moduleSettingsState.slotFlag = flag
        Logger.info("打开装备设置，槽位: \(flag.rawValue), 装备: \(moduleName)")
    }
    
    // 获取指定槽位类型的模块分组
    private func getModuleGroups(for slotType: FittingSlotType, totalSlots: Int) -> [ModuleGroup] {
        var groups: [Int: ModuleGroup] = [:]
        var emptySlots: [FittingFlag] = []
        var firstAppearanceOrder: [Int: Int] = [:] // 记录每个typeId的首次出现顺序
        
        // 收集所有槽位的模块和空槽位，同时记录首次出现顺序
        for index in 0..<totalSlots {
            let slotFlag = slotType.getSlotFlag(index: index)
            
            // 使用辅助函数获取显示模块
            if let installedModule = getDisplayModule(for: slotFlag) {
                // 已安装模块
                let typeId = installedModule.typeId
                
                // 记录首次出现的顺序（如果还没有记录过）
                if firstAppearanceOrder[typeId] == nil {
                    firstAppearanceOrder[typeId] = index
                }
                
                if var group = groups[typeId] {
                    group.modules.append(installedModule)
                    groups[typeId] = group
                } else {
                    groups[typeId] = ModuleGroup(
                        typeId: typeId,
                        name: installedModule.name,
                        iconFileName: installedModule.iconFileName,
                        modules: [installedModule],
                        emptySlots: []
                    )
                }
            } else {
                // 空槽位
                emptySlots.append(slotFlag)
            }
        }
        
        // 如果有空槽位，创建一个特殊的空槽位组
        var result = Array(groups.values)
        if !emptySlots.isEmpty {
            result.append(ModuleGroup(
                typeId: -1, // 特殊标识空槽位
                name: slotType.localizedName,
                iconFileName: nil,
                modules: [],
                emptySlots: emptySlots
            ))
        }
        
        return result.sorted { first, second in
            // 空槽位组（typeId = -1）排在最后
            if first.typeId == -1 && second.typeId != -1 {
                return false // first 排在后面
            }
            if first.typeId != -1 && second.typeId == -1 {
                return true // first 排在前面
            }
            
            // 其他情况按首次出现顺序排列
            let firstOrder = firstAppearanceOrder[first.typeId] ?? Int.max
            let secondOrder = firstAppearanceOrder[second.typeId] ?? Int.max
            return firstOrder < secondOrder
        }
    }
    
    // 处理折叠模块组的点击事件
    private func handleGroupTap(group: ModuleGroup, slotType: FittingSlotType) {
        if group.typeId == -1 {
            // 空槽位组，打开选择器
            if let firstEmptySlot = group.emptySlots.first {
                switch slotType {
                case .hiSlots:
                    openHiSlotSelector(flag: firstEmptySlot)
                case .medSlots:
                    openMedSlotSelector(flag: firstEmptySlot)
                case .loSlots:
                    openLowSlotSelector(flag: firstEmptySlot)
                case .rigSlots:
                    openRigSlotSelector(flag: firstEmptySlot)
                default:
                    break
                }
            }
        } else {
            // 已安装模块组，打开设置页面
            if let firstModule = group.modules.first {
                openModuleSettings(flag: firstModule.flag!, moduleName: firstModule.name)
            }
        }
    }
    
    // 批量安装装备到空槽位（优化版本，只在最后计算一次属性）
    private func installModuleToEmptySlots(typeId: Int, emptySlots: [FittingFlag]) {
        Logger.info("开始批量安装装备到空槽位: \(emptySlots.count) 个槽位，装备ID: \(typeId)")
        
        // 从数据库加载装备属性和效果（只查询一次）
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]
        var effects: [Int] = []
        var groupId: Int = 0
        var model_name: String = ""
        var model_iconFilename: String = ""
        var volume: Double = 0
        
        // 查询装备属性
        let attrQuery = """
            SELECT ta.attribute_id, ta.value, da.name 
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
            WHERE ta.type_id = ?
        """
        
        if case let .success(rows) = viewModel.databaseManager.executeQuery(attrQuery, parameters: [typeId]) {
            for row in rows {
                if let attrId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double,
                   let name = row["name"] as? String {
                    attributes[attrId] = value
                    attributesByName[name] = value
                }
            }
        }
        
        // 查询装备效果
        let effectQuery = "SELECT effect_id FROM typeEffects WHERE type_id = ?"
        if case let .success(rows) = viewModel.databaseManager.executeQuery(effectQuery, parameters: [typeId]) {
            for row in rows {
                if let effectId = row["effect_id"] as? Int {
                    effects.append(effectId)
                }
            }
        }
        
        // 查询装备基本信息，包括capacity
        let infoQuery = "SELECT name, icon_filename, groupID, volume, capacity FROM types WHERE type_id = ?"
        if case let .success(rows) = viewModel.databaseManager.executeQuery(infoQuery, parameters: [typeId]),
           let row = rows.first {
            model_name = row["name"] as? String ?? ""
            model_iconFilename = row["icon_filename"] as? String ?? ""
            groupId = row["groupID"] as? Int ?? 0
            volume = row["volume"] as? Double ?? 0
            
            // 添加capacity到属性字典中（如果存在）
            if let capacity = row["capacity"] as? Double, capacity > 0 {
                attributes[38] = capacity
                attributesByName["capacity"] = capacity
                Logger.info("批量安装装备: \(model_name), capacity=\(capacity)")
            }
        }
        
        // 添加volume到属性字典中
        attributes[161] = volume
        attributesByName["volume"] = volume
        
        var successCount = 0
        var failedFlags: [FittingFlag] = []
        
        // 批量安装装备
        for flag in emptySlots {
            // 检查是否可以安装（使用已查询的数据）
            if canInstallModuleWithData(
                attributes: attributes,
                attributesByName: attributesByName,
                effects: effects,
                volume: volume,
                typeId: typeId,
                groupId: groupId,
                flag: flag
            ) {
                // 计算合适的默认状态
                let maxStatus = getMaxStatus(
                    itemEffects: effects,
                    itemAttributes: attributes,
                    databaseManager: viewModel.databaseManager
                )
                
                var moduleStatus: Int
                switch maxStatus {
                case 3: moduleStatus = 2 // 可超载，默认为激活状态
                case 2: moduleStatus = 2 // 可激活，默认为激活状态
                case 1: moduleStatus = 1 // 可在线，默认为在线状态
                default: moduleStatus = 0 // 默认为离线状态
                }
                
                // 考虑同组装备限制
                moduleStatus = setStatus(
                    itemAttributes: attributes,
                    itemAttributesName: attributesByName,
                    typeId: typeId,
                    typeGroupId: groupId,
                    currentModules: viewModel.simulationInput.modules,
                    currentStatus: moduleStatus,
                    maxStatus: maxStatus
                )
                
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
                
                // 添加到模块列表（不触发属性计算）
                viewModel.simulationInput.modules.append(newModule)
                successCount += 1
                Logger.info("批量安装装备到槽位: \(flag.rawValue), 装备: \(model_name)")
            } else {
                failedFlags.append(flag)
                Logger.warning("无法安装装备到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                break // 如果有一个槽位无法安装，停止后续安装
            }
        }
        
        // 只在最后计算一次属性
        if successCount > 0 {
            Logger.info("批量安装装备完成，重新计算属性")
            viewModel.calculateAttributes()
            
            // 标记有未保存的更改
            viewModel.hasUnsavedChanges = true
            
            // 自动保存配置
            viewModel.saveConfiguration()
        }
        
        Logger.info("批量安装装备完成，成功: \(successCount)/\(emptySlots.count)")
        
        if !failedFlags.isEmpty {
            Logger.warning("批量安装装备部分失败，失败的槽位: \(failedFlags.map { $0.rawValue })")
        }
    }
    
    // 使用已有数据检查是否可以安装模块（避免重复数据库查询）
    private func canInstallModuleWithData(
        attributes: [Int: Double],
        attributesByName: [String: Double],
        effects: [Int],
        volume: Double,
        typeId: Int,
        groupId: Int,
        flag: FittingFlag
    ) -> Bool {
        // 只计算实际需要的挂点数量 - 只使用计算后的数据
        guard let outputShip = viewModel.simulationOutput?.ship else {
            return false
        }
        
        let turretSlotsNum = Int(outputShip.attributesByName["turretSlotsLeft"] ?? 0)
        let launcherSlotsNum = Int(outputShip.attributesByName["launcherSlotsLeft"] ?? 0)
        
        // 使用canFit函数检查
        return canFit(
            simulationInput: viewModel.simulationInput,
            itemAttributes: attributes,
            itemAttributesName: attributesByName,
            itemEffects: effects,
            volume: volume,
            typeId: typeId,
            itemGroupID: groupId,
            databaseManager: viewModel.databaseManager,
            turretSlotsNum: turretSlotsNum,
            launcherSlotsNum: launcherSlotsNum
        )
    }

    // 获取相关模块（同类型的所有模块）
    private func getRelatedModules(for module: SimModule, flag: FittingFlag) -> [SimModule] {
        // 确定槽位类型
        let slotType = getSlotType(for: flag)
        
        // 检查是否处于折叠状态
        let isCollapsed = isSlotTypeCollapsed(slotType)
        
        if isCollapsed {
            // 折叠状态下，返回所有相同typeId的模块
            return viewModel.simulationInput.modules.filter { $0.typeId == module.typeId }
        } else {
            // 非折叠状态下，只返回当前模块
            return [module]
        }
    }
    
    // 判断是否应该应用批量操作
    private func shouldApplyBatchOperations(for module: SimModule) -> Bool {
        guard let flag = module.flag else { return false }
        let slotType = getSlotType(for: flag)
        return isSlotTypeCollapsed(slotType)
    }
    
    // 删除所有相关模块
    private func deleteAllRelatedModules(for module: SimModule) {
        let relatedModules = viewModel.simulationInput.modules.filter { $0.typeId == module.typeId }
        let flags = relatedModules.compactMap { $0.flag }
        
        // 批量删除所有相关模块
        batchRemoveModules(flags: flags)
        
        Logger.info("批量删除装备: \(relatedModules.count) 个 \(module.name)")
    }
    
    // 替换所有相关模块
    private func replaceAllRelatedModules(for module: SimModule, newTypeId: Int) {
        let relatedModules = viewModel.simulationInput.modules.filter { $0.typeId == module.typeId }
        let flags = relatedModules.compactMap { $0.flag }
        
        // 批量替换所有相关模块
        batchReplaceModules(flags: flags, newTypeId: newTypeId)
        
        Logger.info("批量替换装备: \(relatedModules.count) 个 \(module.name) -> 新装备ID: \(newTypeId)")
    }
    
    // 批量删除模块（优化版本，只在最后计算一次属性）
    private func batchRemoveModules(flags: [FittingFlag]) {
        Logger.info("开始批量删除模块: \(flags.count) 个")
        
        // 批量删除模块
        for flag in flags {
            viewModel.simulationInput.modules.removeAll(where: { $0.flag == flag })
            Logger.info("批量删除模块: 槽位 \(flag.rawValue)")
        }
        
        // 只在最后计算一次属性
        Logger.info("批量删除模块完成，重新计算属性")
        viewModel.calculateAttributes()
        
        // 标记有未保存的更改
        viewModel.hasUnsavedChanges = true
        
        // 自动保存配置
        viewModel.saveConfiguration()
        
        Logger.info("批量删除模块成功: \(flags.count) 个")
    }
    
    // 批量替换模块（优化版本，只在最后计算一次属性）
    private func batchReplaceModules(flags: [FittingFlag], newTypeId: Int) {
        Logger.info("开始批量替换模块: \(flags.count) 个，新装备ID: \(newTypeId)")
        
        var successCount = 0
        var failedFlags: [FittingFlag] = []
        
        // 从数据库加载新装备的属性和效果
        var attributes: [Int: Double] = [:]
        var attributesByName: [String: Double] = [:]
        var effects: [Int] = []
        var groupId: Int = 0
        var model_name: String = ""
        var model_iconFilename: String = ""
        var volume: Double = 0
        
        // 查询装备属性
        let attrQuery = """
            SELECT ta.attribute_id, ta.value, da.name 
            FROM typeAttributes ta 
            JOIN dogmaAttributes da ON ta.attribute_id = da.attribute_id 
            WHERE ta.type_id = ?
        """
        
        if case let .success(rows) = viewModel.databaseManager.executeQuery(attrQuery, parameters: [newTypeId]) {
            for row in rows {
                if let attrId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double,
                   let name = row["name"] as? String {
                    attributes[attrId] = value
                    attributesByName[name] = value
                }
            }
        }
        
        // 查询装备效果
        let effectQuery = "SELECT effect_id FROM typeEffects WHERE type_id = ?"
        if case let .success(rows) = viewModel.databaseManager.executeQuery(effectQuery, parameters: [newTypeId]) {
            for row in rows {
                if let effectId = row["effect_id"] as? Int {
                    effects.append(effectId)
                }
            }
        }
        
        // 查询装备基本信息
        let infoQuery = "SELECT name, icon_filename, groupID, volume FROM types WHERE type_id = ?"
        if case let .success(rows) = viewModel.databaseManager.executeQuery(infoQuery, parameters: [newTypeId]),
           let row = rows.first {
            model_name = row["name"] as? String ?? ""
            model_iconFilename = row["icon_filename"] as? String ?? ""
            groupId = row["groupID"] as? Int ?? 0
            volume = row["volume"] as? Double ?? 0
        }
        
        // 添加volume到属性字典中
        attributes[161] = volume
        attributesByName["volume"] = volume
        
        // 批量替换模块
        for flag in flags {
            if let index = viewModel.simulationInput.modules.firstIndex(where: { $0.flag == flag }) {
                let oldModule = viewModel.simulationInput.modules[index]
                
                // 计算合适的默认状态
                let maxStatus = getMaxStatus(
                    itemEffects: effects,
                    itemAttributes: attributes,
                    databaseManager: viewModel.databaseManager
                )
                
                var moduleStatus: Int
                switch maxStatus {
                case 3: moduleStatus = 2 // 可超载，默认为激活状态
                case 2: moduleStatus = 2 // 可激活，默认为激活状态
                case 1: moduleStatus = 1 // 可在线，默认为在线状态
                default: moduleStatus = 0 // 默认为离线状态
                }
                
                // 考虑同组装备限制
                moduleStatus = setStatus(
                    itemAttributes: attributes,
                    itemAttributesName: attributesByName,
                    typeId: newTypeId,
                    typeGroupId: groupId,
                    currentModules: viewModel.simulationInput.modules.filter { $0.flag != flag },
                    currentStatus: moduleStatus,
                    maxStatus: maxStatus
                )
                
                // 尝试保留原有装备的弹药
                if let oldCharge = oldModule.charge {
                    // 检查新装备是否可以装载旧弹药
                    let canLoadOldCharge = viewModel.canLoadCharge(moduleTypeId: newTypeId, chargeTypeId: oldCharge.typeId)
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
                        
                        // 创建带有更新弹药的新模块
                        let updatedModule = SimModule(
                            instanceId: oldModule.instanceId, // 保留原模块的instanceId
                            typeId: newTypeId,
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
                            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes)
                        )
                        
                        viewModel.simulationInput.modules[index] = updatedModule
                        Logger.info("批量替换装备并保留弹药: \(model_name) 到 \(flag.rawValue), 弹药: \(oldCharge.name), 重新计算数量: \(updatedChargeQuantity ?? 0)")
                    } else {
                        // 如果不能装载原有弹药，使用无弹药的模块
                        let newModule = SimModule(
                            instanceId: oldModule.instanceId, // 保留原模块的instanceId
                            typeId: newTypeId,
                            attributes: attributes,
                            attributesByName: attributesByName,
                            effects: effects,
                            groupID: groupId,
                            status: moduleStatus,
                            charge: nil, // 新模块暂时不保留弹药
                            flag: flag,
                            quantity: 1,
                            name: model_name,
                            iconFileName: model_iconFilename,
                            requiredSkills: FitConvert.extractRequiredSkills(attributes: attributes)
                        )
                        
                        viewModel.simulationInput.modules[index] = newModule
                    }
                } else {
                    // 如果原来没有弹药，直接创建新模块
                    let newModule = SimModule(
                        instanceId: oldModule.instanceId, // 保留原模块的instanceId
                        typeId: newTypeId,
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
                    
                    viewModel.simulationInput.modules[index] = newModule
                }
                
                successCount += 1
                Logger.info("批量替换装备: \(oldModule.name) -> \(model_name), 槽位: \(flag.rawValue)")
            } else {
                failedFlags.append(flag)
                Logger.error("批量替换装备失败: 找不到槽位 \(flag.rawValue)")
            }
        }
        
        // 只在最后计算一次属性
        Logger.info("批量替换装备完成，重新计算属性")
        viewModel.calculateAttributes()
        
        // 标记有未保存的更改
        viewModel.hasUnsavedChanges = true
        
        // 自动保存配置
        viewModel.saveConfiguration()
        
        Logger.info("批量替换装备完成，成功: \(successCount)/\(flags.count)")
        
        if !failedFlags.isEmpty {
            Logger.warning("批量替换装备部分失败，失败的槽位: \(failedFlags.map { $0.rawValue })")
        }
    }
    
    // 根据flag获取槽位类型
    private func getSlotType(for flag: FittingFlag) -> FittingSlotType? {
        switch flag {
        case .hiSlot0, .hiSlot1, .hiSlot2, .hiSlot3, .hiSlot4, .hiSlot5, .hiSlot6, .hiSlot7:
            return .hiSlots
        case .medSlot0, .medSlot1, .medSlot2, .medSlot3, .medSlot4, .medSlot5, .medSlot6, .medSlot7:
            return .medSlots
        case .loSlot0, .loSlot1, .loSlot2, .loSlot3, .loSlot4, .loSlot5, .loSlot6, .loSlot7:
            return .loSlots
        case .rigSlot0, .rigSlot1, .rigSlot2:
            return .rigSlots
        case .subSystemSlot0, .subSystemSlot1, .subSystemSlot2, .subSystemSlot3:
            return .subSystemSlots
        case .t3dModeSlot0:
            return .t3dModeSlot
        default:
            return nil
        }
    }
    
    // 检查指定槽位类型是否处于折叠状态
    private func isSlotTypeCollapsed(_ slotType: FittingSlotType?) -> Bool {
        guard let slotType = slotType else { return false }
        
        switch slotType {
        case .hiSlots:
            return viewModel.hiSlotsCollapsed
        case .medSlots:
            return viewModel.medSlotsCollapsed
        case .loSlots:
            return viewModel.loSlotsCollapsed
        case .rigSlots:
            return viewModel.rigSlotsCollapsed
        case .subSystemSlots, .t3dModeSlot:
            return false // 子系统和T3D模式不支持折叠
        }
    }
    
    // 获取槽位图标名称
    private func getSlotIcon(for slotType: FittingSlotType) -> String {
        switch slotType {
        case .hiSlots:
            return "highSlot"
        case .medSlots:
            return "midSlot"
        case .loSlots:
            return "lowSlot"
        case .rigSlots:
            return "rigSlot"
        case .subSystemSlots:
            return "subSystem"
        case .t3dModeSlot:
            return "subSystem"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 船体属性条
            if let output = viewModel.simulationOutput {
                ShipAttributesView(attributes: output.ship, viewModel: viewModel)
            }
            
            // 获取飞船槽位数 - 只使用计算后的数据
            if let outputShip = viewModel.simulationOutput?.ship {
                List {
                    let (hiSlotsNum, medSlotsNum, lowSlotsNum) = calculateDynamicSlots()
                    let rigSlotsNum = Int(outputShip.attributesByName["rigSlots"] ?? 0)
                    let subSysSlotsNum = Int(outputShip.attributesByName["maxSubSystems"] ?? 0)
                    
                    // 子系统槽位（如果有）
                    if subSysSlotsNum > 0 {
                        let subSysSlotsNum = 4  // 子系统槽位数修正为4
                        Section(
                            header: sectionHeader(title: FittingSlotType.subSystemSlots.localizedName, iconName: "subSystem")
                        ) {
                            ForEach(0..<subSysSlotsNum, id: \.self) { index in
                                let slotFlag = FittingSlotType.subSystemSlots.getSlotFlag(index: index)
                                
                                // 查找该槽位是否已安装装备 - 使用辅助函数
                                if let module = getDisplayModule(for: slotFlag) {
                                    filledSlotRow(
                                        module: module,
                                        slotId: slotFlag.rawValue,
                                        slotIndex: index,
                                        slotType: .subSystemSlots
                                    )
                                } else {
                                    emptySlotRow(
                                        icon: "subSystem",
                                        title: FittingSlotType.subSystemSlots.localizedName,
                                        slotId: slotFlag.rawValue,
                                        slotIndex: index,
                                        slotType: .subSystemSlots
                                    )
                                }
                            }
                        }
                    }
                    
                    // 高槽位
                    if hiSlotsNum > 0 {
                        Section(
                            header: sectionHeaderWithCollapse(
                                title: FittingSlotType.hiSlots.localizedName, 
                                iconName: "highSlot",
                                isCollapsed: viewModel.hiSlotsCollapsed,
                                onToggle: { viewModel.hiSlotsCollapsed.toggle() }
                            )
                        ) {
                            if viewModel.hiSlotsCollapsed {
                                // 折叠模式：显示分组
                                let groups = getModuleGroups(for: .hiSlots, totalSlots: hiSlotsNum)
                                ForEach(groups.indices, id: \.self) { index in
                                    let group = groups[index]
                                    collapsedGroupRow(group: group, slotType: .hiSlots)
                                }
                            } else {
                                // 展开模式：显示所有槽位
                                ForEach(0..<hiSlotsNum, id: \.self) { index in
                                    let slotFlag = FittingSlotType.hiSlots.getSlotFlag(index: index)
                                    
                                    // 查找该槽位是否已安装装备 - 使用辅助函数
                                    if let module = getDisplayModule(for: slotFlag) {
                                        filledSlotRow(
                                            module: module,
                                            slotId: slotFlag.rawValue,
                                            slotIndex: index,
                                            slotType: .hiSlots
                                        )
                                    } else {
                                        emptySlotRow(
                                            icon: "highSlot",
                                            title: FittingSlotType.hiSlots.localizedName,
                                            slotId: slotFlag.rawValue,
                                            slotIndex: index,
                                            slotType: .hiSlots
                                        )
                                    }
                                }
                            }
                        }
                    }
                    
                    // 中槽位
                    if medSlotsNum > 0 {
                        Section(
                            header: sectionHeaderWithCollapse(
                                title: FittingSlotType.medSlots.localizedName, 
                                iconName: "midSlot",
                                isCollapsed: viewModel.medSlotsCollapsed,
                                onToggle: { viewModel.medSlotsCollapsed.toggle() }
                            )
                        ) {
                            if viewModel.medSlotsCollapsed {
                                // 折叠模式：显示分组
                                let groups = getModuleGroups(for: .medSlots, totalSlots: medSlotsNum)
                                ForEach(groups.indices, id: \.self) { index in
                                    let group = groups[index]
                                    collapsedGroupRow(group: group, slotType: .medSlots)
                                }
                            } else {
                                // 展开模式：显示所有槽位
                                ForEach(0..<medSlotsNum, id: \.self) { index in
                                    let slotFlag = FittingSlotType.medSlots.getSlotFlag(index: index)
                                    
                                    // 查找该槽位是否已安装装备 - 使用辅助函数
                                    if let module = getDisplayModule(for: slotFlag) {
                                        filledSlotRow(
                                            module: module,
                                            slotId: slotFlag.rawValue,
                                            slotIndex: index,
                                            slotType: .medSlots
                                        )
                                    } else {
                                        emptySlotRow(
                                            icon: "midSlot",
                                            title: FittingSlotType.medSlots.localizedName,
                                            slotId: slotFlag.rawValue,
                                            slotIndex: index,
                                            slotType: .medSlots
                                        )
                                    }
                                }
                            }
                        }
                    }
                    
                    // 低槽位
                    if lowSlotsNum > 0 {
                        Section(
                            header: sectionHeaderWithCollapse(
                                title: FittingSlotType.loSlots.localizedName, 
                                iconName: "lowSlot",
                                isCollapsed: viewModel.loSlotsCollapsed,
                                onToggle: { viewModel.loSlotsCollapsed.toggle() }
                            )
                        ) {
                            if viewModel.loSlotsCollapsed {
                                // 折叠模式：显示分组
                                let groups = getModuleGroups(for: .loSlots, totalSlots: lowSlotsNum)
                                ForEach(groups.indices, id: \.self) { index in
                                    let group = groups[index]
                                    collapsedGroupRow(group: group, slotType: .loSlots)
                                }
                            } else {
                                // 展开模式：显示所有槽位
                                ForEach(0..<lowSlotsNum, id: \.self) { index in
                                    let slotFlag = FittingSlotType.loSlots.getSlotFlag(index: index)
                                    
                                    // 查找该槽位是否已安装装备 - 使用辅助函数
                                    if let module = getDisplayModule(for: slotFlag) {
                                        filledSlotRow(
                                            module: module,
                                            slotId: slotFlag.rawValue,
                                            slotIndex: index,
                                            slotType: .loSlots
                                        )
                                    } else {
                                        emptySlotRow(
                                            icon: "lowSlot",
                                            title: FittingSlotType.loSlots.localizedName,
                                            slotId: slotFlag.rawValue,
                                            slotIndex: index,
                                            slotType: .loSlots
                                        )
                                    }
                                }
                            }
                        }
                    }
                    
                    // 改装槽位
                    if rigSlotsNum > 0 {
                        Section(
                            header: sectionHeaderWithCollapse(
                                title: FittingSlotType.rigSlots.localizedName, 
                                iconName: "rigSlot",
                                isCollapsed: viewModel.rigSlotsCollapsed,
                                onToggle: { viewModel.rigSlotsCollapsed.toggle() }
                            )
                        ) {
                            if viewModel.rigSlotsCollapsed {
                                // 折叠模式：显示分组
                                let groups = getModuleGroups(for: .rigSlots, totalSlots: rigSlotsNum)
                                ForEach(groups.indices, id: \.self) { index in
                                    let group = groups[index]
                                    collapsedGroupRow(group: group, slotType: .rigSlots)
                                }
                            } else {
                                // 展开模式：显示所有槽位
                                ForEach(0..<rigSlotsNum, id: \.self) { index in
                                    let slotFlag = FittingSlotType.rigSlots.getSlotFlag(index: index)
                                    
                                    // 查找该槽位是否已安装装备 - 使用辅助函数
                                    if let module = getDisplayModule(for: slotFlag) {
                                        filledSlotRow(
                                            module: module,
                                            slotId: slotFlag.rawValue,
                                            slotIndex: index,
                                            slotType: .rigSlots
                                        )
                                    } else {
                                        emptySlotRow(
                                            icon: "rigSlot",
                                            title: FittingSlotType.rigSlots.localizedName,
                                            slotId: slotFlag.rawValue,
                                            slotIndex: index,
                                            slotType: .rigSlots
                                        )
                                    }
                                }
                            }
                        }
                    }
                    
                    // T3D模式槽位（如果是战术驱逐舰）
                    if outputShip.groupID == 1305 {
                        Section(
                            header: sectionHeader(title: FittingSlotType.t3dModeSlot.localizedName, iconName: "subSystem")
                        ) {
                            let slotFlag = FittingSlotType.t3dModeSlot.getSlotFlag(index: 0)
                            
                            // 查找该槽位是否已安装装备 - 使用辅助函数
                            if let module = getDisplayModule(for: slotFlag) {
                                filledSlotRow(
                                    module: module,
                                    slotId: slotFlag.rawValue,
                                    slotIndex: 0,
                                    slotType: .t3dModeSlot
                                )
                            } else {
                                emptySlotRow(
                                    icon: "subSystem",
                                    title: FittingSlotType.t3dModeSlot.localizedName,
                                    slotId: "T3DMode",
                                    slotIndex: 0,
                                    slotType: .t3dModeSlot
                                )
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                // 高槽选择器
                .sheet(item: $hiSlotSelectorState.slotFlag) { flag in
                    HiSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 检查是否是折叠模式下的批量安装
                            if viewModel.hiSlotsCollapsed {
                                let groups = getModuleGroups(for: .hiSlots, totalSlots: calculateDynamicSlots().hiSlots)
                                if let emptyGroup = groups.first(where: { $0.typeId == -1 }) {
                                    installModuleToEmptySlots(typeId: typeId, emptySlots: emptyGroup.emptySlots)
                                }
                            } else {
                                // 正常单个安装
                                Logger.info("安装装备到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                                viewModel.installModule(typeId: typeId, flag: flag)
                                Logger.info("已安装装备到槽位: \(flag.rawValue)")
                            }
                        },
                        shipTypeID: outputShip.typeId
                    )
                }
                // 中槽选择器
                .sheet(item: $medSlotSelectorState.slotFlag) { flag in
                    MedSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 检查是否是折叠模式下的批量安装
                            if viewModel.medSlotsCollapsed {
                                let groups = getModuleGroups(for: .medSlots, totalSlots: calculateDynamicSlots().medSlots)
                                if let emptyGroup = groups.first(where: { $0.typeId == -1 }) {
                                    installModuleToEmptySlots(typeId: typeId, emptySlots: emptyGroup.emptySlots)
                                }
                            } else {
                                // 正常单个安装
                                Logger.info("安装装备到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                                viewModel.installModule(typeId: typeId, flag: flag)
                                Logger.info("已安装装备到槽位: \(flag.rawValue)")
                            }
                        },
                        shipTypeID: outputShip.typeId
                    )
                }
                // 低槽选择器
                .sheet(item: $lowSlotSelectorState.slotFlag) { flag in
                    LowSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 检查是否是折叠模式下的批量安装
                            if viewModel.loSlotsCollapsed {
                                let groups = getModuleGroups(for: .loSlots, totalSlots: calculateDynamicSlots().lowSlots)
                                if let emptyGroup = groups.first(where: { $0.typeId == -1 }) {
                                    installModuleToEmptySlots(typeId: typeId, emptySlots: emptyGroup.emptySlots)
                                }
                            } else {
                                // 正常单个安装
                                Logger.info("安装装备到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                                viewModel.installModule(typeId: typeId, flag: flag)
                                Logger.info("已安装装备到槽位: \(flag.rawValue)")
                            }
                        },
                        shipTypeID: outputShip.typeId
                    )
                }
                // 改装槽选择器
                .sheet(item: $rigSlotSelectorState.slotFlag) { flag in
                    RigSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        shipTypeID: outputShip.typeId,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 检查是否是折叠模式下的批量安装
                            if viewModel.rigSlotsCollapsed {
                                let rigSlotsNum = Int(outputShip.attributesByName["rigSlots"] ?? 0)
                                let groups = getModuleGroups(for: .rigSlots, totalSlots: rigSlotsNum)
                                if let emptyGroup = groups.first(where: { $0.typeId == -1 }) {
                                    installModuleToEmptySlots(typeId: typeId, emptySlots: emptyGroup.emptySlots)
                                }
                            } else {
                                // 正常单个安装
                                Logger.info("安装改装件到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                                viewModel.installModule(typeId: typeId, flag: flag)
                                Logger.info("已安装改装件到槽位: \(flag.rawValue)")
                            }
                        }
                    )
                }
                // 子系统槽选择器
                .sheet(item: $subSysSlotSelectorState.slotFlag) { flag in
                    SubSysSlotEquipmentSelectorView(
                        databaseManager: viewModel.databaseManager,
                        shipTypeID: outputShip.typeId,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 安装装备到选定的槽位
                            Logger.info("安装子系统到槽位: \(flag.rawValue), 装备ID: \(typeId)")
                            
                            // 使用模型的安装方法，让模型内部计算并设置合适的状态
                            viewModel.installModule(typeId: typeId, flag: flag)
                            
                            Logger.info("已安装子系统到槽位: \(flag.rawValue)")
                        }
                    )
                }
                // T3D模式选择器
                .sheet(item: $t3dModeSelectorState.slotFlag) { flag in
                    T3DModeSelectorView(
                        databaseManager: viewModel.databaseManager,
                        slotFlag: flag,
                        onModuleSelected: { typeId in
                            // 安装T3D模式到选定的槽位
                            Logger.info("安装T3D模式到槽位: \(flag.rawValue), 模式ID: \(typeId)")
                            
                            // 对T3D模式，我们希望它默认为激活状态
                            viewModel.installModule(typeId: typeId, flag: flag, status: 2)
                            
                            Logger.info("已安装T3D模式到槽位: \(flag.rawValue), 状态: 2")
                        },
                        shipTypeID: outputShip.typeId
                    )
                }
                // 装备设置视图
                .sheet(item: $moduleSettingsState.slotFlag) { flag in
                    if let module = viewModel.simulationInput.modules.first(where: { $0.flag == flag }) {
                        // 检查是否是折叠模式，如果是，需要传递同类型的所有模块
                        let relatedModules = getRelatedModules(for: module, flag: flag)
                        
                        ModuleSettingsView(
                            module: module,
                            slotFlag: flag,
                            databaseManager: viewModel.databaseManager,
                            viewModel: viewModel,
                            relatedModules: relatedModules,
                            onDelete: {
                                // 删除装备 - 如果是批量模式，删除所有相同类型的装备
                                if shouldApplyBatchOperations(for: module) {
                                    deleteAllRelatedModules(for: module)
                                } else {
                                    viewModel.removeModule(flag: flag)
                                }
                                Logger.info("已删除装备，槽位: \(flag.rawValue)")
                            },
                            onReplaceModule: { newTypeId in
                                // 替换装备 - 如果是批量模式，替换所有相同类型的装备
                                if shouldApplyBatchOperations(for: module) {
                                    replaceAllRelatedModules(for: module, newTypeId: newTypeId)
                                } else {
                                    let success = viewModel.replaceModule(typeId: newTypeId, flag: flag)
                                    if success {
                                        Logger.info("已替换装备，槽位: \(flag.rawValue), 新装备ID: \(newTypeId)")
                                    } else {
                                        Logger.error("替换装备失败，槽位: \(flag.rawValue), 新装备ID: \(newTypeId)")
                                    }
                                }
                            }
                        )
                    }
                }
            } else {
                // 如果没有计算后的数据，显示加载状态
                VStack {
                    Text("Calc...")
                        .foregroundColor(.secondary)
                        .font(.headline)
                    
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            }
        }
    }
    
    // 区域头部视图
    private func sectionHeader(title: String, iconName: String) -> some View {
        HStack {
            IconManager.shared.loadImage(for: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            
            Text(title)
                .fontWeight(.semibold)
                .font(.system(size: 18))
        }
        .foregroundColor(.primary)
        .textCase(.none)
    }
    
    // 带折叠按钮的区域头部视图
    private func sectionHeaderWithCollapse(title: String, iconName: String, isCollapsed: Bool, onToggle: @escaping () -> Void) -> some View {
        HStack {
            IconManager.shared.loadImage(for: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            
            Text(title)
                .fontWeight(.semibold)
                .font(.system(size: 18))
            
            Spacer()
            
            Button(action: onToggle) {
                Image(systemName: isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
            }
        }
        .foregroundColor(.primary)
        .textCase(.none)
    }
    
    // 统一的模块行视图组件
    private func ModuleRowView(
        iconName: String?,
        isIconPlaceholder: Bool = false,
        iconOpacity: Double = 1.0,
        title: String,
        titleColor: Color = .primary,
        subtitle: String? = nil,
        charge: SimCharge? = nil,
        moduleForCapacity: SimModule? = nil,
        module: SimModule? = nil, // 新增模块参数用于属性计算
        rightContent: AnyView? = nil,
        onTap: @escaping () -> Void
    ) -> some View {
        HStack {
            // 装备图标
            if let iconName = iconName {
                IconManager.shared.loadImage(for: iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .opacity(iconOpacity)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                IconManager.shared.loadImage(for: "items_7_64_15.png")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            
            // 右侧垂直布局：装备名称和其他信息
            VStack(alignment: .leading, spacing: 2) {
                // 第一行：装备名称和副标题
                HStack(spacing: 8) {
                    Text(title)
                        .foregroundColor(titleColor)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 第二行：弹药信息（如果有）
                if let charge = charge {
                    HStack(spacing: 4) {
                        // 弹药图标
                        if let iconFileName = charge.iconFileName {
                            IconManager.shared.loadImage(for: iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 1))
                        } else {
                            // 如果没有弹药图标，使用占位图标
                            Image(systemName: "circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundColor(.secondary)
                        }
                        
                        // 弹药名称
                        Text(charge.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        // 显示弹药数量
                        if let chargeQuantity = charge.chargeQuantity {
                            // 如果有存储的弹药数量，直接显示
                            Text("×\(chargeQuantity)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if let chargeVolume = charge.attributesByName["volume"], 
                                    chargeVolume > 0,
                                    let module = moduleForCapacity {
                            // 从模块属性中获取容量并计算
                            let capacity = module.attributesByName["capacity"] ?? 0
                            if capacity > 0 {
                                let ammoCount = Int(capacity / chargeVolume)
                                Text("×\(ammoCount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                // 新增：装备属性行（如果有模块信息）
                if let module = module {
                    // 射程与失准
                    let maxRange = module.attributesByName["maxRange"] ?? 0
                    let falloff = module.attributesByName["falloff"] ?? 0
                    let empFieldRange = module.attributesByName["empFieldRange"] ?? 0
                    let isRemote = isRemoteEquip(module: module)
                    if let charge = module.charge {
                        let baseSensorStrength = charge.attributesByName["baseSensorStrength"] ?? 0
                        let maxFlightTime = charge.attributesByName["explosionDelay"] ?? 0
                        let maxFlightSpeed = charge.attributesByName["maxVelocity"] ?? 0
                        let maxMissileRange = maxFlightTime * maxFlightSpeed / 1000
                        if maxMissileRange > 0 { // 导弹最大射程，需除以1000
                            HStack(spacing: 4) {
                                IconManager.shared.loadImage(for: "items_22_32_15.png")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                
                                HStack(spacing: 0) {
                                    Text("\(NSLocalizedString("Module_Attribute_MaxRange", comment: "")): ")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(formatDistance(maxMissileRange))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if baseSensorStrength > 0, charge.groupID == 479 {  // 扫描探针强度
                            HStack(spacing: 4) {
                                IconManager.shared.loadImage(for: "probes")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                
                                HStack(spacing: 0) {
                                    Text("\(NSLocalizedString("Module_Attribute_ProbeStrength", comment: "")): ")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(formatNumber(baseSensorStrength, digits: 2))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // 能量中和值   
                    let energyNeutralizerAmount = module.attributesByName["energyNeutralizerAmount"] ?? 0
                    if energyNeutralizerAmount > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: "neut")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(NSLocalizedString("Module_Attribute_energyNeutralizerAmount", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatNumber(energyNeutralizerAmount, digits: 2)) GJ")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }


                    // 吸电 / 传电
                    let powerTransferAmount = module.attributesByName["powerTransferAmount"] ?? 0
                    if powerTransferAmount > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: module.groupID == 68 ? "neut_nos" : "cap_trans")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {  // 68 为吸电
                                Text("\(module.groupID == 68 ? NSLocalizedString("Module_Attribute_powerTransferAmount_nos", comment: "") : NSLocalizedString("Module_Attribute_powerTransferAmount", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatNumber(powerTransferAmount, digits: 2)) GJ")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // 护盾维修
                    let shieldBonus = module.attributesByName["shieldBonus"] ?? 0
                    if shieldBonus > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: !isRemote ? "shield_glow" : "shield_trans")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(!isRemote ? NSLocalizedString("Module_Attribute_shieldBonus", comment: "") : NSLocalizedString("Module_Attribute_trans_shieldBonus", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatNumber(shieldBonus, digits: 2)) HP")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // 装甲维修
                    let armorDamageAmount = module.attributesByName["armorDamageAmount"] ?? 0
                    if armorDamageAmount > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: !isRemote ? "armor_repairer_i" : "armor_trans")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(!isRemote ? NSLocalizedString("Module_Attribute_armorBonus", comment: "") : NSLocalizedString("Module_Attribute_trans_armorBonus", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatNumber(armorDamageAmount, digits: 2)) HP")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // 结构维修
                    let structureDamageAmount = module.attributesByName["structureDamageAmount"] ?? 0
                    if structureDamageAmount > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: !isRemote ? "hull_repairer_i" : "hull_trans")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(!isRemote ? NSLocalizedString("Module_Attribute_hullBonus", comment: "") : NSLocalizedString("Module_Attribute_trans_hullBonus", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatNumber(structureDamageAmount, digits: 2)) HP")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // 护盾盾扩加成
                    let capacityBonus = module.attributesByName["capacityBonus"] ?? 0
                    if capacityBonus > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: "shield")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(NSLocalizedString("Module_Attribute_shieldHPBonus", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("+\(formatNumber(capacityBonus, digits: 2)) HP")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 钢版加成
                    let armorHPBonusAdd = module.attributesByName["armorHPBonusAdd"] ?? 0
                    if armorHPBonusAdd > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: "armor")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(NSLocalizedString("Module_Attribute_armorHPBonus", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("+\(formatNumber(armorHPBonusAdd, digits: 2)) HP")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // 电容量加成
                    let capacitorBonus = module.attributesByName["capacitorBonus"] ?? 0
                    if capacitorBonus > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: "cap_add")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(NSLocalizedString("Module_Attribute_capBonus", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("+\(formatNumber(capacitorBonus, digits: 2)) GJ")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // 开采量
                    let miningAmount = module.attributesByName["miningAmount"] ?? 0
                    let miningWasteProbability = module.attributesByName["miningWasteProbability"] ?? 0
                    if miningAmount > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: "miner")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(NSLocalizedString("Module_Attribute_miningAmount", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatNumber(miningAmount, digits: 2)) m³ + \(formatNumber(miningWasteProbability, digits: 2))%")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 立体炸弹范围
                    if empFieldRange > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: "items_22_32_15.png")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(NSLocalizedString("Module_Attribute_empFieldRange", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatDistance(empFieldRange))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 最佳射程
                    if maxRange > 0 || falloff > 0 {
                        HStack(spacing: 4) {
                            if maxRange > 0 {
                                // 有maxRange时使用maxRange图标
                                IconManager.shared.loadImage(for: "items_22_32_15.png")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                            } else {
                                // 只有falloff时使用falloff图标
                                IconManager.shared.loadImage(for: "items_22_32_23.png")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                            }
                            
                            HStack(spacing: 0) {
                                if maxRange > 0 && falloff > 0 {
                                    Text("\(NSLocalizedString("Module_Attribute_Range", comment: ""))+\(NSLocalizedString("Module_Attribute_Falloff", comment: "")): ")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(formatDistance(maxRange)) + \(formatDistance(falloff))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                } else if maxRange > 0 {
                                    Text("\(NSLocalizedString("Module_Attribute_Range", comment: "")): ")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(formatDistance(maxRange))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(NSLocalizedString("Module_Attribute_Falloff", comment: "")): ")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(formatDistance(falloff))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    // 跟踪速度
                    let trackingSpeed = module.attributesByName["trackingSpeed"] ?? 0
                    
                    if trackingSpeed > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: "items_22_32_22.png")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(NSLocalizedString("Module_Attribute_Tracking", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatNumber(trackingSpeed))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 射击速度
                    let cycleDuration = calculateCycleDuration(module: module)
                    if cycleDuration > 0 {
                        HStack(spacing: 4) {
                            IconManager.shared.loadImage(for: "items_22_32_21.png")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            
                            HStack(spacing: 0) {
                                Text("\(NSLocalizedString("Module_Attribute_Rate_of_Fire", comment: "")): ")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(formatCycleDuration(cycleDuration))s")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }            
                }
            }
            
            Spacer()
            
            // 右侧内容（如状态图标等）
            if let rightContent = rightContent {
                rightContent
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = title
            } label: {
                Label(NSLocalizedString("Misc_Copy_Module_Name", comment: ""), systemImage: "doc.on.doc")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
    
    private func isRemoteEquip(module: SimModule) -> Bool {
        let maxRange = module.attributesByName["maxRange"] ?? 0
        return maxRange > 0
    }
    
    // 格式化距离显示（自动选择合适的单位：m或km）
    private func formatDistance(_ distance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.numberStyle = .decimal
        
        if distance >= 1000000 {
            // 大于等于1000km时，使用k km单位
            let value = distance / 1000000.0
            formatter.maximumFractionDigits = 1
            let formattedValue = formatter.string(from: NSNumber(value: value)) ?? "0"
            return "\(formattedValue)k km"
        } else if distance >= 1000 {
            // 大于等于1km时，使用km单位
            let value = distance / 1000.0
            formatter.maximumFractionDigits = 2
            let formattedValue = formatter.string(from: NSNumber(value: value)) ?? "0"
            return "\(formattedValue) km"
        } else {
            // 小于1km时，使用m单位
            formatter.maximumFractionDigits = 0
            let formattedValue = formatter.string(from: NSNumber(value: distance)) ?? "0"
            return "\(formattedValue) m"
        }
    }
    
    // 格式化跟踪速度（最多5位小数，去掉末尾的0）
    private func formatNumber(_ number: Double, digits: Int = 5) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "0"
    }
    
    // 计算射击周期时间（参考ShipFirepowerStatsView的方法）
    private func calculateCycleDuration(module: SimModule) -> Double {
        // 获取武器周期时间（毫秒）
        let speedMs = module.attributesByName["speed"] ?? 0
        let durationMs = module.attributesByName["duration"] ?? 0
        let durationHighisGoodMs = module.attributesByName["durationHighisGood"] ?? 0
        let durationSensorDampeningBurstProjectorMs = module.attributesByName["durationSensorDampeningBurstProjector"] ?? 0
        let durationTargetIlluminationBurstProjectorMs = module.attributesByName["durationTargetIlluminationBurstProjector"] ?? 0
        let durationECMJammerBurstProjectorMs = module.attributesByName["durationECMJammerBurstProjector"] ?? 0
        let durationWeaponDisruptionBurstProjectorMs = module.attributesByName["durationWeaponDisruptionBurstProjector"] ?? 0
        
        // 取最大值作为周期时间
        let cycleDurationMs = max(
            speedMs,
            durationMs,
            durationHighisGoodMs,
            durationSensorDampeningBurstProjectorMs,
            durationTargetIlluminationBurstProjectorMs,
            durationECMJammerBurstProjectorMs,
            durationWeaponDisruptionBurstProjectorMs
        )
        
        // 转换为秒
        return cycleDurationMs / 1000.0
    }
    
    // 格式化射击周期时间
    private func formatCycleDuration(_ duration: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: duration)) ?? "0"
    }
    
    // 重构后的折叠模式下的分组行视图
    private func collapsedGroupRow(group: ModuleGroup, slotType: FittingSlotType) -> some View {
        ModuleRowView(
            iconName: group.typeId == -1 ? getSlotIcon(for: slotType) : group.iconFileName,
            iconOpacity: group.typeId == -1 ? 0.6 : 1.0,
            title: group.name,
            titleColor: group.typeId == -1 ? .secondary : .primary,
            subtitle: "×\(group.totalCount)",
            charge: group.typeId != -1 ? group.modules.first?.charge : nil,
            moduleForCapacity: group.modules.first,
            module: group.typeId != -1 ? group.modules.first : nil,
            rightContent: group.typeId != -1 && group.modules.first != nil ? 
                AnyView(getStatusIcon(status: group.modules.first!.status)) : nil
        ) {
            handleGroupTap(group: group, slotType: slotType)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
    
    // 重构后的已安装装备的行视图
    private func filledSlotRow(module: SimModule, slotId: String, slotIndex: Int, slotType: FittingSlotType) -> some View {
        ModuleRowView(
            iconName: module.iconFileName,
            title: module.name,
            charge: module.charge,
            moduleForCapacity: module,
            module: module,
            rightContent: AnyView(getStatusIcon(status: module.status))
        ) {
            // 处理点击事件，获取当前槽位的flag
            let slotFlag = slotType.getSlotFlag(index: slotIndex)
            
            // 记录点击日志
            Logger.info("点击了已安装装备: \(module.name), 槽位: \(slotFlag.rawValue)")
            
            // 使用统一的打开函数
            openModuleSettings(flag: slotFlag, moduleName: module.name)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
    
    // 空槽位行视图，增加了slotId、slotIndex和slotType参数
    private func emptySlotRow(icon: String, title: String, slotId: String, slotIndex: Int, slotType: FittingSlotType? = nil) -> some View {
        HStack {
            IconManager.shared.loadImage(for: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .opacity(0.6)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            
            Text(title)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            // 处理点击事件，根据槽位类型打开不同的选择器
            Logger.info("点击了槽位: \(slotId), 索引: \(slotIndex)")
            
            if let slotType = slotType {
                let slotFlag = slotType.getSlotFlag(index: slotIndex)
                
                // 根据槽位类型打开对应的选择器
                switch slotType {
                case .hiSlots:
                    openHiSlotSelector(flag: slotFlag)
                case .medSlots:
                    openMedSlotSelector(flag: slotFlag)
                case .loSlots:
                    openLowSlotSelector(flag: slotFlag)
                case .rigSlots:
                    openRigSlotSelector(flag: slotFlag)
                case .subSystemSlots:
                    openSubSysSlotSelector(flag: slotFlag)
                case .t3dModeSlot:
                    openT3DModeSelector(flag: slotFlag)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

// 统一使用一个状态类，替代之前的ModuleSettingsState
class SlotState: ObservableObject, Identifiable {
    var id: String { slotFlag?.rawValue ?? "none" }
    @Published var slotFlag: FittingFlag?
}

// 保留FittingFlag的Identifiable扩展
extension FittingFlag: Identifiable {
    public var id: String { self.rawValue }
}

