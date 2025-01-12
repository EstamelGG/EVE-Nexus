import SwiftUI
import Foundation
import OSLog

struct KillMailDetailCell: View {
    let detail: KillMailDetail
    let databaseManager = CharacterDatabaseManager.shared
    @State private var shipIconFilename: String = "items_7_64_15.png"
    @State private var shipTypeName: String = ""
    @State private var victimName: String = ""
    @State private var victimAllianceIcon: UIImage?
    @State private var attackerName: String = ""
    @State private var attackerAllianceIcon: UIImage?
    @State private var systemName: String = ""
    @State private var regionName: String = ""
    @State private var securityStatus: Double = 0.0
    
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
                // 舰船图标
                AsyncImage(url: URL(string: "https://images.evetech.net/types/\(detail.victim.shipTypeId)/icon?size=64")) { image in
                    image
                        .resizable()
                        .frame(width: 32, height: 32)
                } placeholder: {
                    Image("items_7_64_15")
                        .resizable()
                        .frame(width: 32, height: 32)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    // 舰船类型名称
                    Text(shipTypeName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    // 受害者名称和联盟图标
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
            
            // 第二行: 最后一击者名称和联盟图标
            if let finalBlow = detail.attackers.first(where: { $0.finalBlow }) {
                HStack(spacing: 4) {
                    Text(attackerName)
                        .font(.system(size: 14))
                        .lineLimit(1)
                    
                    if let allianceId = finalBlow.allianceId,
                       let icon = attackerAllianceIcon {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            
            // 第三行: 击杀地点和时间
            HStack {
                HStack(spacing: 4) {
                    Text(formatSystemSecurity(securityStatus))
                        .foregroundColor(getSecurityColor(securityStatus))
                    Text("\(systemName) / \(regionName)")
                }
                .font(.caption)
                
                Spacer()
                
                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .task {
            // 获取舰船类型名称
            let query = "SELECT icon_filename, name FROM types WHERE type_id = ?"
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [detail.victim.shipTypeId]),
               let row = rows.first,
               let iconFilename = row["icon_filename"] as? String,
               let name = row["name"] as? String {
                shipIconFilename = iconFilename
                shipTypeName = name
            }
            
            // 获取受害者名称
            if let characterId = detail.victim.characterId {
                let victimQuery = "SELECT name FROM characters WHERE character_id = ?"
                if case .success(let rows) = databaseManager.executeQuery(victimQuery, parameters: [characterId]),
                   let row = rows.first,
                   let name = row["name"] as? String {
                    victimName = name
                }
            }
            
            // 获取受害者联盟图标
            if let allianceId = detail.victim.allianceId {
                do {
                    let icon = try await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId, size: 64)
                    victimAllianceIcon = icon
                } catch {
                    Logger.error("获取受害者联盟图标失败: \(error)")
                }
            }
            
            // 获取最后一击者名称
            if let finalBlow = detail.attackers.first(where: { $0.finalBlow }),
               let characterId = finalBlow.characterId {
                do {
                    let info = try await CharacterAPI.shared.fetchCharacterPublicInfo(characterId: characterId)
                    attackerName = info.name
                    
                    // 获取最后一击者联盟图标
                    if let allianceId = finalBlow.allianceId {
                        let icon = try await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId, size: 64)
                        attackerAllianceIcon = icon
                    }
                } catch {
                    Logger.error("获取攻击者信息失败: \(error)")
                }
            }
            
            // 获取系统和区域信息
            let systemQuery = "SELECT name, security_status, region_id FROM systems WHERE system_id = ?"
            if case .success(let rows) = databaseManager.executeQuery(systemQuery, parameters: [detail.solarSystemId]),
               let row = rows.first,
               let sysName = row["name"] as? String,
               let secStatus = row["security_status"] as? Double,
               let regionId = row["region_id"] as? Int {
                systemName = sysName
                securityStatus = secStatus
                
                // 获取区域名称
                let regionQuery = "SELECT name FROM regions WHERE region_id = ?"
                if case .success(let regionRows) = databaseManager.executeQuery(regionQuery, parameters: [regionId]),
                   let regionRow = regionRows.first,
                   let regName = regionRow["name"] as? String {
                    regionName = regName
                }
            }
        }
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