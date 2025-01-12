import SwiftUI
import Foundation
import OSLog

struct KillMailDetailCell: View {
    let detail: KillMailDetail
    let databaseManager = DatabaseManager.shared
    
    // 从数据库获取的信息
    @State private var shipInfo: (name: String, iconFileName: String) = (name: "Unknown Item", iconFileName: DatabaseConfig.defaultItemIcon)
    @State private var systemInfo: SolarSystemInfo?
    
    // 从API获取的信息
    @State private var victimName: String = ""
    @State private var victimAllianceIcon: UIImage?
    @State private var attackerName: String = ""
    @State private var attackerAllianceIcon: UIImage?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private var formattedDate: String {
        if let date = isoDateFormatter.date(from: detail.killmailTime) {
            return dateFormatter.string(from: date)
        }
        return detail.killmailTime
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行: 舰船图标、受害者名称和联盟图标
            HStack(spacing: 8) {
                // 受害者舰船图标（从数据库获取）
                IconManager.shared.loadImage(for: shipInfo.iconFileName)
                    .resizable()
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    // 舰船类型名称（从数据库获取）
                    Text(shipInfo.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    // 受害者名称和联盟图标（从API获取）
                    HStack(spacing: 4) {
                        Text(victimName)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        if let icon = victimAllianceIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                
                Spacer()
                
                // 击杀者数量
                Text("\(detail.attackers.count)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            
            // 第二行: 最后一击者名称和联盟图标（从API获取）
            if let finalBlow = detail.attackers.first(where: { $0.finalBlow }) {
                HStack(spacing: 4) {
                    Text(attackerName)
                        .font(.system(size: 14))
                        .lineLimit(1)
                    
                    if let icon = attackerAllianceIcon {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            
            // 第三行: 击杀地点和时间（从数据库获取星系信息）
            HStack {
                if let info = systemInfo {
                    HStack(spacing: 4) {
                        Text(formatSystemSecurity(info.security))
                            .foregroundColor(getSecurityColor(info.security))
                        Text("\(info.systemName) / \(info.regionName)")
                    }
                    .font(.caption)
                }
                
                Spacer()
                
                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .task {
            // 1. 从数据库获取舰船信息
            shipInfo = getItemInfo(for: detail.victim.shipTypeId)
            
            // 2. 从数据库获取星系信息
            systemInfo = await getSolarSystemInfo(solarSystemId: detail.solarSystemId, databaseManager: databaseManager)
            
            // 3. 从API获取受害者信息
            if let characterId = detail.victim.characterId {
                do {
                    let info = try await CharacterAPI.shared.fetchCharacterPublicInfo(characterId: characterId)
                    victimName = info.name
                    
                    if let allianceId = detail.victim.allianceId {
                        victimAllianceIcon = try await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId, size: 64)
                    }
                } catch {
                    Logger.error("获取受害者信息失败: \(error)")
                }
            }
            
            // 4. 从API获取最后一击者信息
            if let finalBlow = detail.attackers.first(where: { $0.finalBlow }),
               let characterId = finalBlow.characterId {
                do {
                    let info = try await CharacterAPI.shared.fetchCharacterPublicInfo(characterId: characterId)
                    attackerName = info.name
                    
                    if let allianceId = finalBlow.allianceId {
                        attackerAllianceIcon = try await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId, size: 64)
                    }
                } catch {
                    Logger.error("获取攻击者信息失败: \(error)")
                }
            }
        }
    }
    
    private func getItemInfo(for typeId: Int) -> (name: String, iconFileName: String) {
        let result = databaseManager.executeQuery(
            "SELECT name, icon_filename FROM types WHERE type_id = ?",
            parameters: [typeId]
        )
        
        if case .success(let rows) = result,
           let row = rows.first,
           let name = row["name"] as? String,
           let iconFileName = row["icon_filename"] as? String {
            return (name: name, iconFileName: iconFileName)
        }
        
        return (name: "Unknown Item", iconFileName: DatabaseConfig.defaultItemIcon)
    }
    
    private func formatSystemSecurity(_ security: Double) -> String {
        String(format: "%.1f", security)
    }
    
    private func getSecurityColor(_ security: Double) -> Color {
        if security >= 0.5 {
            return .green
        } else if security > 0.0 {
            return .orange
        } else {
            return .red
        }
    }
} 
