import SwiftUI

struct CorpStructureView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpStructureViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var error: Error?
    @State private var showError = false
    @State private var showSettings = false
    @AppStorage("structureFuelMonitorDays") private var fuelMonitorDays: Int = 7 {
        didSet {
            viewModel.updateLowFuelStructures(within: fuelMonitorDays)
        }
    }

    @State private var tempDays: String = ""
    @AppStorage("useEnglishSystemNames") private var useEnglishSystemNames: Bool = true

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
                if !viewModel.lowFuelStructuresCache.isEmpty {
                    Section(
                        header: Text(
                            String(
                                format: NSLocalizedString("Corp_Structure_Low_Fuel", comment: ""),
                                fuelMonitorDays
                            )
                        )
                        .foregroundColor(.red)
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .textCase(nil)
                    ) {
                        ForEach(viewModel.lowFuelStructuresCache.indices, id: \.self) { index in
                            let structure = viewModel.lowFuelStructuresCache[index]
                            if let typeId = structure["type_id"] as? Int {
                                StructureCell(
                                    structure: structure,
                                    iconName: viewModel.getIconName(typeId: typeId), isLowFuel: true
                                )
                            }
                        }
                    }
                }

                // 所有建筑列表
                structureListView
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
        .navigationTitle(NSLocalizedString("Corp_Structure_Title", comment: ""))
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
                                ForEach(
                                    [
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_1Week", comment: ""
                                            ),
                                            days: 7
                                        ),
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_2Weeks", comment: ""
                                            ),
                                            days: 14
                                        ),
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_3Weeks", comment: ""
                                            ),
                                            days: 21
                                        ),
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_1Month", comment: ""
                                            ),
                                            days: 30
                                        ),
                                        (
                                            name: NSLocalizedString(
                                                "Corp_Structure_Monitor_2Months", comment: ""
                                            ),
                                            days: 60
                                        ),
                                    ], id: \.days
                                ) { option in
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
                            .navigationTitle(
                                NSLocalizedString("Corp_Structure_Monitor_Time", comment: "")
                            )
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack {
                                Text(NSLocalizedString("Corp_Structure_Monitor_Time", comment: ""))
                                Spacer()
                                Text(
                                    String(
                                        format: NSLocalizedString(
                                            "Corp_Structure_Days", comment: ""
                                        ), fuelMonitorDays
                                    )
                                )
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .navigationTitle(NSLocalizedString("Corp_Structure_Settings", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(NSLocalizedString("Corp_Structure_Done", comment: "")) {
                            showSettings = false
                        }
                    }
                }
            }
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text(NSLocalizedString("Corp_Structure_Error", comment: "")),
                message: Text(
                    error?.localizedDescription
                        ?? NSLocalizedString("Corp_Structure_Unknown_Error", comment: "")),
                dismissButton: .default(Text(NSLocalizedString("Corp_Structure_OK", comment: ""))) {
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
            Text(NSLocalizedString("Corp_Structure_No_Data", comment: ""))
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var structureListView: some View {
        ForEach(viewModel.locationKeys, id: \.self) { location in
            if let structures = viewModel.groupedStructures[location] {
                Section(
                    header: {
                        if let systemId = structures.first?["system_id"] as? Int,
                            let securityLevel = viewModel.regionSecs[systemId]
                        {
                            (Text(formatSystemSecurity(securityLevel))
                                .foregroundColor(getSecurityColor(securityLevel)) + Text(" ")
                                + Text(location))
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(nil)
                        } else {
                            Text(location)
                                .fontWeight(.bold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(nil)
                        }
                    }()
                ) {
                    ForEach(structures.indices, id: \.self) { index in
                        let structure = structures[index]
                        if let typeId = structure["type_id"] as? Int {
                            StructureCell(
                                structure: structure,
                                iconName: viewModel.getIconName(typeId: typeId)
                            )
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
                    .stroke(
                        isLowFuel
                            ? .red : getStateColor(state: structure["state"] as? String ?? ""),
                        lineWidth: 2
                    )
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
                Text(
                    structure["name"] as? String
                        ?? NSLocalizedString("Corp_Structure_Unknown", comment: "")
                )
                .font(.headline)
                .lineLimit(1)

                if let fuelExpires = structure["fuel_expires"] as? String {
                    HStack {
                        Text(NSLocalizedString("Corp_Structure_Fuel_Expires", comment: ""))
                        Text(formatDateTime(fuelExpires).localTime)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .font(.subheadline)

                    HStack {
                        Text(NSLocalizedString("Corp_Structure_Time_Remaining", comment: ""))
                        Text(formatDateTime(fuelExpires).remainingTime)
                            .foregroundColor(isLowFuel ? .red : .secondary)
                    }
                    .font(.subheadline)
                }

                HStack {
                    Text(NSLocalizedString("Corp_Structure_Status", comment: ""))
                    Text(getStateText(state: structure["state"] as? String ?? ""))
                        .foregroundColor(getStateColor(state: structure["state"] as? String ?? ""))
                }
                .font(.subheadline)

                if let services = structure["services"] as? [[String: String]] {
                    HStack {
                        Text(NSLocalizedString("Corp_Structure_Services", comment: ""))
                        ForEach(services, id: \.["name"]) { service in
                            if let name = service["name"], let state = service["state"] {
                                Text(name)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        state == "online"
                                            ? Color.green.opacity(0.2) : Color.red.opacity(0.2)
                                    )
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

    private func formatDateTime(_ dateString: String) -> (localTime: String, remainingTime: String)
    {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return ("error time format", "error time format")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let localTime =
            formatter.string(from: date)
            + NSLocalizedString("Corp_Structure_Time_Format_UTC", comment: "")

        let remainingTime = date.timeIntervalSince(Date())
        let days = Int(remainingTime / (24 * 3600))
        let hours = Int((remainingTime.truncatingRemainder(dividingBy: 24 * 3600)) / 3600)
        let minutes = Int((remainingTime.truncatingRemainder(dividingBy: 3600)) / 60)

        let remainingTimeString: String
        if days > 0 {
            if hours > 0 {
                remainingTimeString = String(
                    format: NSLocalizedString("Corp_Structure_Time_Format_Days_Hours", comment: ""),
                    days, hours
                )
            } else {
                remainingTimeString = String(
                    format: NSLocalizedString("Corp_Structure_Time_Format_Days", comment: ""), days
                )
            }
        } else if hours > 0 {
            remainingTimeString = String(
                format: NSLocalizedString("Corp_Structure_Time_Format_Hours", comment: ""), hours
            )
        } else {
            remainingTimeString = String(
                format: NSLocalizedString("Corp_Structure_Time_Format_Minutes", comment: ""),
                minutes
            )
        }

        return (localTime, remainingTimeString)
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
            return NSLocalizedString("Corp_Structure_State_Shield_Vulnerable", comment: "")
        case "armor_vulnerable":
            return NSLocalizedString("Corp_Structure_State_Armor_Vulnerable", comment: "")
        case "armor_reinforce":
            return NSLocalizedString("Corp_Structure_State_Armor_Reinforce", comment: "")
        case "hull_vulnerable":
            return NSLocalizedString("Corp_Structure_State_Hull_Vulnerable", comment: "")
        case "hull_reinforce":
            return NSLocalizedString("Corp_Structure_State_Hull_Reinforce", comment: "")
        case "online_deprecated":
            return NSLocalizedString("Corp_Structure_State_Online_Deprecated", comment: "")
        case "anchor_vulnerable":
            return NSLocalizedString("Corp_Structure_State_Anchor_Vulnerable", comment: "")
        case "anchoring":
            return NSLocalizedString("Corp_Structure_State_Anchoring", comment: "")
        case "deploy_vulnerable":
            return NSLocalizedString("Corp_Structure_State_Deploy_Vulnerable", comment: "")
        case "fitting_invulnerable":
            return NSLocalizedString("Corp_Structure_State_Fitting_Invulnerable", comment: "")
        case "unanchored":
            return NSLocalizedString("Corp_Structure_State_Unanchored", comment: "")
        default:
            return NSLocalizedString("Corp_Structure_State_Unknown", comment: "")
        }
    }
}

@MainActor
class CorpStructureViewModel: ObservableObject {
    @Published var structures: [[String: Any]] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lowFuelStructuresCache: [[String: Any]] = []
    private var typeIcons: [Int: String] = [:]
    private var systemNames: [Int: String] = [:]
    private var regionNames: [Int: String] = [:]
    var regionSecs: [Int: Double] = [:]
    private let characterId: Int
    private var currentMonitorDays: Int

    private var useEnglishSystemNames: Bool {
        UserDefaults.standard.bool(forKey: "useEnglishSystemNames")
    }

    init(characterId: Int) {
        self.characterId = characterId
        // 从 UserDefaults 获取保存的监控时间
        currentMonitorDays = UserDefaults.standard.integer(forKey: "structureFuelMonitorDays")
        if currentMonitorDays == 0 {
            currentMonitorDays = 7
        }

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

    // 获取燃料不足的建筑，按照燃料耗尽时间升序排序
    func updateLowFuelStructures(within days: Int = 7) {
        let monitorDays = days <= 0 ? 7 : days
        currentMonitorDays = monitorDays

        lowFuelStructuresCache = structures.filter { structure in
            guard let fuelExpires = structure["fuel_expires"] as? String,
                let expirationDate = ISO8601DateFormatter().date(from: fuelExpires)
            else {
                return false
            }

            let timeInterval = expirationDate.timeIntervalSince(Date())
            return timeInterval > 0 && timeInterval <= Double(monitorDays) * 24 * 3600
        }.sorted { structure1, structure2 in
            guard let fuelExpires1 = structure1["fuel_expires"] as? String,
                let fuelExpires2 = structure2["fuel_expires"] as? String,
                let date1 = ISO8601DateFormatter().date(from: fuelExpires1),
                let date2 = ISO8601DateFormatter().date(from: fuelExpires2)
            else {
                return false
            }
            return date1 < date2
        }
    }

    var locationKeys: [String] {
        Array(groupedStructures.keys).sorted()
    }

    var groupedStructures: [String: [[String: Any]]] {
        var groups: [String: [[String: Any]]] = [:]
        for structure in structures {
            if let systemId = structure["system_id"] as? Int {
                let systemName = systemNames[systemId] ?? "Unknown"
                let regionName = regionNames[systemId] ?? "Unknown"
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
                "name": structure.name ?? "Unknown",
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
        // 更新低燃料缓存，使用当前的监控天数
        updateLowFuelStructures(within: currentMonitorDays)
    }

    private func loadTypeIcons(typeIds: [Int]) async {
        let query =
            "SELECT type_id, icon_filename FROM types WHERE type_id IN (\(typeIds.map(String.init).joined(separator: ",")))"
        let result = DatabaseManager.shared.executeQuery(query)
        if case let .success(rows) = result {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                    let iconFilename = row["icon_filename"] as? String
                {
                    typeIcons[typeId] = iconFilename
                }
            }
        }
    }

    private func loadLocationInfo(systemIds: [Int]) async {
        // 1. 获取星系名称
        let systemQuery = """
                SELECT solarSystemID, solarSystemName, solarSystemName_en
                FROM solarsystems
                WHERE solarSystemID IN (\(Array(systemIds).map { String($0) }.joined(separator: ",")))
            """
        let systemResult = DatabaseManager.shared.executeQuery(systemQuery)
        if case let .success(rows) = systemResult {
            for row in rows {
                if let systemId = row["solarSystemID"] as? Int,
                    let systemNameLocal = row["solarSystemName"] as? String,
                    let systemNameEn = row["solarSystemName_en"] as? String
                {
                    let systemName = useEnglishSystemNames ? systemNameEn : systemNameLocal
                    systemNames[systemId] = systemName
                }
            }
        }

        // 2. 获取星域信息
        let universeQuery = """
                SELECT DISTINCT u.solarsystem_id, u.region_id, 
                       r.regionName, r.regionName_en
                FROM universe u
                JOIN regions r ON r.regionID = u.region_id
                WHERE u.solarsystem_id IN (\(Array(systemIds).map { String($0) }.joined(separator: ",")))
            """
        let universeResult = DatabaseManager.shared.executeQuery(universeQuery)
        if case let .success(rows) = universeResult {
            for row in rows {
                if let systemId = row["solarsystem_id"] as? Int,
                    let regionNameLocal = row["regionName"] as? String,
                    let regionNameEn = row["regionName_en"] as? String
                {
                    let regionName = useEnglishSystemNames ? regionNameEn : regionNameLocal
                    regionNames[systemId] = regionName
                }
            }
        }

        // 3. 获取星系安等
        let systemSecQuery = """
                SELECT solarsystem_id, system_security
                FROM universe 
                WHERE solarsystem_id IN (\(systemIds.map(String.init).joined(separator: ",")))
            """
        let systemSecResult = DatabaseManager.shared.executeQuery(systemSecQuery)
        if case let .success(rows) = systemSecResult {
            for row in rows {
                if let systemId = row["solarsystem_id"] as? Int,
                    let systemSecurity = row["system_security"] as? Double
                {
                    regionSecs[systemId] = systemSecurity
                }
            }
        }
    }

    func getIconName(typeId: Int) -> String? {
        return typeIcons[typeId]
    }
}
