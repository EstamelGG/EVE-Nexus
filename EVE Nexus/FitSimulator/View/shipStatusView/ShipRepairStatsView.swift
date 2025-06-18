import SwiftUI

struct ShipRepairStatsView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    
    init(viewModel: FittingEditorViewModel) {
        self.viewModel = viewModel
    }
    
    private func formatValue(_ value: Double) -> String {
        return FormatUtil.formatForUI(value)
    }
    
    // 补丁函数，获取模块的维修量，处理特殊情况
    private func getModuleRepair(module: SimModuleOutput) -> (shield: Double, armor: Double, hull: Double) {
        let shieldBonus = module.attributesByName["shieldBonus"] ?? 0
        var armorBonus = module.attributesByName["armorDamageAmount"] ?? 0
        let hullBonus = module.attributesByName["structureDamageAmount"] ?? 0
        
        // 处理特殊装备: 辅助装甲维修器 (GroupID: 1199)
        if module.groupID == 1199 {
            if let charge = module.charge, let chargeQty = charge.chargeQuantity , chargeQty > 0 {
                let multiplier = module.attributesByName["chargedArmorDamageMultiplier"] ?? 1.0
                armorBonus *= multiplier
            }
        }
        
        return (shieldBonus, armorBonus, hullBonus)
    }
    
    // 计算坦克数据
    private func calculateTankData(ship: SimShipOutput) -> TankData {
        // 护盾被动恢复
        let shieldRechargeRate = ship.attributesByName["shieldRechargeRate"] ?? 0
        let shieldCapacity = ship.attributesByName["shieldCapacity"] ?? 0
        let passiveShieldRecharge = calculateShieldRecharge(capacity: shieldCapacity, rechargeRate: shieldRechargeRate / 1000.0)
        
        // 从模块获取主动修复数据
        var shieldRepair: Double = 0
        var armorRepair: Double = 0
        var hullRepair: Double = 0
        
        // 遍历所有模块计算修复量
        for module in viewModel.simulationOutput?.modules ?? [] {
            if module.status > 1 { // 模块处于激活状态
                // 获取模块维修量，处理特殊情况
                let (shieldBonus, armorBonus, hullBonus) = getModuleRepair(module: module)
                
                // 如果所有维修值都为0，跳过后续计算
                if shieldBonus == 0 && armorBonus == 0 && hullBonus == 0 {
                    continue
                }
                
                // 计算周期时间
                let durationMs = module.attributesByName["duration"] ?? 0
                let duration = durationMs / 1000.0 // 转换为秒
                
                // 计算重激活延迟
                let reactivationDelayMs = module.attributesByName["moduleReactivationDelay"] ?? 0
                let reactivationDelay = reactivationDelayMs / 1000.0
                
                // 计算总周期时间
                let cycleDuration = duration + reactivationDelay
                
                if cycleDuration > 0 {
                    // 计算每秒修复量
                    if shieldBonus != 0 {
                        let repair = shieldBonus / cycleDuration
                        shieldRepair += repair
                    }
                    
                    if armorBonus != 0 {
                        let repair = armorBonus / cycleDuration
                        armorRepair += repair
                    }
                    
                    if hullBonus != 0 {
                        let repair = hullBonus / cycleDuration
                        hullRepair += repair
                    }
                }
            }
        }
        
        // 计算有效HP
        let (shieldResist, armorResist, hullResist) = calculateResistances(ship: ship)
        
        // 创建坦克数据结构
        return TankData(
            passiveShield: passiveShieldRecharge,
            shieldRepair: shieldRepair,
            armorRepair: armorRepair,
            hullRepair: hullRepair,
            shieldResist: shieldResist,
            armorResist: armorResist,
            hullResist: hullResist
        )
    }
    
    // 计算护盾充能率
    private func calculateShieldRecharge(capacity: Double, rechargeRate: Double) -> Double {
        // 使用EVE公式：最大充能率 = 2.5 * capacity / rechargeRate
        return 2.5 * capacity / rechargeRate
    }
    
    // 计算抗性
    private func calculateResistances(ship: SimShipOutput) -> (shield: Double, armor: Double, hull: Double) {
        // 获取各类抗性
        let shieldEmResist = 1.0 - (ship.attributesByName["shieldEmDamageResonance"] ?? 0)
        let shieldThermResist = 1.0 - (ship.attributesByName["shieldThermalDamageResonance"] ?? 0)
        let shieldKinResist = 1.0 - (ship.attributesByName["shieldKineticDamageResonance"] ?? 0)
        let shieldExpResist = 1.0 - (ship.attributesByName["shieldExplosiveDamageResonance"] ?? 0)
        
        let armorEmResist = 1.0 - (ship.attributesByName["armorEmDamageResonance"] ?? 0)
        let armorThermResist = 1.0 - (ship.attributesByName["armorThermalDamageResonance"] ?? 0)
        let armorKinResist = 1.0 - (ship.attributesByName["armorKineticDamageResonance"] ?? 0)
        let armorExpResist = 1.0 - (ship.attributesByName["armorExplosiveDamageResonance"] ?? 0)
        
        let hullEmResist = 1.0 - (ship.attributesByName["emDamageResonance"] ?? 0)
        let hullThermResist = 1.0 - (ship.attributesByName["thermalDamageResonance"] ?? 0)
        let hullKinResist = 1.0 - (ship.attributesByName["kineticDamageResonance"] ?? 0)
        let hullExpResist = 1.0 - (ship.attributesByName["explosiveDamageResonance"] ?? 0)
        
        // 计算平均抗性
        let shieldAvgResist = (shieldEmResist + shieldThermResist + shieldKinResist + shieldExpResist) / 4.0
        let armorAvgResist = (armorEmResist + armorThermResist + armorKinResist + armorExpResist) / 4.0
        let hullAvgResist = (hullEmResist + hullThermResist + hullKinResist + hullExpResist) / 4.0
        
        return (shieldAvgResist, armorAvgResist, hullAvgResist)
    }
    
    var body: some View {
        if let ship = viewModel.simulationOutput?.ship {
            let tankData = calculateTankData(ship: ship)
            
            Section {
                VStack(spacing: 2) {
                    // 标题行：修复类型图标
                    HStack {
                        Text(NSLocalizedString("Fitting_tank_header", comment: "修复类型"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Icon(image: "shield_passive").frame(maxWidth: .infinity)
                        Icon(image: "shield_glow").frame(maxWidth: .infinity)
                        Icon(image: "armor_repairer_i").frame(maxWidth: .infinity)
                        Icon(image: "hull_repairer_i").frame(maxWidth: .infinity)
                    }
                    Divider()
                    
                    // 原始修复量行
                    HStack {
                        Text(NSLocalizedString("Fitting_tank_raw", comment: "原始值"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // 原始修复量
                        Text(formatValue(tankData.passiveShield)).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatValue(tankData.shieldRepair)).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatValue(tankData.armorRepair)).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatValue(tankData.hullRepair)).fixedSize()
                            .frame(maxWidth: .infinity)
                    }
                    
                    // 有效修复量行
                    HStack {
                        Text(NSLocalizedString("Fitting_tank_effective_repair", comment: "有效值"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // 考虑抗性后的有效修复量
                        Text(formatValue(tankData.passiveShield / (1 - tankData.shieldResist))).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatValue(tankData.shieldRepair / (1 - tankData.shieldResist))).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatValue(tankData.armorRepair / (1 - tankData.armorResist))).fixedSize()
                            .frame(maxWidth: .infinity)
                        Text(formatValue(tankData.hullRepair / (1 - tankData.hullResist))).fixedSize()
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            } header: {
                Text(NSLocalizedString("Fitting_stat_tank", comment: ""))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .font(.system(size: 18))
            }
        }
    }
}

// 坦克数据结构
struct TankData {
    let passiveShield: Double
    let shieldRepair: Double
    let armorRepair: Double
    let hullRepair: Double
    let shieldResist: Double
    let armorResist: Double
    let hullResist: Double
}

// 图标组件
struct Icon: View {
    let image: String
    
    var body: some View {
        IconManager.shared.loadImage(for: image)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
    }
} 
