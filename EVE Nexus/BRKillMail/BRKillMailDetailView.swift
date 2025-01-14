import SwiftUI

struct BRKillMailDetailView: View {
    let killmail: [String: Any]
    let kbAPI = KbEvetoolAPI.shared
    @State private var victimCharacterIcon: UIImage?
    @State private var victimCorporationIcon: UIImage?
    @State private var victimAllianceIcon: UIImage?
    @State private var shipIcon: UIImage?
    
    var body: some View {
        List {
            // 简介部分
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    // 受害者信息行
                    HStack(spacing: 12) {
                        // 角色头像
                        if let characterIcon = victimCharacterIcon {
                            Image(uiImage: characterIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else {
                            ProgressView()
                                .frame(width: 64, height: 64)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            // 角色名称
                            if let victInfo = killmail["vict"] as? [String: Any],
                               let charInfo = victInfo["char"] as? [String: Any],
                               let charId = charInfo["id"] as? Int {
                                Text(charInfo["name"] as? String ?? "\(charId)")
                                    .font(.headline)
                            }
                            
                            // 军团和联盟信息
                            HStack(spacing: 8) {
                                // 军团图标和名称
                                if let corpIcon = victimCorporationIcon {
                                    Image(uiImage: corpIcon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 32, height: 32)
                                }
                                if let victInfo = killmail["vict"] as? [String: Any],
                                   let corpInfo = victInfo["corp"] as? [String: Any] {
                                    Text(corpInfo["name"] as? String ?? "")
                                        .font(.subheadline)
                                }
                                
                                // 联盟图标和名称
                                if let allyIcon = victimAllianceIcon {
                                    Image(uiImage: allyIcon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 32, height: 32)
                                }
                                if let victInfo = killmail["vict"] as? [String: Any],
                                   let allyInfo = victInfo["ally"] as? [String: Any] {
                                    Text(allyInfo["name"] as? String ?? "")
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 舰船信息
                    if let victInfo = killmail["vict"] as? [String: Any],
                       let shipId = victInfo["ship"] as? Int {
                        HStack {
                            if let shipIcon = shipIcon {
                                Image(uiImage: shipIcon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                            }
                            Text(getShipName(shipId))
                                .font(.headline)
                        }
                    }
                    
                    Divider()
                    
                    // 战斗地点信息
                    if let sysInfo = killmail["sys"] as? [String: Any] {
                        HStack {
                            Text(formatSecurityStatus(sysInfo["ss"] as? String ?? "0.0"))
                                .foregroundColor(getSecurityColor(sysInfo["ss"] as? String ?? "0.0"))
                            Text(sysInfo["name"] as? String ?? "")
                                .font(.system(.body, design: .monospaced))
                            Text("/")
                            Text(sysInfo["region"] as? String ?? "")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    Divider()
                    
                    // 时间信息
                    if let time = killmail["time"] as? Int {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("EVE Time:")
                                Text(formatEVETime(time))
                                    .font(.system(.body, design: .monospaced))
                            }
                            HStack {
                                Text("Local Time:")
                                Text(formatLocalTime(time))
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 价值信息
                    if let victInfo = killmail["vict"] as? [String: Any] {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Damage Taken:")
                                Spacer()
                                Text("\(victInfo["dmg"] as? Int ?? 0)")
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            if let prices = killmail["prices"] as? [String: Double],
                               let shipId = victInfo["ship"] as? Int {
                                let shipPrice = prices[String(shipId)] ?? 0
                                HStack {
                                    Text("Ship Value:")
                                    Spacer()
                                    Text(formatISK(shipPrice))
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                            
                            if let destroyed = killmail["sumV"] as? Double {
                                HStack {
                                    Text("Total Value:")
                                    Spacer()
                                    Text(formatISK(destroyed))
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Battle Report")
        .task {
            await loadIcons()
        }
    }
    
    private func loadIcons() async {
        // 加载受害者角色头像
        if let victInfo = killmail["vict"] as? [String: Any],
           let charInfo = victInfo["char"] as? [String: Any],
           let charId = charInfo["id"] as? Int {
            let url = URL(string: "https://images.evetech.net/characters/\(charId)/portrait?size=128")
            if let url = url,
               let data = try? await NetworkManager.shared.fetchData(from: url) {
                victimCharacterIcon = UIImage(data: data)
            }
        }
        
        // 加载军团图标
        if let victInfo = killmail["vict"] as? [String: Any],
           let corpInfo = victInfo["corp"] as? [String: Any],
           let corpId = corpInfo["id"] as? Int {
            let url = URL(string: "https://images.evetech.net/corporations/\(corpId)/logo?size=64")
            if let url = url,
               let data = try? await NetworkManager.shared.fetchData(from: url) {
                victimCorporationIcon = UIImage(data: data)
            }
        }
        
        // 加载联盟图标
        if let victInfo = killmail["vict"] as? [String: Any],
           let allyInfo = victInfo["ally"] as? [String: Any],
           let allyId = allyInfo["id"] as? Int {
            let url = URL(string: "https://images.evetech.net/alliances/\(allyId)/logo?size=64")
            if let url = url,
               let data = try? await NetworkManager.shared.fetchData(from: url) {
                victimAllianceIcon = UIImage(data: data)
            }
        }
        
        // 加载舰船图标
        if let victInfo = killmail["vict"] as? [String: Any],
           let shipId = victInfo["ship"] as? Int {
            let url = URL(string: "https://images.evetech.net/types/\(shipId)/render?size=64")
            if let url = url,
               let data = try? await NetworkManager.shared.fetchData(from: url) {
                shipIcon = UIImage(data: data)
            }
        }
    }
    
    private func getShipName(_ shipId: Int) -> String {
        let query = "SELECT name FROM types WHERE type_id = ?"
        if case .success(let rows) = DatabaseManager.shared.executeQuery(query, parameters: [shipId]),
           let row = rows.first,
           let name = row["name"] as? String {
            return name
        }
        return "Unknown Ship"
    }
    
    private func formatSecurityStatus(_ status: String) -> String {
        if let value = Double(status) {
            return String(format: "%.1f", value)
        }
        return status
    }
    
    private func getSecurityColor(_ status: String) -> Color {
        guard let value = Double(status) else { return .gray }
        switch value {
        case 1.0...: return .green
        case 0.5..<1.0: return .blue
        case 0.0..<0.5: return .yellow
        default: return .red
        }
    }
    
    private func formatEVETime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
    
    private func formatLocalTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    private func formatISK(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.2fT ISK", value / 1_000_000_000_000)
        } else if value >= 1_000_000_000 {
            return String(format: "%.2fB ISK", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.2fM ISK", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.2fK ISK", value / 1_000)
        } else {
            return String(format: "%.2f ISK", value)
        }
    }
} 