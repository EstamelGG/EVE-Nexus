import SwiftUI

struct KillMailDetailCell: View {
    let detail: KillMailDetail
    @State private var shipTypeName: String = ""
    @State private var shipIconFilename: String = "items_7_64_15.png"
    @State private var victimName: String = ""
    @State private var attackerName: String = ""
    @State private var systemInfo: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：舰船信息和攻击者数量
            HStack(spacing: 12) {
                // 舰船图标
                AsyncImage(url: URL(string: "https://images.evetech.net/types/\(detail.victim.shipTypeId)/\(shipIconFilename)?size=64")) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 64, height: 64)
                
                VStack(alignment: .leading, spacing: 4) {
                    // 舰船名称和攻击者数量
                    HStack {
                        Text(shipTypeName)
                            .lineLimit(1)
                        Text("(\(detail.attackers.count))")
                            .foregroundColor(.secondary)
                    }
                    
                    // 受害者信息
                    HStack(spacing: 4) {
                        if let allianceId = detail.victim.allianceId {
                            AsyncImage(url: URL(string: "https://images.evetech.net/alliances/\(allianceId)/logo?size=32")) { image in
                                image.resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 20, height: 20)
                        }
                        Text(victimName)
                            .lineLimit(1)
                    }
                    
                    // 最后一击攻击者信息
                    if let finalBlowAttacker = detail.attackers.first(where: { $0.finalBlow }) {
                        HStack(spacing: 4) {
                            if let allianceId = finalBlowAttacker.allianceId {
                                AsyncImage(url: URL(string: "https://images.evetech.net/alliances/\(allianceId)/logo?size=32")) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 20, height: 20)
                            }
                            Text(attackerName)
                                .lineLimit(1)
                        }
                    }
                }
            }
            
            // 第二行：击杀地点
            Text(systemInfo)
                .foregroundColor(.secondary)
                .font(.subheadline)
            
            // 第三行：击杀时间
            Text(formatDate(detail.killmailTime))
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
        .padding(.vertical, 8)
        .onAppear {
            // 获取舰船类型名称和图标
            Task {
                let query = "SELECT icon_filename, name FROM types WHERE type_id = ?"
                if let result = try? await DatabaseManager.shared.executeQuery(query, parameters: [detail.victim.shipTypeId]),
                   let row = result.first,
                   let name = row["name"] as? String {
                    shipTypeName = name
                    if let iconFilename = row["icon_filename"] as? String {
                        shipIconFilename = iconFilename
                    }
                }
            }
            
            // 获取受害者名称
            Task {
                if let characterId = detail.victim.characterId,
                   let name = await UniverseManager.shared.getCharacterName(characterId) {
                    victimName = name
                }
            }
            
            // 获取最后一击攻击者名称
            Task {
                if let attacker = detail.attackers.first(where: { $0.finalBlow }),
                   let characterId = attacker.characterId,
                   let name = await UniverseManager.shared.getCharacterName(characterId) {
                    attackerName = name
                }
            }
            
            // 获取星系信息
            Task {
                if let systemName = await UniverseManager.shared.getSystemName(detail.solarSystemId),
                   let systemInfo = await UniverseManager.shared.getSystemInfo(detail.solarSystemId) {
                    let securityStatus = String(format: "%.1f", systemInfo.securityStatus)
                    let regionName = await UniverseManager.shared.getRegionName(systemInfo.regionId) ?? "未知星域"
                    self.systemInfo = "\(securityStatus) \(systemName) (\(regionName))"
                }
            }
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
} 