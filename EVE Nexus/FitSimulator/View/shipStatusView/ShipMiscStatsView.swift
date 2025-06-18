import SwiftUI

struct ShipMiscStatsView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    
    init(viewModel: FittingEditorViewModel) {
        self.viewModel = viewModel
    }
    
    private func formatValue(_ value: Double, unit: String = "") -> String {
        let numberString = FormatUtil.formatForUI(value, maxFractionDigits: 2)
        return numberString + (unit.isEmpty ? "" : " " + unit)
    }
    
    // 计算飞船朝向时间
    private func calculateAlignTime(mass: Double, agility: Double) -> Double {
        // 公式: -ln(0.25) * agility * mass / 1000000
        // 其中 -ln(0.25) ≈ 1.3862943611198906
        return 1.3862943611198906 * agility * mass / 1000000
    }
    
    var body: some View {
        if let ship = viewModel.simulationOutput?.ship {
            // Get character attributes if available
            let characterMaxLockedTargets = viewModel.simulationOutput?.ship.characterAttributesByName["maxLockedTargets"] ?? 0
            let droneControlDistance = viewModel.simulationOutput?.ship.characterAttributesByName["droneControlDistance"] ?? 0
            
            // Get ship attributes
            let maxLockedTargets = min(ship.attributesByName["maxLockedTargets"] ?? 0, characterMaxLockedTargets)
            let maxTargetRange = ship.attributesByName["maxTargetRange"] ?? 0
            let scanResolution = ship.attributesByName["scanResolution"] ?? 0
            let mass = ship.attributesByName["mass"] ?? 0
            let agility = ship.attributesByName["agility"] ?? 0
            let maxVelocity = ship.attributesByName["maxVelocity"] ?? 0
            let signatureRadius = ship.attributesByName["signatureRadius"] ?? 0
            let capacity = ship.attributesByName["capacity"] ?? 0
            let warpSpeedMultiplier = ship.attributesByName["warpSpeedMultiplier"] ?? 0
            let baseWarpSpeed = ship.attributesByName["baseWarpSpeed"] ?? 0
            let warpSpeed = warpSpeedMultiplier * baseWarpSpeed
            
            // 计算朝向时间
            let alignTime = calculateAlignTime(mass: mass, agility: agility)
            
            // Sensor strength values
            let radarStrength = ship.attributesByName["scanRadarStrength"] ?? 0
            let ladarStrength = ship.attributesByName["scanLadarStrength"] ?? 0
            let magnetometricStrength = ship.attributesByName["scanMagnetometricStrength"] ?? 0
            let gravimetricStrength = ship.attributesByName["scanGravimetricStrength"] ?? 0
            
            Section {
                // Two-column layout
                HStack(alignment: .top, spacing: 0) {
                    // Left column
                    VStack(alignment: .leading, spacing: 8) {
                        StatRow(label: NSLocalizedString("Fitting_max_targets", comment: "锁定数"), 
                              value: formatValue(maxLockedTargets))
                        
                        StatRow(label: NSLocalizedString("Fitting_lock_range", comment: "锁定距离"), 
                              value: formatValue(maxTargetRange / 1000, unit: "km"))
                        
                        StatRow(label: NSLocalizedString("Fitting_scan_resolution", comment: "扫描分辨率"), 
                              value: formatValue(scanResolution, unit: "mm"))
                        
                        StatRow(label: NSLocalizedString("Fitting_drone_range", comment: "无人机距离"), 
                              value: formatValue(droneControlDistance / 1000, unit: "km"))
                        
                        StatRow(label: NSLocalizedString("Fitting_mass", comment: "质量"), 
                              value: formatValue(mass, unit: "kg"))
                        
                        StatRow(label: NSLocalizedString("Fitting_radar_strength", comment: ""),
                              value: formatValue(radarStrength))
                        
                        StatRow(label: NSLocalizedString("Fitting_ladar_strength", comment: ""),
                              value: formatValue(ladarStrength))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Vertical divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1)
                        .padding(.horizontal, 8)
                    
                    // Right column
                    VStack(alignment: .leading, spacing: 8) {
                        StatRow(label: NSLocalizedString("Fitting_velocity", comment: "速度"), 
                              value: formatValue(maxVelocity, unit: "m/s"))
                        
                        StatRow(label: NSLocalizedString("Fitting_align_time", comment: "转向时间"), 
                              value: formatValue(alignTime, unit: "s"))
                        
                        StatRow(label: NSLocalizedString("Fitting_signature", comment: "信号半径"), 
                              value: formatValue(signatureRadius, unit: "m"))
                        
                        StatRow(label: NSLocalizedString("Fitting_cargo", comment: "货舱"), 
                              value: formatValue(capacity, unit: "m³"))
                        
                        StatRow(label: NSLocalizedString("Fitting_warp_speed", comment: "跃迁速度"), 
                              value: formatValue(warpSpeed, unit: "AU/s"))
                        
                        StatRow(label: NSLocalizedString("Fitting_mag_strength", comment: ""),
                              value: formatValue(magnetometricStrength))
                        
                        StatRow(label: NSLocalizedString("Fitting_grav_strength", comment: ""),
                              value: formatValue(gravimetricStrength))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .padding(.vertical, 4)
            } header: {
                Text(NSLocalizedString("Fitting_stat_misc", comment: "其他属性"))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .font(.system(size: 18))
            }
        }
    }
}

// Reusable row component for statistics
struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
        }
        .lineLimit(1)
    }
} 
