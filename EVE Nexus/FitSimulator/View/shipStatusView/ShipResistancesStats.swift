import SwiftUI

struct ShipResistancesStatsView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    @State private var hpColumnWidth: CGFloat?
    
    // 伤害类型颜色 - 参考AttributeBarView.swift中的颜色
    private let emColor = Color(red: 74/255, green: 128/255, blue: 192/255)      // EM - 蓝色
    private let thermalColor = Color(red: 176/255, green: 53/255, blue: 50/255)  // Thermal - 红色
    private let kineticColor = Color(red: 155/255, green: 155/255, blue: 155/255) // Kinetic - 灰色
    private let explosiveColor = Color(red: 185/255, green: 138/255, blue: 62/255) // Explosive - 橙色
    
    var body: some View {
        if let ship = viewModel.simulationOutput?.ship {
            Section {
                VStack(spacing: 2) {
                    // 标题行：图标
                    HStack {
                        Color.clear.frame(width: 22, height: 0)
                        IconManager.shared.loadImage(for: "anti_em")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(maxWidth: .infinity)
                        
                        IconManager.shared.loadImage(for: "anti_th")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(maxWidth: .infinity)
                        
                        IconManager.shared.loadImage(for: "anti_ki")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(maxWidth: .infinity)
                        
                        IconManager.shared.loadImage(for: "anti_ex")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .frame(maxWidth: .infinity)
                        
                        Text("HP")
                            .font(.caption)
                            .frame(width: hpColumnWidth)
                    }
                    Divider()
                    // 护盾抗性行
                    HStack {
                        IconManager.shared.loadImage(for: "shield")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        
                        let shieldResistances = getShieldResistances(ship: ship)
                        ResistanceView(resistance: shieldResistances.em, color: emColor)
                        ResistanceView(resistance: shieldResistances.thermal, color: thermalColor)
                        ResistanceView(resistance: shieldResistances.kinetic, color: kineticColor)
                        ResistanceView(resistance: shieldResistances.explosive, color: explosiveColor)
                        
                        Text(formatHP(ship.attributesByName["shieldCapacity"] ?? 0))
                            .font(.caption)
                            .frame(width: hpColumnWidth)
                    }
                    
                    // 装甲抗性行
                    HStack {
                        IconManager.shared.loadImage(for: "armor")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        
                        let armorResistances = getArmorResistances(ship: ship)
                        ResistanceView(resistance: armorResistances.em, color: emColor)
                        ResistanceView(resistance: armorResistances.thermal, color: thermalColor)
                        ResistanceView(resistance: armorResistances.kinetic, color: kineticColor)
                        ResistanceView(resistance: armorResistances.explosive, color: explosiveColor)
                        
                        Text(formatHP(ship.attributesByName["armorHP"] ?? 0))
                            .font(.caption)
                            .frame(width: hpColumnWidth)
                    }
                    
                    // 结构抗性行
                    HStack {
                        IconManager.shared.loadImage(for: "hull")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        
                        let hullResistances = getHullResistances(ship: ship)
                        ResistanceView(resistance: hullResistances.em, color: emColor)
                        ResistanceView(resistance: hullResistances.thermal, color: thermalColor)
                        ResistanceView(resistance: hullResistances.kinetic, color: kineticColor)
                        ResistanceView(resistance: hullResistances.explosive, color: explosiveColor)
                        
                        Text(formatHP(ship.attributesByName["hp"] ?? 0))
                            .font(.caption)
                            .frame(width: hpColumnWidth)
                    }
                    
                    Divider()
                    
                    // 有效血量和总HP
                    let ehp = calculateEHP(ship: ship)
                    let totalHP = calculateTotalHP(ship: ship)
                    Text("\(NSLocalizedString("Fitting_tank_totalHP", comment: "总血量")): \(formatHP(totalHP)) | \(NSLocalizedString("Fitting_tank_effective", comment: "有效血量")): \(formatHP(ehp))")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption)
                .lineLimit(1)
                .onAppear {
                    // 初始设置HP列宽度
                    self.hpColumnWidth = 60
                }
            } header: {
                Text(NSLocalizedString("Fitting_stat_resistances", comment: ""))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .font(.system(size: 18))
            }
        }
    }
    
    // 获取护盾抗性
    private func getShieldResistances(ship: SimShipOutput) -> (em: Double, thermal: Double, kinetic: Double, explosive: Double) {
        let emResist = ship.attributesByName["shieldEmDamageResonance"] ?? 0
        let thermalResist = ship.attributesByName["shieldThermalDamageResonance"] ?? 0
        let kineticResist = ship.attributesByName["shieldKineticDamageResonance"] ?? 0
        let explosiveResist = ship.attributesByName["shieldExplosiveDamageResonance"] ?? 0
        
        // 谐振值需要转换为抗性百分比：抗性 = (1 - 谐振值)
        // 确保抗性在0-1范围内
        return (
            em: max(0, min(1, 1.0 - emResist)),
            thermal: max(0, min(1, 1.0 - thermalResist)),
            kinetic: max(0, min(1, 1.0 - kineticResist)),
            explosive: max(0, min(1, 1.0 - explosiveResist))
        )
    }
    
    // 获取装甲抗性
    private func getArmorResistances(ship: SimShipOutput) -> (em: Double, thermal: Double, kinetic: Double, explosive: Double) {
        let emResist = ship.attributesByName["armorEmDamageResonance"] ?? 0
        let thermalResist = ship.attributesByName["armorThermalDamageResonance"] ?? 0
        let kineticResist = ship.attributesByName["armorKineticDamageResonance"] ?? 0
        let explosiveResist = ship.attributesByName["armorExplosiveDamageResonance"] ?? 0
        
        return (
            em: max(0, min(1, 1.0 - emResist)),
            thermal: max(0, min(1, 1.0 - thermalResist)),
            kinetic: max(0, min(1, 1.0 - kineticResist)),
            explosive: max(0, min(1, 1.0 - explosiveResist))
        )
    }
    
    // 获取结构抗性
    private func getHullResistances(ship: SimShipOutput) -> (em: Double, thermal: Double, kinetic: Double, explosive: Double) {
        let emResist = ship.attributesByName["emDamageResonance"] ?? 0
        let thermalResist = ship.attributesByName["thermalDamageResonance"] ?? 0
        let kineticResist = ship.attributesByName["kineticDamageResonance"] ?? 0
        let explosiveResist = ship.attributesByName["explosiveDamageResonance"] ?? 0
        
        return (
            em: max(0, min(1, 1.0 - emResist)),
            thermal: max(0, min(1, 1.0 - thermalResist)),
            kinetic: max(0, min(1, 1.0 - kineticResist)),
            explosive: max(0, min(1, 1.0 - explosiveResist))
        )
    }
    
    // 计算总HP（盾+甲+结构）
    private func calculateTotalHP(ship: SimShipOutput) -> Double {
        let shieldHP = ship.attributesByName["shieldCapacity"] ?? 0
        let armorHP = ship.attributesByName["armorHP"] ?? 0
        let hullHP = ship.attributesByName["hp"] ?? 0
        
        return shieldHP + armorHP + hullHP
    }
    
    // 计算有效血量
    private func calculateEHP(ship: SimShipOutput) -> Double {
        let shieldHP = ship.attributesByName["shieldCapacity"] ?? 0
        let armorHP = ship.attributesByName["armorHP"] ?? 0
        let hullHP = ship.attributesByName["hp"] ?? 0
        
        let shieldResistances = getShieldResistances(ship: ship)
        let armorResistances = getArmorResistances(ship: ship)
        let hullResistances = getHullResistances(ship: ship)
        
        // 简单计算：取平均抗性计算EHP
        let shieldAvgResist = (shieldResistances.em + shieldResistances.thermal + shieldResistances.kinetic + shieldResistances.explosive) / 4.0
        let armorAvgResist = (armorResistances.em + armorResistances.thermal + armorResistances.kinetic + armorResistances.explosive) / 4.0
        let hullAvgResist = (hullResistances.em + hullResistances.thermal + hullResistances.kinetic + hullResistances.explosive) / 4.0
        
        let shieldEHP = shieldHP / (1.0 - shieldAvgResist)
        let armorEHP = armorHP / (1.0 - armorAvgResist)
        let hullEHP = hullHP / (1.0 - hullAvgResist)
        
        return shieldEHP + armorEHP + hullEHP
    }
    
    // 格式化HP数值：大于100,000时才使用k单位，使用FormatUtil的uiFormatter
    private func formatHP(_ value: Double) -> String {
        // 创建一个临时的NumberFormatter，基于FormatUtil的uiFormatter配置
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""     // 不使用千位分隔符
        formatter.decimalSeparator = "."
        
        if value == 0 {
            return "0"
        } else if value >= 1_000_000_000 {
            let formattedValue = value / 1_000_000_000
            formatter.maximumFractionDigits = 2
            let numberString = formatter.string(from: NSNumber(value: formattedValue)) ?? String(format: "%.2f", formattedValue)
            return numberString + "B"
        } else if value >= 1_000_000 {
            let formattedValue = value / 1_000_000
            formatter.maximumFractionDigits = 2
            let numberString = formatter.string(from: NSNumber(value: formattedValue)) ?? String(format: "%.2f", formattedValue)
            return numberString + "M"
        } else if value >= 100_000 {
            let formattedValue = value / 1000
            formatter.maximumFractionDigits = 2
            let numberString = formatter.string(from: NSNumber(value: formattedValue)) ?? String(format: "%.2f", formattedValue)
            return numberString + "k"
        } else {
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
    }
}

// 抗性视图组件
struct ResistanceView: View {
    let resistance: Double
    let color: Color
    
    var body: some View {
        Text(formatResistance(resistance))
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 18)
            .background(
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // 背景 - 使用更深的相同色调
                        Rectangle()
                            .fill(color.opacity(0.8))
                            .overlay(Color.black.opacity(0.5))
                        
                        // 进度条 - 增加亮度和饱和度
                        Rectangle()
                            .fill(color)
                            .saturation(1.2)  // 增加饱和度
                            .brightness(0.1)  // 增加亮度
                            .frame(width: getWidth(totalWidth: geometry.size.width))
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color, lineWidth: 0)
                    .saturation(1.2)
            )
    }
    
    private func formatResistance(_ value: Double) -> String {
        // 确保抗性值在0-100范围内显示
        let clampedValue = max(0, min(100, value * 100))
        return FormatUtil.formatForUI(clampedValue) + "%"
    }
    
    private func getWidth(totalWidth: CGFloat) -> CGFloat {
        // 确保抗性值在0-1范围内用于计算进度条宽度
        let clampedResistance = max(0, min(1, resistance))
        return totalWidth * CGFloat(clampedResistance)
    }
} 
