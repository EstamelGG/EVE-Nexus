import Foundation

/// Step5 - 推进模块速度修正阶段
/// 处理激活状态的推进模块对maxVelocity的额外修正
class Step5 {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    /// 处理推进模块的速度修正和突变属性修正
    /// - Parameter output: 经过Step4计算的输出数据
    /// - Returns: 修正后的输出数据
    func process(output: SimulationOutput) -> SimulationOutput {
        var modifiedOutput = output

        // 1. 应用突变属性修正（在速度修正之前）
        modifiedOutput = applyMutationAttributes(output: modifiedOutput)

        // 2. 查找第一个激活状态的推进模块
        let activePropulsionModule = findFirstActivePropulsionModule(modules: modifiedOutput.modules)

        if let propulsionModule = activePropulsionModule {
            Logger.info("找到激活的推进模块: \(propulsionModule.name) (TypeID: \(propulsionModule.typeId))")

            // 修正飞船的maxVelocity
            modifiedOutput.ship = applyVelocityCorrection(
                ship: modifiedOutput.ship,
                propulsionModule: propulsionModule
            )

            Logger.info("已应用推进模块速度修正")
        } else {
            Logger.info("未找到激活的推进模块，跳过速度修正")
        }

        return modifiedOutput
    }

    /// 应用突变属性到模块和无人机的计算后属性
    /// - Parameter output: 经过Step4计算的输出数据
    /// - Returns: 应用突变属性后的输出数据
    private func applyMutationAttributes(output: SimulationOutput) -> SimulationOutput {
        var modifiedOutput = output

        // 应用模块的突变属性
        for i in 0 ..< modifiedOutput.modules.count {
            let moduleOutput = modifiedOutput.modules[i]

            // 从原始输入中找到对应的模块（通过instanceId匹配）
            if let originalModule = output.originalInput.modules.first(where: { $0.instanceId == moduleOutput.instanceId }),
               !originalModule.mutatedAttributes.isEmpty
            {
                // 查询属性ID到属性名称的映射
                let attrIds = Array(originalModule.mutatedAttributes.keys)
                guard !attrIds.isEmpty else { continue }

                let placeholders = Array(repeating: "?", count: attrIds.count).joined(separator: ",")
                let attrNameQuery = "SELECT attribute_id, name FROM dogmaAttributes WHERE attribute_id IN (\(placeholders))"
                var attrIdToName: [Int: String] = [:]
                if case let .success(rows) = databaseManager.executeQuery(
                    attrNameQuery, parameters: attrIds
                ) {
                    for row in rows {
                        if let attrId = row["attribute_id"] as? Int,
                           let name = row["name"] as? String
                        {
                            attrIdToName[attrId] = name
                        }
                    }
                }

                // 对每个突变属性，将计算后的值乘以突变倍数
                var updatedAttributes = moduleOutput.attributes
                var updatedAttributesByName = moduleOutput.attributesByName

                for (attributeID, multiplier) in originalModule.mutatedAttributes {
                    if let currentValue = updatedAttributes[attributeID] {
                        let mutatedValue = currentValue * multiplier
                        updatedAttributes[attributeID] = mutatedValue

                        // 同时更新属性名称字典
                        if let attributeName = attrIdToName[attributeID] {
                            updatedAttributesByName[attributeName] = mutatedValue
                        }

                        if AppConfiguration.Fitting.showDebug {
                            Logger.info("应用突变属性: 模块 \(moduleOutput.name), 属性ID \(attributeID), 计算后值: \(currentValue), 突变倍数: \(multiplier), 突变后值: \(mutatedValue)")
                        }
                    }
                }

                // 创建更新后的模块输出
                var updatedModule = moduleOutput
                updatedModule.attributes = updatedAttributes
                updatedModule.attributesByName = updatedAttributesByName
                modifiedOutput.modules[i] = updatedModule
            }
        }

        // 应用无人机的突变属性
        for i in 0 ..< modifiedOutput.drones.count {
            let droneOutput = modifiedOutput.drones[i]

            // 从原始输入中找到对应的无人机（通过instanceId匹配）
            if let originalDrone = output.originalInput.drones.first(where: { $0.instanceId == droneOutput.instanceId }),
               !originalDrone.mutatedAttributes.isEmpty
            {
                // 查询属性ID到属性名称的映射
                let attrIds = Array(originalDrone.mutatedAttributes.keys)
                guard !attrIds.isEmpty else { continue }

                let placeholders = Array(repeating: "?", count: attrIds.count).joined(separator: ",")
                let attrNameQuery = "SELECT attribute_id, name FROM dogmaAttributes WHERE attribute_id IN (\(placeholders))"
                var attrIdToName: [Int: String] = [:]
                if case let .success(rows) = databaseManager.executeQuery(
                    attrNameQuery, parameters: attrIds
                ) {
                    for row in rows {
                        if let attrId = row["attribute_id"] as? Int,
                           let name = row["name"] as? String
                        {
                            attrIdToName[attrId] = name
                        }
                    }
                }

                // 对每个突变属性，将计算后的值乘以突变倍数
                var updatedAttributes = droneOutput.attributes
                var updatedAttributesByName = droneOutput.attributesByName

                for (attributeID, multiplier) in originalDrone.mutatedAttributes {
                    if let currentValue = updatedAttributes[attributeID] {
                        let mutatedValue = currentValue * multiplier
                        updatedAttributes[attributeID] = mutatedValue

                        // 同时更新属性名称字典
                        if let attributeName = attrIdToName[attributeID] {
                            updatedAttributesByName[attributeName] = mutatedValue
                        }

                        if AppConfiguration.Fitting.showDebug {
                            Logger.info("应用突变属性: 无人机 \(droneOutput.name), 属性ID \(attributeID), 计算后值: \(currentValue), 突变倍数: \(multiplier), 突变后值: \(mutatedValue)")
                        }
                    }
                }

                // 创建更新后的无人机输出
                var updatedDrone = droneOutput
                updatedDrone.attributes = updatedAttributes
                updatedDrone.attributesByName = updatedAttributesByName
                modifiedOutput.drones[i] = updatedDrone
            }
        }

        return modifiedOutput
    }

    /// 查找第一个激活状态的推进模块
    /// - Parameter modules: 模块列表
    /// - Returns: 第一个激活的推进模块，如果没有则返回nil
    private func findFirstActivePropulsionModule(modules: [SimModuleOutput]) -> SimModuleOutput? {
        let propulsionEffectIds = [6730, 6731] // moduleBonusAfterburner, moduleBonusMicrowarpdrive

        for module in modules {
            // 检查模块是否处于激活状态 (status > 1， 0 下线，1 在线，2 激活，3 超载)
            if module.status > 1 {
                // 检查模块是否包含推进效果
                let hasActivePropulsionEffect = module.effects.contains { effectId in
                    propulsionEffectIds.contains(effectId)
                }

                if hasActivePropulsionEffect {
                    return module
                }
            }
        }

        return nil
    }

    /// 应用速度修正到飞船
    /// - Parameters:
    ///   - ship: 飞船数据
    ///   - propulsionModule: 推进模块数据
    /// - Returns: 修正后的飞船数据
    private func applyVelocityCorrection(ship: SimShipOutput, propulsionModule: SimModuleOutput)
        -> SimShipOutput
    {
        var correctedShip = ship

        // 获取当前属性值
        let currentMass = ship.attributesByName["mass"] ?? 0
        let currentMaxVelocity = ship.attributesByName["maxVelocity"] ?? 0

        // 获取推进模块的属性
        let speedFactor = propulsionModule.attributesByName["speedFactor"] ?? 0
        let speedBoostFactor = propulsionModule.attributesByName["speedBoostFactor"] ?? 0
        let massAddition = propulsionModule.attributesByName["massAddition"] ?? 0

        Logger.info("速度修正前 - 质量: \(currentMass), 最大速度: \(currentMaxVelocity)")
        Logger.info(
            "推进模块属性 - speedFactor: \(speedFactor), speedBoostFactor: \(speedBoostFactor), massAddition: \(massAddition)"
        )

        // 根据propulsionModules.yaml的逻辑计算velocityBoost:
        // velocityBoost += speedBoostFactor (modAdd)
        // velocityBoost *= speedFactor (postMul)
        // velocityBoost /= mass (postDiv)
        // maxVelocity *= (1 + velocityBoost/100) (postPercent)

        // 步骤1: 计算velocityBoost
        var velocityBoost = 0.0
        velocityBoost += speedBoostFactor // modAdd操作
        velocityBoost *= speedFactor // postMul操作

        // 步骤2: 用质量修正velocityBoost
        let correctedVelocityBoost = currentMass > 0 ? velocityBoost / currentMass : 0

        // 步骤3: 计算修正后的maxVelocity
        let velocityMultiplier = 1.0 + (correctedVelocityBoost / 100.0)
        let correctedMaxVelocity = currentMaxVelocity * velocityMultiplier

        // 更新属性值
        correctedShip.attributesByName["maxVelocity"] = correctedMaxVelocity
        if let maxVelocityId = getAttributeId(name: "maxVelocity") {
            correctedShip.attributes[maxVelocityId] = correctedMaxVelocity
        }

        Logger.info(
            "速度修正计算 - velocityBoost: \(velocityBoost), 修正后velocityBoost: \(correctedVelocityBoost)")
        Logger.info("速度修正后 - 速度倍数: \(velocityMultiplier), 最大速度: \(correctedMaxVelocity)")

        return correctedShip
    }

    /// 获取属性ID
    /// - Parameter name: 属性名称
    /// - Returns: 属性ID，如果不存在则返回nil
    private func getAttributeId(name: String) -> Int? {
        // 这里应该从数据库查询属性ID，为了简化先硬编码常用的
        switch name {
        case "maxVelocity":
            return 37
        case "mass":
            return 4
        case "velocityBoost":
            return 5801
        default:
            return nil
        }
    }
}
