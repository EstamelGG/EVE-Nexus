import SwiftUI
import Foundation
import OSLog

struct KillMailDetailCell: View {
    let detail: KillMailDetail
    let killMailInfo: KillMailInfo
    let characterId: Int
    let databaseManager = DatabaseManager.shared
    
    // 从数据库获取的信息
    @State private var shipInfo: (name: String, iconFileName: String) = (name: "Unknown Item", iconFileName: DatabaseConfig.defaultItemIcon)
    @State private var systemInfo: SolarSystemInfo?
    
    // 从API获取的信息
    @State private var victimName: String = ""
    @State private var victimIcon: UIImage?
    @State private var attackerName: String = ""
    @State private var attackerIcon: UIImage?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private var formattedDate: String {
        if let date = isoDateFormatter.date(from: detail.killmailTime) {
            return dateFormatter.string(from: date)
        }
        return "Unknown Date"
    }
    
    // 获取联盟图标
    private func getAllianceIcon(allianceId: Int) async throws -> UIImage? {
        try await Task.detached(priority: .userInitiated) {
            let url = URL(string: "https://images.evetech.net/alliances/\(allianceId)/logo?size=64")!
            let data = try await NetworkManager.shared.fetchData(from: url)
            return UIImage(data: data)
        }.value
    }
    
    // 获取军团/势力图标（包括 NPC 军团和玩家军团）
    private func getCorporationIcon(corporationId: Int) async throws -> UIImage? {
        try await Task.detached(priority: .userInitiated) {
            let url = URL(string: "https://images.evetech.net/corporations/\(corporationId)/logo?size=64")!
            let data = try await NetworkManager.shared.fetchData(from: url)
            return UIImage(data: data)
        }.value
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一大行：飞船信息、受害者和攻击者信息
            HStack(alignment: .center, spacing: 8) {
                // 飞船图标
                IconManager.shared.loadImage(for: shipInfo.iconFileName)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                // 右侧信息：四行
                VStack(alignment: .leading, spacing: 6) {
                    // 第一行：飞船类型名称
                    HStack {
                        Text(detail.victim.characterId == characterId ? "损失" : "击杀")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(detail.victim.characterId == characterId ? Color.red : Color.green)
                            .cornerRadius(2)
                        
                        Text(shipInfo.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    
                    // 第二行：价值显示
                    HStack {
                        Text("价值")
                            .font(.system(size: 11))
                            .foregroundColor(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.yellow)
                            .cornerRadius(2)
                        
                        Text(formatISK(killMailInfo.totalValue ?? 0))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    // 第三行：受害者信息
                    HStack(spacing: 4) {
                        Text("受害者")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(2)
                        
                        if let icon = victimIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 12, height: 12)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                        Text(victimName)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // 第四行：攻击者信息
                    if let _ = detail.attackers.first(where: { $0.finalBlow }) {
                        HStack(spacing: 4) {
                            Text("最后一击")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(2)
                            
                            if let icon = attackerIcon {
                                Image(uiImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 12, height: 12)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                            Text(attackerName)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            // 添加标签
                            if killMailInfo.npc == true {
                                Text("NPC")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.8))
                                    .cornerRadius(2)
                            }
                            
                            if killMailInfo.solo == true {
                                Text("SOLO")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.8))
                                    .cornerRadius(2)
                            }
                            
                            if killMailInfo.awox == true {
                                Text("AWOX")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red.opacity(0.8))
                                    .cornerRadius(2)
                            }
                        }
                    }
                }
                .frame(height: 80) // 确保与图标等高
            }
            
            // 第二大行：地点和时间
            HStack {
                // 左侧：战斗地点
                if let info = systemInfo {
                    HStack(spacing: 2) {
                        Text(formatSystemSecurity(info.security))
                            .foregroundColor(getSecurityColor(info.security))
                        Text(info.systemName)
                            .fontWeight(.medium)
                        Text("/")
                            .foregroundColor(.secondary)
                        Text(info.regionName)
                            .foregroundColor(.secondary)
                    }
                    .font(.system(size: 12))
                }
                
                Spacer()
                
                // 右侧：时间
                Text(formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
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
                    
                    // 获取受害者图标（优先级：联盟 > 势力/军团）
                    if let allianceId = detail.victim.allianceId {
                        victimIcon = try? await getAllianceIcon(allianceId: allianceId)
                    } else if let factionId = detail.victim.factionId {
                        victimIcon = try? await getCorporationIcon(corporationId: factionId)
                    } else if let corporationId = detail.victim.corporationId {
                        victimIcon = try? await getCorporationIcon(corporationId: corporationId)
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
                    
                    // 获取攻击者图标（优先级：联盟 > 势力/军团）
                    if let allianceId = finalBlow.allianceId {
                        attackerIcon = try? await getAllianceIcon(allianceId: allianceId)
                    } else if let factionId = finalBlow.factionId {
                        attackerIcon = try? await getCorporationIcon(corporationId: factionId)
                    } else if let corporationId = finalBlow.corporationId {
                        attackerIcon = try? await getCorporationIcon(corporationId: corporationId)
                    }
                } catch {
                    Logger.error("获取攻击者信息失败: \(error)")
                }
            }
        }
    }
    
    private func formatISK(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB ISK", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM ISK", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK ISK", value / 1_000)
        } else {
            return String(format: "%.0f ISK", value)
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
    
    private func getFactionIcon(factionId: Int) -> String? {
        let query = "SELECT icon_filename FROM factions WHERE faction_id = ?"
        if case .success(let results) = databaseManager.executeQuery(query, parameters: [factionId]),
           let row = results.first,
           let iconFileName = row["icon_filename"] as? String {
            return iconFileName
        }
        return nil
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
    
    // 获取军团图标
    private func getCorporationIcon(for corporationId: Int) -> String? {
        let query = "SELECT icon_id FROM corporations WHERE corporation_id = ?"
        if case .success(let results) = databaseManager.executeQuery(query, parameters: [corporationId]),
           let row = results.first,
           let iconId = row["icon_id"] as? Int64 {
            return "icon\(iconId)_64"
        }
        return nil
    }
    
    // 获取图标（仅从数据库获取，不包含异步API调用）
    private func getEntityIcon(factionId: Int?, corporationId: Int?) -> UIImage? {
        if let factionId = factionId {
            // 从数据库获取势力图标
            if let iconName = getFactionIcon(factionId: factionId) {
                return IconManager.shared.loadUIImage(for: iconName)
            }
        }
        if let corporationId = corporationId {
            // 从数据库获取军团图标
            if let iconName = getCorporationIcon(for: corporationId) {
                return IconManager.shared.loadUIImage(for: iconName)
            }
        }
        return nil
    }
} 
