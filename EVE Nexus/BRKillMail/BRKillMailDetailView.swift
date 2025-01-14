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
            
            // Ship
            HStack {
                Text("Ship:")
                    .foregroundColor(.gray)
                    .frame(width: 120, alignment: .leading)
                if let victInfo = killmail["vict"] as? [String: Any],
                   let shipId = victInfo["ship"] as? Int {
                    Text("\(getShipName(shipId)) / Dreadnought")
                        .foregroundColor(.cyan)
                }
            }
            
            // System
            if let sysInfo = killmail["sys"] as? [String: Any] {
                HStack {
                    Text("System:")
                        .foregroundColor(.gray)
                        .frame(width: 120, alignment: .leading)
                    Text("\(sysInfo["name"] as? String ?? "") -\(formatSecurityStatus(sysInfo["ss"] as? String ?? "0.0")) / \(sysInfo["region"] as? String ?? "")")
                        .foregroundColor(.cyan)
                }
            }
            
            // Eve Time
            if let time = killmail["time"] as? Int {
                HStack {
                    Text("Eve Time:")
                        .foregroundColor(.gray)
                        .frame(width: 120, alignment: .leading)
                    Text(formatEVETime(time))
                        .foregroundColor(.gray)
                }
            }
            
            // Local Time
            if let time = killmail["time"] as? Int {
                HStack {
                    Text("Local Time:")
                        .foregroundColor(.gray)
                        .frame(width: 120, alignment: .leading)
                    Text(formatLocalTime(time))
                        .foregroundColor(.gray)
                }
            }
            
            // Damage
            if let victInfo = killmail["vict"] as? [String: Any] {
                HStack {
                    Text("Damage:")
                        .foregroundColor(.gray)
                        .frame(width: 120, alignment: .leading)
                    Text("\(victInfo["dmg"] as? Int ?? 0)")
                        .foregroundColor(.gray)
                }
            }
            
            // Fitted
            if let fitted = killmail["sumF"] as? Double {
                HStack {
                    Text("Fitted:")
                        .foregroundColor(.gray)
                        .frame(width: 120, alignment: .leading)
                    Text(formatISK(fitted))
                        .foregroundColor(.gray)
                }
            }
            
            // Ship Value
            if let victInfo = killmail["vict"] as? [String: Any],
               let shipId = victInfo["ship"] as? Int,
               let prices = killmail["prices"] as? [String: Double] {
                let shipPrice = prices[String(shipId)] ?? 0
                HStack {
                    Text("Ship:")
                        .foregroundColor(.gray)
                        .frame(width: 120, alignment: .leading)
                    Text(formatISK(shipPrice))
                        .foregroundColor(.gray)
                }
            }
            
            // Destroyed
            if let destroyed = killmail["sumV"] as? Double {
                HStack {
                    Text("Destroyed:")
                        .foregroundColor(.gray)
                        .frame(width: 120, alignment: .leading)
                    Text(formatISK(destroyed))
                        .foregroundColor(.red)
                }
            }
            
            // Dropped
            if let dropped = killmail["sumD"] as? Double {
                HStack {
                    Text("Dropped:")
                        .foregroundColor(.gray)
                        .frame(width: 120, alignment: .leading)
                    Text(formatISK(dropped))
                        .foregroundColor(.green)
                }
            }
            
            // Total
            if let destroyed = killmail["sumV"] as? Double,
               let dropped = killmail["sumD"] as? Double {
                HStack {
                    Text("Total:")
                        .foregroundColor(.gray)
                        .frame(width: 120, alignment: .leading)
                    Text(formatISK(destroyed + dropped))
                        .foregroundColor(.gray)
                }
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