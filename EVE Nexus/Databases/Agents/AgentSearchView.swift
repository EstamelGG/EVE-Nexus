import SwiftUI
import Kingfisher

// UIViewController扩展，用于查找导航控制器
extension UIViewController {
    func findNavigationController() -> UINavigationController? {
        if let nav = self as? UINavigationController {
            return nav
        }
        
        if let nav = self.navigationController {
            return nav
        }
        
        for child in children {
            if let nav = child.findNavigationController() {
                return nav
            }
        }
        
        if let presented = presentedViewController {
            if let nav = presented.findNavigationController() {
                return nav
            }
        }
        
        return nil
    }
}

struct DropdownOption: Identifiable {
    let id: Int
    let value: String
    let key: String
    
    init(id: Int, value: String, key: String = "") {
        self.id = id
        self.value = value
        self.key = key.isEmpty ? "\(id)" : key
    }
}

// 搜索条件结构体
struct SearchConditions {
    var divisionID: Int?
    var level: Int?
    var securityLevel: String?
    var factionID: Int?
    var corporationID: Int?
    var isLocatorOnly: Bool
}

// 代理人项目结构体
struct AgentItem: Identifiable {
    let id = UUID()
    let agentID: Int
    let name: String
    let level: Int
    let corporationID: Int
    let divisionID: Int
    let isLocator: Bool
    let locationID: Int
    let locationName: String
    let solarSystemID: Int?
    let solarSystemName: String?
}

struct AgentSearchRootView: View {
    @ObservedObject var databaseManager: DatabaseManager
    
    var body: some View {
        NavigationStack {
            AgentSearchView(databaseManager: databaseManager)
        }
    }
}

struct AgentSearchView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var isNavigatingToResults = false
    @State private var searchResultsDestination: String? = nil
    
    // 过滤条件
    @State private var selectedDivisionID: Int?
    @State private var selectedLevel: Int?
    @State private var selectedSecurityLevel: String?
    @State private var selectedFactionID: Int?
    @State private var selectedCorporationID: Int?
    @State private var isLocatorOnly = false
    
    // 可用的选项数据
    @State private var availableFactions: [(Int, String)] = []
    @State private var availableCorporations: [(Int, String)] = []
    
    // 部门数据
    let divisions = [
        (18, NSLocalizedString("Division_Research", comment: "研发")),
        (22, NSLocalizedString("Division_Distribution", comment: "物流")),
        (23, NSLocalizedString("Division_Mining", comment: "采矿")),
        (24, NSLocalizedString("Division_Security", comment: "安全"))
    ]
    
    // 等级数据
    let levels = [
        (1, "Level 1"),
        (2, "Level 2"),
        (3, "Level 3"),
        (4, "Level 4"),
        (5, "Level 5")
    ]
    
    // 安全等级选项
    let securityLevels = [
        ("highsec", NSLocalizedString("Security_HighSec", comment: "高安")),
        ("lowsec", NSLocalizedString("Security_LowSec", comment: "低安")),
        ("nullsec", NSLocalizedString("Security_NullSec", comment: "零安"))
    ]
    
    var body: some View {
        VStack {
            List {
                // 所有过滤条件放在同一个Section中
                Section(header: Text("过滤条件")) {
                    // 1. 部门过滤
                    Picker("部门", selection: $selectedDivisionID) {
                        Text("所有部门").tag(nil as Int?)
                        ForEach(divisions, id: \.0) { division in
                            Text(division.1).tag(division.0 as Int?)
                        }
                    }
                    
                    // 2. 等级过滤
                    Picker("等级", selection: $selectedLevel) {
                        Text("所有等级").tag(nil as Int?)
                        ForEach(levels, id: \.0) { level in
                            Text(level.1).tag(level.0 as Int?)
                        }
                    }
                    
                    // 3. 安全等级过滤
                    Picker("安全等级", selection: $selectedSecurityLevel) {
                        Text("所有安全等级").tag(nil as String?)
                        ForEach(securityLevels, id: \.0) { security in
                            Text(security.1).tag(security.0 as String?)
                        }
                    }
                    
                    // 4. 势力过滤
                    Picker("势力", selection: $selectedFactionID) {
                        Text("所有势力").tag(nil as Int?)
                        ForEach(availableFactions, id: \.0) { faction in
                            Text(faction.1).tag(faction.0 as Int?)
                        }
                    }
                    .onChange(of: selectedFactionID) { _, newValue in
                        selectedCorporationID = nil
                        if let factionID = newValue {
                            loadCorporationsForFaction(factionID)
                        }
                    }
                    
                    // 5. 军团过滤 (仅当选择了势力时显示)
                    if selectedFactionID != nil {
                        Picker("军团", selection: $selectedCorporationID) {
                            Text("所有军团").tag(nil as Int?)
                            ForEach(availableCorporations, id: \.0) { corp in
                                Text(corp.1).tag(corp.0 as Int?)
                            }
                        }
                    }
                    
                    // 6. 定位代理人开关
                    Toggle("仅显示定位代理人", isOn: $isLocatorOnly)
                }
            }
            
            Button(action: {
                isNavigatingToResults = true
                searchResultsDestination = "searchResults"
            }) {
                Text("搜索代理人")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("代理人搜索")
        .navigationDestination(isPresented: $isNavigatingToResults) {
            AgentSearchResultView(
                databaseManager: databaseManager,
                searchConditions: getSearchConditions(),
                title: "搜索结果"
            )
        }
        .onAppear {
            loadFactions()
        }
    }
    
    // 获取搜索条件
    private func getSearchConditions() -> SearchConditions {
        return SearchConditions(
            divisionID: selectedDivisionID,
            level: selectedLevel,
            securityLevel: selectedSecurityLevel,
            factionID: selectedFactionID,
            corporationID: selectedCorporationID,
            isLocatorOnly: isLocatorOnly
        )
    }
    
    // 加载所有势力
    private func loadFactions() {
        let query = """
            SELECT DISTINCT f.id, f.name
            FROM agents a
            JOIN npcCorporations c ON a.corporationID = c.corporation_id
            JOIN factions f ON c.faction_id = f.id
            ORDER BY f.name
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            availableFactions = rows.compactMap { row in
                guard let factionID = row["id"] as? Int,
                      let name = row["name"] as? String else {
                    return nil
                }
                return (factionID, name)
            }
        }
    }
    
    // 加载特定势力的军团
    private func loadCorporationsForFaction(_ factionID: Int) {
        let query = """
            SELECT DISTINCT c.corporation_id, c.name
            FROM agents a
            JOIN npcCorporations c ON a.corporationID = c.corporation_id
            WHERE c.faction_id = ?
            ORDER BY c.name
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionID]) {
            availableCorporations = rows.compactMap { row in
                guard let corporationID = row["corporation_id"] as? Int,
                      let name = row["name"] as? String else {
                    return nil
                }
                return (corporationID, name)
            }
        }
    }
}

struct AgentSearchResultView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var searchResults: [AgentItem] = []
    @State private var isLoading = true
    
    // 分组数据
    @State private var factions: [(Int, String, String)] = [] // ID, 名称, 图标
    
    // 缓存数据
    @State private var corporationToFaction: [Int: Int] = [:]
    @State private var factionToCorporations: [Int: Set<Int>] = [:]
    @State private var factionAgentCounts: [Int: Int] = [:]
    
    let searchConditions: SearchConditions
    let title: String
    
    // 计算实际显示的标题
    private var displayTitle: String {
        if isLoading || factions.count == 1 {
            return ""
        }
        return title
    }
    
    var body: some View {
        ZStack {
            if isLoading {
                VStack {
                    ProgressView()
                    Text("加载中...")
                        .padding(.top, 16)
                }
            } else if searchResults.isEmpty {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                        .padding()
                    Text("没有找到符合条件的代理人")
                }
            } else if factions.count == 1 {
                // 如果只有一个势力，直接显示该势力的军团列表
                AgentCorporationsView(
                    databaseManager: databaseManager,
                    factionID: factions[0].0,
                    factionName: factions[0].1,
                    searchResults: searchResults.filter { agent in
                        if let corpFactionID = corporationToFaction[agent.corporationID] {
                            return corpFactionID == factions[0].0
                        }
                        return false
                    }
                )
            } else {
                // 显示势力列表
                List {
                    ForEach(factions, id: \.0) { factionID, factionName, iconName in
                        NavigationLink(destination: AgentCorporationsView(
                            databaseManager: databaseManager,
                            factionID: factionID,
                            factionName: factionName,
                            searchResults: searchResults.filter { agent in
                                if let corpFactionID = corporationToFaction[agent.corporationID] {
                                    return corpFactionID == factionID
                                }
                                return false
                            }
                        )) {
                            HStack {
                                IconManager.shared.loadImage(for: iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(4)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(factionName)
                                    Text("\(countAgentsInFaction(factionID)) 个代理人")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(displayTitle)
        .onAppear {
            searchAgents()
        }
    }
    
    // 搜索代理人
    private func searchAgents() {
        isLoading = true
        
        var conditions: [String] = []
        var parameters: [Any] = []
        
        // 添加部门过滤条件
        if let divisionID = searchConditions.divisionID {
            conditions.append("a.divisionID = ?")
            parameters.append(divisionID)
        }
        
        // 添加等级过滤条件
        if let level = searchConditions.level {
            conditions.append("a.level = ?")
            parameters.append(level)
        }
        
        // 添加安全等级过滤条件
        if let securityLevel = searchConditions.securityLevel {
            switch securityLevel {
            case "highsec":
                conditions.append("(s.security_status >= 0.5 OR st.security >= 0.5)")
            case "lowsec":
                conditions.append("((s.security_status < 0.5 AND s.security_status >= 0.0) OR (st.security < 0.5 AND st.security >= 0.0))")
            case "nullsec":
                conditions.append("((s.security_status < 0.0) OR (st.security < 0.0))")
            default:
                break
            }
        }
        
        // 添加势力过滤条件
        if let factionID = searchConditions.factionID {
            conditions.append("c.faction_id = ?")
            parameters.append(factionID)
        }
        
        // 添加军团过滤条件
        if let corporationID = searchConditions.corporationID {
            conditions.append("a.corporationID = ?")
            parameters.append(corporationID)
        }
        
        // 添加定位代理人过滤条件
        if searchConditions.isLocatorOnly {
            conditions.append("a.isLocator = 1")
        }
        
        // 构建查询
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        
        let query = """
            SELECT a.agent_id, n.itemName as name, a.level, a.corporationID, a.divisionID, a.isLocator, a.locationID,
                   l.itemName as locationName, a.solarSystemID, s.solarSystemName as solarSystemName,
                   c.name as corporationName, f.id as factionID, f.name as factionName, f.iconName as factionIcon,
                   c.icon_id as corporationIconID, d.name as divisionName
            FROM agents a
            JOIN invNames n ON a.agent_id = n.itemID
            LEFT JOIN invNames l ON a.locationID = l.itemID
            LEFT JOIN solarsystems s ON a.solarSystemID = s.solarSystemID
            LEFT JOIN stations st ON a.locationID = st.stationID
            JOIN npcCorporations c ON a.corporationID = c.corporation_id
            JOIN factions f ON c.faction_id = f.id
            LEFT JOIN divisions d ON a.divisionID = d.division_id
            \(whereClause)
            ORDER BY f.name, c.name, d.name, a.level DESC, n.itemName
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: parameters) {
            searchResults = rows.compactMap { row in
                guard let agentID = row["agent_id"] as? Int,
                      let name = row["name"] as? String,
                      let level = row["level"] as? Int,
                      let corporationID = row["corporationID"] as? Int,
                      let divisionID = row["divisionID"] as? Int,
                      let isLocator = row["isLocator"] as? Int,
                      let locationID = row["locationID"] as? Int else {
                    return nil
                }
                
                let locationName = row["locationName"] as? String ?? "未知位置"
                let solarSystemID = row["solarSystemID"] as? Int
                let solarSystemName = row["solarSystemName"] as? String
                
                return AgentItem(
                    agentID: agentID,
                    name: name,
                    level: level,
                    corporationID: corporationID,
                    divisionID: divisionID,
                    isLocator: isLocator == 1,
                    locationID: locationID,
                    locationName: locationName,
                    solarSystemID: solarSystemID,
                    solarSystemName: solarSystemName
                )
            }
            
            // 初始化导航
            loadCorporationFactionMapping()
            updateFactions()
        }
        
        isLoading = false
    }
    
    // 加载军团-势力映射关系
    private func loadCorporationFactionMapping() {
        // 一次性查询所有军团和势力的映射关系
        let query = """
            SELECT c.corporation_id, c.faction_id
            FROM npcCorporations c
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query) {
            var corpToFaction: [Int: Int] = [:]
            var factionToCorps: [Int: Set<Int>] = [:]
            
            for row in rows {
                if let corporationID = row["corporation_id"] as? Int,
                   let factionID = row["faction_id"] as? Int {
                    corpToFaction[corporationID] = factionID
                    factionToCorps[factionID, default: []].insert(corporationID)
                }
            }
            
            self.corporationToFaction = corpToFaction
            self.factionToCorporations = factionToCorps
            
            // 预计算每个势力的代理人数量
            var counts: [Int: Int] = [:]
            for agent in searchResults {
                if let factionID = corpToFaction[agent.corporationID] {
                    counts[factionID, default: 0] += 1
                }
            }
            self.factionAgentCounts = counts
        }
    }
    
    // 更新势力列表
    private func updateFactions() {
        // 1. 首先获取所有代理人的军团ID
        let corporationIDs = Set(searchResults.map { $0.corporationID })
        
        if corporationIDs.isEmpty {
            self.factions = []
            return
        }
        
        // 2. 一次性查询所有军团所属的势力
        let placeholders = Array(repeating: "?", count: corporationIDs.count).joined(separator: ",")
        let query = """
            SELECT DISTINCT c.corporation_id, f.id as faction_id, f.name as faction_name, f.iconName as faction_icon
            FROM npcCorporations c
            JOIN factions f ON c.faction_id = f.id
            WHERE c.corporation_id IN (\(placeholders))
            ORDER BY f.name
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: Array(corporationIDs)) {
            // 3. 创建军团ID到势力ID的映射
            var corporationToFaction: [Int: (Int, String, String)] = [:]
            for row in rows {
                if let corporationID = row["corporation_id"] as? Int,
                   let factionID = row["faction_id"] as? Int,
                   let factionName = row["faction_name"] as? String {
                    let iconName = row["faction_icon"] as? String ?? "faction_default"
                    corporationToFaction[corporationID] = (factionID, factionName, iconName)
                }
            }
            
            // 4. 统计每个势力下的代理人数量
            var factionData: [Int: (String, String, Int)] = [:]
            
            for agent in searchResults {
                if let (factionID, factionName, iconName) = corporationToFaction[agent.corporationID] {
                    if let (name, icon, count) = factionData[factionID] {
                        factionData[factionID] = (name, icon, count + 1)
                    } else {
                        factionData[factionID] = (factionName, iconName, 1)
                    }
                }
            }
            
            // 5. 创建最终的势力列表
            let factionsList = factionData.map { (factionID, data) in
                (factionID, data.0, data.1)
            }.sorted { $0.1 < $1.1 }
            
            self.factions = factionsList
        } else {
            self.factions = []
        }
    }
    
    // 计算势力中的代理人数量
    private func countAgentsInFaction(_ factionID: Int) -> Int {
        // 使用预先计算的缓存数据
        return factionAgentCounts[factionID] ?? 0
    }
}

// 军团视图
struct AgentCorporationsView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let factionID: Int
    let factionName: String
    let searchResults: [AgentItem]
    
    @State private var corporations: [(Int, String, String)] = [] // ID, 名称, 图标
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if isLoading {
                // 加载时显示空视图，避免闪现
                Color.clear
            } else if corporations.count == 1 {
                // 如果只有一个军团，直接显示该军团的部门列表
                AgentDivisionsView(
                    databaseManager: databaseManager,
                    corporationID: corporations[0].0,
                    corporationName: corporations[0].1,
                    searchResults: searchResults.filter { $0.corporationID == corporations[0].0 }
                )
            } else {
                List {
                    ForEach(corporations, id: \.0) { corporationID, corporationName, iconName in
                        NavigationLink(destination: AgentDivisionsView(
                            databaseManager: databaseManager,
                            corporationID: corporationID,
                            corporationName: corporationName,
                            searchResults: searchResults.filter { $0.corporationID == corporationID }
                        )) {
                            HStack {
                                IconManager.shared.loadImage(for: iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(4)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(corporationName)
                                    Text("\(searchResults.filter { $0.corporationID == corporationID }.count) 个代理人")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                .navigationTitle(factionName)
            }
        }
        .onAppear {
            loadCorporations()
        }
    }
    
    private func loadCorporations() {
        isLoading = true
        // 一次性查询指定势力下的所有军团
        let query = """
            SELECT c.corporation_id, c.name, c.icon_id, i.iconFile_new
            FROM npcCorporations c
            LEFT JOIN iconIDs i ON c.icon_id = i.icon_id
            WHERE c.faction_id = ?
            ORDER BY c.name
        """
        
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [factionID]) {
            let allCorporations = rows.compactMap { row -> (Int, String, String)? in
                guard let corporationID = row["corporation_id"] as? Int,
                      let name = row["name"] as? String else {
                    return nil
                }
                
                let iconFile = row["iconFile_new"] as? String ?? "corporation_default"
                return (corporationID, name, iconFile)
            }
            
            // 过滤出有代理人的军团
            let corporationIDs = Set(searchResults.map { $0.corporationID })
            let filteredCorporations = allCorporations.filter { corporationIDs.contains($0.0) }
            
            self.corporations = filteredCorporations
        }
        isLoading = false
    }
}

// 部门视图
struct AgentDivisionsView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let corporationID: Int
    let corporationName: String
    let searchResults: [AgentItem]
    
    @State private var divisions: [(Int, String, String)] = [] // ID, 名称, 图标
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if isLoading {
                // 加载时显示空视图，避免闪现
                Color.clear
            } else if divisions.count == 1 {
                // 如果只有一个部门，直接显示该部门的等级列表
                AgentLevelsView(
                    databaseManager: databaseManager,
                    divisionID: divisions[0].0,
                    divisionName: divisions[0].1,
                    searchResults: searchResults.filter { $0.divisionID == divisions[0].0 }
                )
            } else {
                List {
                    ForEach(divisions, id: \.0) { divisionID, divisionName, iconName in
                        NavigationLink(destination: AgentLevelsView(
                            databaseManager: databaseManager,
                            divisionID: divisionID,
                            divisionName: divisionName,
                            searchResults: searchResults.filter { $0.divisionID == divisionID }
                        )) {
                            HStack {
                                Image(iconName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 40, height: 40)
                                    .cornerRadius(4)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(divisionName)
                                    Text("\(searchResults.filter { $0.divisionID == divisionID }.count) 个代理人")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                .navigationTitle(corporationName)
            }
        }
        .onAppear {
            loadDivisions()
        }
    }
    
    private func loadDivisions() {
        isLoading = true
        var uniqueDivisions = Set<Int>()
        var divisionsList: [(Int, String, String)] = []
        
        // 部门名称和图标映射
        let divisionData: [Int: (String, String)] = [
            24: ("安全", "gunnery_turret"),
            23: ("采矿", "miner"),
            22: ("物流", "cargo_fit"),
            18: ("研发", "pg")
        ]
        
        for agent in searchResults {
            if !uniqueDivisions.contains(agent.divisionID) {
                uniqueDivisions.insert(agent.divisionID)
                let (divisionName, iconName) = divisionData[agent.divisionID] ?? ("未知部门", "agent")
                divisionsList.append((agent.divisionID, divisionName, iconName))
            }
        }
        
        self.divisions = divisionsList.sorted(by: { $0.0 > $1.0 })
        isLoading = false
    }
}

// 等级视图
struct AgentLevelsView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let divisionID: Int
    let divisionName: String
    let searchResults: [AgentItem]
    
    @State private var levels: [(Int, String)] = []
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if isLoading {
                // 加载时显示空视图，避免闪现
                Color.clear
            } else if levels.count == 1 {
                // 如果只有一个等级，直接显示该等级的代理人列表
                AgentListView(
                    level: levels[0].0,
                    levelName: levels[0].1,
                    searchResults: searchResults.filter { $0.level == levels[0].0 },
                    databaseManager: databaseManager
                )
            } else {
                List {
                    ForEach(levels, id: \.0) { level, levelName in
                        NavigationLink(destination: AgentListView(
                            level: level,
                            levelName: levelName,
                            searchResults: searchResults.filter { $0.level == level },
                            databaseManager: databaseManager
                        )) {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(getLevelColor(level))
                                        .frame(width: 40, height: 40)
                                    Text("\(level)")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(levelName)
                                    Text("\(searchResults.filter { $0.level == level }.count) 个代理人")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                .navigationTitle(divisionName)
            }
        }
        .onAppear {
            loadLevels()
        }
    }
    
    private func loadLevels() {
        isLoading = true
        var uniqueLevels = Set<Int>()
        var levelsList: [(Int, String)] = []
        
        for agent in searchResults {
            if !uniqueLevels.contains(agent.level) {
                uniqueLevels.insert(agent.level)
                levelsList.append((agent.level, "Level \(agent.level)"))
            }
        }
        
        self.levels = levelsList.sorted(by: { $0.0 > $1.0 }) // 等级从高到低排序
        isLoading = false
    }
    
    // 根据等级获取颜色
    private func getLevelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color.gray
        case 2: return Color.green
        case 3: return Color.blue
        case 4: return Color.purple
        case 5: return Color.red
        default: return Color.gray
        }
    }
}

// 代理人单元格视图
struct AgentCellView: View {
    let agent: AgentItem
    @ObservedObject var databaseManager: DatabaseManager
    @State private var portraitImage: Image?
    @State private var isLoadingPortrait = true
    @State private var locationInfo: (name: String, security: Double?) = ("加载中...", nil)
    @State private var affiliationInfo: (factionName: String, corporationName: String) = ("", "")
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧头像
            ZStack {
                if isLoadingPortrait {
                    ProgressView()
                        .frame(width: 64, height: 64)
                } else if let image = portraitImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 64, height: 64)
            
            // 右侧信息
            VStack(alignment: .leading, spacing: 4) {
                // 名称
                Text(agent.name)
                    .font(.headline)
                
                // 位置信息
                LocationInfoView(
                    stationName: agent.solarSystemID == nil ? agent.locationName : nil,
                    solarSystemName: agent.solarSystemName ?? agent.locationName,
                    security: locationInfo.security,
                    locationId: agent.locationID > 0 ? Int64(agent.locationID) : nil,
                    font: .caption,
                    textColor: .secondary
                )
                
                // 势力和军团信息
                if !affiliationInfo.factionName.isEmpty && !affiliationInfo.corporationName.isEmpty {
                    Text("\(affiliationInfo.factionName) - \(affiliationInfo.corporationName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 标签行
                HStack(spacing: 8) {
                    // 等级标签
                    Text("L\(agent.level)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(getLevelColor(agent.level))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    
                    // 定位代理人标签
                    if agent.isLocator {
                        Text("定位代理人")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    
                    // 空间代理人标签
                    if agent.solarSystemID != nil {
                        Text("空间代理人")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            loadLocationInfo()
            loadPortrait()
        }
    }
    
    private func loadPortrait() {
        isLoadingPortrait = true
        
        Task {
            do {
                let uiImage = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: agent.agentID,
                    size: 128,
                    forceRefresh: false,
                    catchImage: true
                )
                portraitImage = Image(uiImage: uiImage)
                isLoadingPortrait = false
            } catch {
                isLoadingPortrait = false
                // 加载失败时不设置portraitImage，将显示默认图标
            }
        }
    }
    
    private func loadLocationInfo() {
        // 查询位置信息
        if let systemID = agent.solarSystemID {
            // 查询太阳系信息
            let query = """
                SELECT solarSystemName, security_status
                FROM solarsystems
                WHERE solarSystemID = ?
            """
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [systemID]) {
                if let row = rows.first,
                   let name = row["solarSystemName"] as? String {
                    let security = row["security_status"] as? Double
                    locationInfo = (name, security)
                }
            }
        } else {
            // 查询空间站信息
            let query = """
                SELECT stationName, security
                FROM stations
                WHERE stationID = ?
            """
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [agent.locationID]) {
                if let row = rows.first,
                   let name = row["stationName"] as? String {
                    let security = row["security"] as? Double
                    locationInfo = (name, security)
                }
            }
        }
        
        // 查询势力和军团信息
        let affiliationQuery = """
            SELECT c.name as corporationName, f.name as factionName
            FROM npcCorporations c
            JOIN factions f ON c.faction_id = f.id
            WHERE c.corporation_id = ?
        """
        
        if case .success(let rows) = databaseManager.executeQuery(affiliationQuery, parameters: [agent.corporationID]) {
            if let row = rows.first,
               let corporationName = row["corporationName"] as? String,
               let factionName = row["factionName"] as? String {
                affiliationInfo = (factionName, corporationName)
            }
        }
    }
    
    // 根据等级获取颜色
    private func getLevelColor(_ level: Int) -> Color {
        switch level {
        case 1: return Color.gray
        case 2: return Color.green
        case 3: return Color.blue
        case 4: return Color.purple
        case 5: return Color.red
        default: return Color.gray
        }
    }
}

// 代理人列表视图
struct AgentListView: View {
    let level: Int
    let levelName: String
    let searchResults: [AgentItem]
    @ObservedObject var databaseManager: DatabaseManager
    
    var body: some View {
        List {
            ForEach(searchResults) { agent in
                AgentCellView(agent: agent, databaseManager: databaseManager)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .navigationTitle(levelName)
    }
} 
