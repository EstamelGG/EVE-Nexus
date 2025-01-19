import SwiftUI

struct CorpStructureView: View {
    let characterId: Int
    @StateObject private var viewModel = CorpStructureViewModel()
    
    var body: some View {
        List {
            ForEach(viewModel.structureGroups.sorted(by: { $0.key < $1.key }), id: \.key) { location, structures in
                Section(header: Text(location)) {
                    ForEach(structures, id: \.structure_id) { structure in
                        StructureCell(structure: structure, iconName: viewModel.getIconName(typeId: structure.type_id))
                    }
                }
            }
        }
        .navigationTitle("军团建筑")
        .task {
            await viewModel.loadStructures(characterId: characterId)
        }
        .refreshable {
            await viewModel.loadStructures(characterId: characterId, forceRefresh: true)
        }
    }
}

struct StructureCell: View {
    let structure: [String: Any]
    let iconName: String?
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧图标
            ZStack {
                Circle()
                    .stroke(getStateColor(state: structure["state"] as? String ?? ""), lineWidth: 2)
                    .frame(width: 50, height: 50)
                
                if let iconName = iconName {
                    Image(iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "building.2")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                }
            }
            
            // 右侧信息
            VStack(alignment: .leading, spacing: 4) {
                Text(structure["name"] as? String ?? "未知建筑")
                    .font(.headline)
                
                if let fuelExpires = structure["fuel_expires"] as? String {
                    HStack {
                        Text("燃料过期：")
                        Text(formatDateTime(fuelExpires))
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }
                
                HStack {
                    Text("状态：")
                    Text(getStateText(state: structure["state"] as? String ?? ""))
                        .foregroundColor(getStateColor(state: structure["state"] as? String ?? ""))
                }
                .font(.subheadline)
                
                if let services = structure["services"] as? [[String: String]] {
                    HStack {
                        Text("服务：")
                        ForEach(services, id: \.["name"]) { service in
                            if let name = service["name"], let state = service["state"] {
                                Text(name)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(state == "online" ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatDateTime(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return "未知时间"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let localTime = formatter.string(from: date)
        
        let remainingTime = date.timeIntervalSince(Date())
        let days = Int(remainingTime / (24 * 3600))
        let hours = Int((remainingTime.truncatingRemainder(dividingBy: 24 * 3600)) / 3600)
        
        return "\(localTime) (UTC+8) (\(days)天\(hours)小时后)"
    }
    
    private func getStateColor(state: String) -> Color {
        switch state {
        case "shield_vulnerable":
            return .blue
        case "armor_vulnerable", "armor_reinforce":
            return .orange
        case "hull_vulnerable", "hull_reinforce":
            return .red
        case "online_deprecated":
            return .gray
        default:
            return .green
        }
    }
    
    private func getStateText(state: String) -> String {
        switch state {
        case "shield_vulnerable":
            return "护盾易伤"
        case "armor_vulnerable":
            return "装甲易伤"
        case "armor_reinforce":
            return "装甲增强"
        case "hull_vulnerable":
            return "船体易伤"
        case "hull_reinforce":
            return "船体增强"
        case "online_deprecated":
            return "已弃用"
        case "anchor_vulnerable":
            return "锚定易伤"
        case "anchoring":
            return "锚定中"
        case "deploy_vulnerable":
            return "部署易伤"
        case "fitting_invulnerable":
            return "装配无敌"
        case "unanchored":
            return "未锚定"
        default:
            return "未知状态"
        }
    }
}

class CorpStructureViewModel: ObservableObject {
    @Published var structureGroups: [String: [[String: Any]]] = [:]
    private var typeIcons: [Int: String] = [:]
    private var systemNames: [Int: String] = [:]
    private var regionNames: [Int: String] = [:]
    
    func loadStructures(characterId: Int, forceRefresh: Bool = false) async {
        do {
            // 1. 获取角色的军团ID
            guard let corporationId = try await CharacterDatabaseManager.shared.getCharacterCorporationId(characterId: characterId) else {
                throw NetworkError.authenticationError("无法获取军团ID")
            }
            
            // 2. 从API获取数据
            let urlString = "https://esi.evetech.net/latest/corporations/\(corporationId)/structures/?datasource=tranquility"
            guard let url = URL(string: urlString) else {
                throw NetworkError.invalidURL
            }
            
            let headers = [
                "Accept": "application/json",
                "Content-Type": "application/json"
            ]
            
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url,
                characterId: characterId,
                headers: headers
            )
            
            guard let structures = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NetworkError.invalidResponse
            }
            
            // 3. 收集所有需要查询的ID
            let typeIds = Set(structures.compactMap { $0["type_id"] as? Int })
            let systemIds = Set(structures.compactMap { $0["system_id"] as? Int })
            
            // 4. 查询类型图标
            await loadTypeIcons(typeIds: Array(typeIds))
            
            // 5. 查询星系和星域信息
            await loadLocationInfo(systemIds: Array(systemIds))
            
            // 6. 按位置分组结构
            await MainActor.run {
                var groups: [String: [[String: Any]]] = [:]
                for structure in structures {
                    if let systemId = structure["system_id"] as? Int {
                        let systemName = systemNames[systemId] ?? "未知星系"
                        let regionName = regionNames[systemId] ?? "未知星域"
                        let locationKey = "\(regionName) - \(systemName)"
                        
                        if groups[locationKey] == nil {
                            groups[locationKey] = []
                        }
                        groups[locationKey]?.append(structure)
                    }
                }
                self.structureGroups = groups
            }
        } catch {
            Logger.error("加载建筑物信息失败: \(error)")
        }
    }
    
    private func loadTypeIcons(typeIds: [Int]) async {
        do {
            let query = "SELECT type_id, icon_filename FROM types WHERE type_id IN (\(typeIds.map(String.init).joined(separator: ",")))"
            let result = try await DatabaseManager.shared.executeQuery(query)
            
            if case .success(let rows) = result {
                await MainActor.run {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let iconFilename = row["icon_filename"] as? String {
                            self.typeIcons[typeId] = iconFilename
                        }
                    }
                }
            }
        } catch {
            Logger.error("加载类型图标失败: \(error)")
        }
    }
    
    private func loadLocationInfo(systemIds: [Int]) async {
        do {
            // 1. 获取星系名称
            let systemQuery = """
                SELECT solarSystemID, solarSystemName 
                FROM solarsystems 
                WHERE solarSystemID IN (\(systemIds.map(String.init).joined(separator: ",")))
            """
            let systemResult = try await DatabaseManager.shared.executeQuery(systemQuery)
            
            // 2. 获取星域信息
            let universeQuery = """
                SELECT DISTINCT u.solarsystem_id, u.region_id, r.regionName
                FROM universe u
                JOIN regions r ON u.region_id = r.regionID
                WHERE u.solarsystem_id IN (\(systemIds.map(String.init).joined(separator: ",")))
            """
            let universeResult = try await DatabaseManager.shared.executeQuery(universeQuery)
            
            await MainActor.run {
                // 处理星系名称
                if case .success(let rows) = systemResult {
                    for row in rows {
                        if let systemId = row["solarSystemID"] as? Int,
                           let systemName = row["solarSystemName"] as? String {
                            self.systemNames[systemId] = systemName
                        }
                    }
                }
                
                // 处理星域信息
                if case .success(let rows) = universeResult {
                    for row in rows {
                        if let systemId = row["solarsystem_id"] as? Int,
                           let regionName = row["regionName"] as? String {
                            self.regionNames[systemId] = regionName
                        }
                    }
                }
            }
        } catch {
            Logger.error("加载位置信息失败: \(error)")
        }
    }
    
    func getIconName(typeId: Int) -> String? {
        return typeIcons[typeId]
    }
} 
