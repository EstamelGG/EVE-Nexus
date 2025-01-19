import SwiftUI

struct CorpStructureView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpStructureViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: Error?
    @State private var showError = false
    @State private var showSettings = false
    @AppStorage("structureFuelMonitorDays") private var fuelMonitorDays: Int = 7
    @State private var tempDays: String = ""
    
    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: CorpStructureViewModel(characterId: characterId))
        _tempDays = State(initialValue: "7")
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.structures.isEmpty {
                emptyView
            } else {
                // 即将耗尽燃料的建筑
                if !viewModel.lowFuelStructures(within: fuelMonitorDays).isEmpty {
                    Section(header: Text("⚠️ 燃料不足（\(fuelMonitorDays)天内）")
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .textCase(nil))
                    {
                        ForEach(viewModel.lowFuelStructures(within: fuelMonitorDays).indices, id: \.self) { index in
                            let structure = viewModel.lowFuelStructures(within: fuelMonitorDays)[index]
                            if let typeId = structure["type_id"] as? Int {
                                StructureCell(structure: structure, iconName: viewModel.getIconName(typeId: typeId), isLowFuel: true)
                            }
                        }
                    }
                }
                
                // 所有建筑列表
                structureListView
            }
        }
        .navigationTitle("军团建筑")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    tempDays = String(fuelMonitorDays)
                    showSettings = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationView {
                Form {
                    Section {
                        NavigationLink {
                            List {
                                ForEach([
                                    (name: "1周", days: 7),
                                    (name: "2周", days: 14),
                                    (name: "3周", days: 21),
                                    (name: "1个月", days: 30),
                                    (name: "2个月", days: 60)
                                ], id: \.days) { option in
                                    HStack {
                                        Text(option.name)
                                        Spacer()
                                        if fuelMonitorDays == option.days {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.accentColor)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        fuelMonitorDays = option.days
                                        showSettings = false
                                    }
                                }
                            }
                            .navigationTitle("监控时间")
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack {
                                Text("燃料监控时间")
                                Spacer()
                                Text("\(fuelMonitorDays)天")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle("设置")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") {
                            showSettings = false
                        }
                    }
                }
            }
        }
        .refreshable {
            do {
                try await viewModel.loadStructures(forceRefresh: true)
            } catch {
                if !(error is CancellationError) {
                    self.error = error
                    self.showError = true
                    Logger.error("刷新建筑信息失败: \(error)")
                }
            }
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("错误"),
                message: Text(error?.localizedDescription ?? "未知错误"),
                dismissButton: .default(Text("确定")) {
                    dismiss()
                }
            )
        }
    }
    
    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
            Spacer()
        }
    }
    
    private var emptyView: some View {
        HStack {
            Spacer()
            Text("暂无建筑数据")
                .foregroundColor(.secondary)
            Spacer()
        }
    }
    
    private var structureListView: some View {
        ForEach(viewModel.locationKeys, id: \.self) { location in
            if let structures = viewModel.groupedStructures[location] {
                Section(header: Text(location)
                    .fontWeight(.bold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(nil))
                {
                    ForEach(structures.indices, id: \.self) { index in
                        let structure = structures[index]
                        if let typeId = structure["type_id"] as? Int {
                            StructureCell(structure: structure, iconName: viewModel.getIconName(typeId: typeId))
                        }
                    }
                }
            }
        }
    }
}

struct StructureCell: View {
    let structure: [String: Any]
    let iconName: String?
    let isLowFuel: Bool
    @State private var icon: Image?
    
    init(structure: [String: Any], iconName: String?, isLowFuel: Bool = false) {
        self.structure = structure
        self.iconName = iconName
        self.isLowFuel = isLowFuel
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧图标
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 44, height: 44)
                
                Circle()
                    .stroke(isLowFuel ? .red : getStateColor(state: structure["state"] as? String ?? ""), lineWidth: 2)
                    .frame(width: 44, height: 44)
                
                if let icon = icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "building.2")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            
            // 右侧信息
            VStack(alignment: .leading, spacing: 4) {
                Text(structure["name"] as? String ?? "未知建筑")
                    .font(.headline)
                    .lineLimit(1)
                
                if let fuelExpires = structure["fuel_expires"] as? String {
                    HStack {
                        Text("燃料耗尽：")
                        Text(formatDateTime(fuelExpires).localTime)
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                    
                    HStack {
                        Text("耗尽时间：")
                        Text(formatDateTime(fuelExpires).remainingTime)
                            .foregroundColor(isLowFuel ? .red : .secondary)
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
        .task {
            if let iconName = iconName {
                icon = IconManager.shared.loadImage(for: iconName)
            }
        }
    }
    
    private func formatDateTime(_ dateString: String) -> (localTime: String, remainingTime: String) {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return ("未知时间", "")
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let localTime = formatter.string(from: date) + " (UTC+8)"
        
        let remainingTime = date.timeIntervalSince(Date())
        let days = Int(remainingTime / (24 * 3600))
        let hours = Int((remainingTime.truncatingRemainder(dividingBy: 24 * 3600)) / 3600)
        
        return (localTime, "\(days)天\(hours)小时后")
    }
    
    private func getStateColor(state: String) -> Color {
        switch state {
        case "shield_reinforce":
            return .blue.opacity(0.7)  // 淡蓝色
        case "armor_reinforce":
            return .orange
        case "hull_reinforce":
            return .red
        default:
            return .green
        }
    }
    
    private func getStateText(state: String) -> String {
        switch state {
        case "shield_vulnerable":
            return "护盾可被攻击"
        case "armor_vulnerable":
            return "装甲可被攻击"
        case "armor_reinforce":
            return "装甲增强中"
        case "hull_vulnerable":
            return "船体可被攻击"
        case "hull_reinforce":
            return "船体增强中"
        case "online_deprecated":
            return "已弃用"
        case "anchor_vulnerable":
            return "锚定可被攻击"
        case "anchoring":
            return "锚定中"
        case "deploy_vulnerable":
            return "部署可被攻击"
        case "fitting_invulnerable":
            return "装配无敌"
        case "unanchored":
            return "未锚定"
        default:
            return "未知状态"
        }
    }
}

@MainActor
class CorpStructureViewModel: ObservableObject {
    @Published var structures: [[String: Any]] = []
    @Published private(set) var isLoading = false
    private var typeIcons: [Int: String] = [:]
    private var systemNames: [Int: String] = [:]
    private var regionNames: [Int: String] = [:]
    private let characterId: Int
    
    // 获取燃料不足的建筑，按照燃料耗尽时间升序排序
    func lowFuelStructures(within days: Int = 7) -> [[String: Any]] {
        let monitorDays = days <= 0 ? 7 : days
        return structures.filter { structure in
            guard let fuelExpires = structure["fuel_expires"] as? String,
                  let expirationDate = ISO8601DateFormatter().date(from: fuelExpires) else {
                return false
            }
            
            let timeInterval = expirationDate.timeIntervalSince(Date())
            return timeInterval > 0 && timeInterval <= Double(monitorDays) * 24 * 3600
        }.sorted { structure1, structure2 in
            guard let fuelExpires1 = structure1["fuel_expires"] as? String,
                  let fuelExpires2 = structure2["fuel_expires"] as? String,
                  let date1 = ISO8601DateFormatter().date(from: fuelExpires1),
                  let date2 = ISO8601DateFormatter().date(from: fuelExpires2) else {
                return false
            }
            return date1 < date2
        }
    }
    
    init(characterId: Int) {
        self.characterId = characterId
        // 在初始化时立即开始加载数据
        Task {
            do {
                try await loadStructures()
            } catch {
                if !(error is CancellationError) {
                    Logger.error("初始化加载建筑信息失败: \(error)")
                }
            }
        }
    }
    
    var locationKeys: [String] {
        Array(groupedStructures.keys).sorted()
    }
    
    var groupedStructures: [String: [[String: Any]]] {
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
        
        // 对每个区域内的建筑按名称排序
        for (key, value) in groups {
            groups[key] = value.sorted { structure1, structure2 in
                let name1 = structure1["name"] as? String ?? ""
                let name2 = structure2["name"] as? String ?? ""
                return name1 < name2
            }
        }
        
        return groups
    }
    
    func loadStructures(forceRefresh: Bool = false) async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        // 从API获取数据
        let structures = try await CorpStructureAPI.shared.fetchStructures(
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        
        // 将 StructureInfo 转换为字典
        let structureDicts: [[String: Any]] = structures.map { structure in
            var dict: [String: Any] = [
                "structure_id": structure.structure_id,
                "type_id": structure.type_id,
                "system_id": structure.system_id,
                "state": structure.state,
                "name": structure.name ?? "Unknown"
            ]
            
            if let fuelExpires = structure.fuel_expires {
                dict["fuel_expires"] = fuelExpires
            }
            
            if let services = structure.services {
                dict["services"] = services.map { ["name": $0.name, "state": $0.state] }
            }
            
            return dict
        }
        
        // 收集所有需要查询的ID
        let typeIds = Set(structureDicts.compactMap { $0["type_id"] as? Int })
        let systemIds = Set(structureDicts.compactMap { $0["system_id"] as? Int })
        
        // 查询类型图标
        await loadTypeIcons(typeIds: Array(typeIds))
        
        // 查询星系和星域信息
        await loadLocationInfo(systemIds: Array(systemIds))
        
        // 更新结构数据
        self.structures = structureDicts
    }
    
    private func loadTypeIcons(typeIds: [Int]) async {
        let query = "SELECT type_id, icon_filename FROM types WHERE type_id IN (\(typeIds.map(String.init).joined(separator: ",")))"
        let result = DatabaseManager.shared.executeQuery(query)
        if case .success(let rows) = result {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let iconFilename = row["icon_filename"] as? String {
                    self.typeIcons[typeId] = iconFilename
                }
            }
        }
    }
    
    private func loadLocationInfo(systemIds: [Int]) async {
        // 1. 获取星系名称
        let systemQuery = """
            SELECT solarSystemID, solarSystemName 
            FROM solarsystems 
            WHERE solarSystemID IN (\(systemIds.map(String.init).joined(separator: ",")))
        """
        let systemResult = DatabaseManager.shared.executeQuery(systemQuery)
        if case .success(let rows) = systemResult {
            for row in rows {
                if let systemId = row["solarSystemID"] as? Int,
                   let systemName = row["solarSystemName"] as? String {
                    self.systemNames[systemId] = systemName
                }
            }
        }
        
        // 2. 获取星域信息
        let universeQuery = """
            SELECT DISTINCT u.solarsystem_id, u.region_id, r.regionName
            FROM universe u
            JOIN regions r ON u.region_id = r.regionID
            WHERE u.solarsystem_id IN (\(systemIds.map(String.init).joined(separator: ",")))
        """
        let universeResult = DatabaseManager.shared.executeQuery(universeQuery)
        if case .success(let rows) = universeResult {
            for row in rows {
                if let systemId = row["solarsystem_id"] as? Int,
                   let regionName = row["regionName"] as? String {
                    self.regionNames[systemId] = regionName
                }
            }
        }
    }
    
    func getIconName(typeId: Int) -> String? {
        return typeIcons[typeId]
    }
} 
