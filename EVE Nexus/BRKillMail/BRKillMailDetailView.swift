import SwiftUI

struct BRKillMailDetailView: View {
    let killmail: [String: Any]  // 这个现在只用来获取ID
    let kbAPI = KbEvetoolAPI.shared
    @State private var victimCharacterIcon: UIImage?
    @State private var victimCorporationIcon: UIImage?
    @State private var victimAllianceIcon: UIImage?
    @State private var shipIcon: UIImage?
    @State private var detailData: [String: Any]?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        List {
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let detail = detailData {
                // 受害者信息行
                HStack(spacing: 12) {
                    // 角色头像
                    if let characterIcon = victimCharacterIcon {
                        Image(uiImage: characterIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 66, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ProgressView()
                            .frame(width: 66, height: 66)
                    }
                    
                    // 军团和联盟图标
                    VStack(spacing: 2) {
                        if let corpIcon = victimCorporationIcon {
                            Image(uiImage: corpIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        if let allyIcon = victimAllianceIcon,
                           let victInfo = detail["vict"] as? [String: Any],
                           let allyId = victInfo["ally"] as? Int,
                           allyId > 0 {
                            Image(uiImage: allyIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    
                    // 名称信息
                    VStack(alignment: .leading, spacing: 2) {
                        // 角色名称
                        if let victInfo = detail["vict"] as? [String: Any],
                           let charId = victInfo["char"] as? Int,
                           let names = detail["names"] as? [String: [String: String]],
                           let chars = names["chars"],
                           let charName = chars[String(charId)] {
                            Text(charName)
                                .font(.headline)
                        }
                        
                        // 军团名称
                        if let victInfo = detail["vict"] as? [String: Any],
                           let corpId = victInfo["corp"] as? Int,
                           let names = detail["names"] as? [String: [String: String]],
                           let corps = names["corps"],
                           let corpName = corps[String(corpId)] {
                            Text(corpName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        // 联盟名称
                        if let victInfo = detail["vict"] as? [String: Any],
                           let allyId = victInfo["ally"] as? Int,
                           allyId > 0,
                           let names = detail["names"] as? [String: [String: String]],
                           let allys = names["allys"],
                           let allyName = allys[String(allyId)] {
                            Text(allyName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Ship
                if let victInfo = detail["vict"] as? [String: Any],
                   let shipId = victInfo["ship"] as? Int {
                    HStack {
                        Text(NSLocalizedString("Main_KM_Ship", comment: ""))
                            .frame(width: 110, alignment: .leading)
                        HStack {
                            if let shipIcon = shipIcon {
                                Image(uiImage: shipIcon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            Text(getShipName(shipId))
                        }
                    }
                }
                
                // System
                if let sysInfo = detail["sys"] as? [String: Any] {
                    HStack {
                        Text(NSLocalizedString("Main_KM_System", comment: ""))
                            .frame(width: 110, alignment: .leading)
                            .frame(maxHeight: .infinity, alignment: .center)
                        VStack(alignment: .leading) {
                            HStack {
                                Text(formatSecurityStatus(sysInfo["ss"] as? String ?? "0.0"))
                                    .foregroundColor(getSecurityColor(sysInfo["ss"] as? String ?? "0.0"))
                                Text(sysInfo["name"] as? String ?? "")
                                    .fontWeight(.bold)
                            }
                            Text(sysInfo["region"] as? String ?? "")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Eve Time
                HStack {
                    Text(NSLocalizedString("Main_KM_EVE_Time", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    if let time = detail["time"] as? Int {
                        Text(formatEVETime(time))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Local Time
                HStack {
                    Text(NSLocalizedString("Main_KM_Local_Time", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    if let time = detail["time"] as? Int {
                        Text(formatLocalTime(time))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Damage
                HStack {
                    Text(NSLocalizedString("Main_KM_Damage", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    if let victInfo = detail["vict"] as? [String: Any] {
                        let damage = victInfo["dmg"] as? Int ?? 0
                        Text(formatNumber(damage))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Ship Value
                HStack {
                    Text(NSLocalizedString("Main_KM_Ship_Value", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    if let victInfo = detail["vict"] as? [String: Any],
                       let shipId = victInfo["ship"] as? Int,
                       let prices = detail["prices"] as? [String: Double] {
                        let shipPrice = prices[String(shipId)] ?? 0
                        Text(formatISK(shipPrice))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Destroyed
                HStack {
                    Text(NSLocalizedString("Main_KM_Destroyed_Value", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    if let victInfo = detail["vict"] as? [String: Any],
                       let prices = detail["prices"] as? [String: Double] {
                        let values = calculateValues(victInfo: victInfo, prices: prices)
                        Text(formatISK(values.destroyed))
                            .foregroundColor(.red)
                    }
                }
                
                // Dropped
                HStack {
                    Text(NSLocalizedString("Main_KM_Dropped_Value", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    if let victInfo = detail["vict"] as? [String: Any],
                       let prices = detail["prices"] as? [String: Double] {
                        let values = calculateValues(victInfo: victInfo, prices: prices)
                        Text(formatISK(values.dropped))
                            .foregroundColor(.green)
                    }
                }
                
                // Total
                HStack {
                    Text(NSLocalizedString("Main_KM_Total", comment: ""))
                        .frame(width: 110, alignment: .leading)
                    if let victInfo = detail["vict"] as? [String: Any],
                       let prices = detail["prices"] as? [String: Double] {
                        let values = calculateValues(victInfo: victInfo, prices: prices)
                        Text(formatISK(values.destroyed + values.dropped))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .task {
            // 获取详细信息
            if let killId = killmail["_id"] as? Int {
                Logger.debug("准备获取战报ID: \(killId)的详细信息")
                do {
                    detailData = try await kbAPI.fetchKillMailDetail(killMailId: killId)
                    Logger.debug("成功获取战报详情: \(String(describing: detailData))")
                    // 获取到详细数据后再加载图标
                    if let detail = detailData {
                        await loadIcons(from: detail)
                    }
                } catch {
                    Logger.error("加载战斗日志详情失败: \(error)")
                    errorMessage = "加载失败: \(error.localizedDescription)"
                }
                isLoading = false
            } else {
                Logger.error("无法获取战报ID")
                errorMessage = "无法获取战报ID"
                isLoading = false
            }
        }
    }
    
    private func loadIcons(from detail: [String: Any]) async {
        // 加载受害者角色头像
        if let victInfo = detail["vict"] as? [String: Any],
           let charId = victInfo["char"] as? Int {
            let url = URL(string: "https://images.evetech.net/characters/\(charId)/portrait?size=128")
            if let url = url,
               let data = try? await NetworkManager.shared.fetchData(from: url) {
                victimCharacterIcon = UIImage(data: data)
            }
        }
        
        // 加载军团图标
        if let victInfo = detail["vict"] as? [String: Any],
           let corpId = victInfo["corp"] as? Int {
            let url = URL(string: "https://images.evetech.net/corporations/\(corpId)/logo?size=64")
            if let url = url,
               let data = try? await NetworkManager.shared.fetchData(from: url) {
                victimCorporationIcon = UIImage(data: data)
            }
        }
        
        // 加载联盟图标
        if let victInfo = detail["vict"] as? [String: Any],
           let allyId = victInfo["ally"] as? Int {
            let url = URL(string: "https://images.evetech.net/alliances/\(allyId)/logo?size=64")
            if let url = url,
               let data = try? await NetworkManager.shared.fetchData(from: url) {
                victimAllianceIcon = UIImage(data: data)
            }
        }
        
        // 加载舰船图标
        if let victInfo = detail["vict"] as? [String: Any],
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
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0  // 不显示小数位
        formatter.roundingMode = .halfUp     // 四舍五入
        return (formatter.string(from: NSNumber(value: value)) ?? "\(Int(round(value)))") + " ISK"
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func calculateValues(victInfo: [String: Any], prices: [String: Double]) -> (destroyed: Double, dropped: Double) {
        var destroyedTotal: Double = 0
        var droppedTotal: Double = 0
        
        // 首先加入船体本身的价值到被摧毁总价值中
        if let shipId = victInfo["ship"] as? Int,
           let shipPrice = prices[String(shipId)] {
            destroyedTotal += shipPrice
        }
        
        // 计算主船装备
        if let items = victInfo["itms"] as? [[Int]] {
            for item in items {
                if item.count >= 4 {
                    let typeId = item[1]
                    let dropped = item[2]    // 掉落的数量
                    let destroyed = item[3]   // 被摧毁的数量
                    
                    if let price = prices[String(typeId)] {
                        droppedTotal += price * Double(dropped)
                        destroyedTotal += price * Double(destroyed)
                    }
                }
            }
        }
        
        // 计算容器中的物品
        if let containers = victInfo["cnts"] as? [[String: Any]] {
            for container in containers {
                // 首先计算容器本身的价值
                if let containerTypeId = container["type"] as? Int,
                   let containerPrice = prices[String(containerTypeId)] {
                    if let drop = container["drop"] as? Int, drop == 1 {
                        droppedTotal += containerPrice
                    }
                    if let dstr = container["dstr"] as? Int, dstr == 1 {
                        destroyedTotal += containerPrice
                    }
                }
                
                // 然后计算容器内物品的价值
                if let containerItems = container["items"] as? [[Int]] {
                    for item in containerItems {
                        if item.count >= 4 {
                            let typeId = item[1]
                            let dropped = item[2]
                            let destroyed = item[3]
                            
                            if let price = prices[String(typeId)] {
                                droppedTotal += price * Double(dropped)
                                destroyedTotal += price * Double(destroyed)
                            }
                        }
                    }
                }
            }
        }
        
        return (destroyedTotal, droppedTotal)
    }
} 
