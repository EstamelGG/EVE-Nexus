import Kingfisher
import SwiftUI

// UIViewController扩展，用于查找导航控制器
extension UIViewController {
    func findNavigationController() -> UINavigationController? {
        if let nav = self as? UINavigationController {
            return nav
        }

        if let nav = navigationController {
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
    var agentType: Int?
}

// 代理人类型ID列表
let agentTypeIDs: [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
// 部门图标映射
let divisionIcons: [Int: String] = [
    24: "gunnery_turret",  // 安全
    23: "miner",  // 采矿
    22: "cargo_fit",  // 物流
    18: "pg",  // 研发
    25: "not_found",  // 工业家 - 商业大亨
    26: "not_found",  // 探险家
    27: "not_found",  // 工业家 - 制造商
    28: "not_found",  // 执法者
    29: "not_found",  // 自由战士
    37: "not_found",  // 星际捷运
]

// 获取代理人类型名称的函数
func getAgentTypeName(_ agentType: Int) -> String {
    switch agentType {
    case 1: return NSLocalizedString("Agent_Type_NonAgent", comment: "非代理人")
    case 2: return NSLocalizedString("Agent_Type_BasicAgent", comment: "基础代理人")
    case 3: return NSLocalizedString("Agent_Type_TutorialAgent", comment: "教程代理人")
    case 4: return NSLocalizedString("Agent_Type_ResearchAgent", comment: "研究代理人")
    case 5: return NSLocalizedString("Agent_Type_CONCORDAgent", comment: "CONCORD代理人")
    case 6:
        return NSLocalizedString("Agent_Type_GenericStorylineMissionAgent", comment: "通用剧情任务代理人")
    case 7: return NSLocalizedString("Agent_Type_StorylineMissionAgent", comment: "剧情任务代理人")
    case 8: return NSLocalizedString("Agent_Type_EventMissionAgent", comment: "事件任务代理人")
    case 9: return NSLocalizedString("Agent_Type_FactionalWarfareAgent", comment: "派系战争代理人")
    case 10: return NSLocalizedString("Agent_Type_EpicArcAgent", comment: "史诗弧线代理人")
    case 11: return NSLocalizedString("Agent_Type_AuraAgent", comment: "Aura代理人")
    case 12: return NSLocalizedString("Agent_Type_CareerAgent", comment: "职业代理人")
    case 13: return NSLocalizedString("Agent_Type_HeraldryAgent", comment: "纹章代理人")
    default: return NSLocalizedString("Agent_Type_Other", comment: "其他")
    }
}

// 获取代理人类型简短名称的函数
func getAgentTypeShortName(_ agentType: Int) -> String {
    switch agentType {
    case 1: return NSLocalizedString("Agent_Type_Short_NonAgent", comment: "非代理")
    case 2: return NSLocalizedString("Agent_Type_Short_BasicAgent", comment: "基础")
    case 3: return NSLocalizedString("Agent_Type_Short_TutorialAgent", comment: "教程")
    case 4: return NSLocalizedString("Agent_Type_Short_ResearchAgent", comment: "研究")
    case 5: return NSLocalizedString("Agent_Type_Short_CONCORDAgent", comment: "CONCORD")
    case 6:
        return NSLocalizedString("Agent_Type_Short_GenericStorylineMissionAgent", comment: "故事线")
    case 7: return NSLocalizedString("Agent_Type_Short_StorylineMissionAgent", comment: "剧情")
    case 8: return NSLocalizedString("Agent_Type_Short_EventMissionAgent", comment: "事件")
    case 9: return NSLocalizedString("Agent_Type_Short_FactionalWarfareAgent", comment: "派系战")
    case 10: return NSLocalizedString("Agent_Type_Short_EpicArcAgent", comment: "史诗")
    case 11: return NSLocalizedString("Agent_Type_Short_AuraAgent", comment: "Aura")
    case 12: return NSLocalizedString("Agent_Type_Short_CareerAgent", comment: "职业")
    case 13: return NSLocalizedString("Agent_Type_Short_HeraldryAgent", comment: "徽章")
    default: return NSLocalizedString("Agent_Type_Short_Other", comment: "其他")
    }
}

// 代理人项目结构体
struct AgentItem: Identifiable {
    let id = UUID()
    let agentID: Int
    let agentType: Int
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
    @State private var isSpaceAgentOnly = false  // 添加空间代理人筛选条件
    @State private var selectedAgentType: Int? = nil  // 不默认选择任何代理人类型

    // 可用的选项数据
    @State private var availableFactions: [(Int, String, String)] = []
    @State private var availableCorporations: [(Int, String, String)] = []
    @State private var availableDivisions: [(Int, String, String)] = []
    @State private var availableAgentTypes: [(Int, String)] = []

    // 等级数据
    let levels = [
        (1, "Level 1"),
        (2, "Level 2"),
        (3, "Level 3"),
        (4, "Level 4"),
        (5, "Level 5"),
    ]

    // 安全等级选项
    let securityLevels = [
        ("highsec", NSLocalizedString("Security_HighSec", comment: "高安")),
        ("lowsec", NSLocalizedString("Security_LowSec", comment: "低安")),
        ("nullsec", NSLocalizedString("Security_NullSec", comment: "零安")),
    ]

    var body: some View {
        VStack {
            List {
                // 所有过滤条件放在同一个Section中
                Section(header: Text(NSLocalizedString("Agent_Search_Filter", comment: "过滤条件"))) {
                    // 1. 部门过滤
                    Picker(
                        selection: $selectedDivisionID,
                        label: Text(NSLocalizedString("Agent_Search_Division", comment: "部门"))
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Divisions", comment: "所有部门")).tag(
                            nil as Int?)

                        // 主要部门ID列表
                        let mainDivisionIDs = [24, 23, 22, 18]

                        // 主要部门
                        ForEach(
                            availableDivisions.filter { mainDivisionIDs.contains($0.0) }, id: \.0
                        ) { division in
                            Text(division.1).tag(division.0 as Int?)
                        }

                        // 分隔线
                        Divider()

                        // 其他部门
                        ForEach(
                            availableDivisions.filter { !mainDivisionIDs.contains($0.0) }, id: \.0
                        ) { division in
                            Text(division.1).tag(division.0 as Int?)
                        }
                    }

                    // 2. 等级过滤
                    Picker(
                        NSLocalizedString("Agent_Search_Level", comment: "等级"),
                        selection: $selectedLevel
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Levels", comment: "所有等级")).tag(
                            nil as Int?)
                        ForEach(levels, id: \.0) { level in
                            Text(level.1).tag(level.0 as Int?)
                        }
                    }

                    // 3. 安全等级过滤
                    Picker(
                        NSLocalizedString("Agent_Search_Security", comment: "安全等级"),
                        selection: $selectedSecurityLevel
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Security", comment: "所有安全等级")).tag(
                            nil as String?)
                        ForEach(securityLevels, id: \.0) { security in
                            Text(security.1).tag(security.0 as String?)
                        }
                    }

                    // 4. 势力过滤
                    Picker(
                        selection: $selectedFactionID,
                        label: Text(NSLocalizedString("Agent_Search_Faction", comment: "势力"))
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Factions", comment: "所有势力")).tag(
                            nil as Int?)
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
                        Picker(
                            selection: $selectedCorporationID,
                            label: Text(
                                NSLocalizedString("Agent_Search_Corporation", comment: "军团"))
                        ) {
                            Text(
                                NSLocalizedString("Agent_Search_All_Corporations", comment: "所有军团")
                            ).tag(nil as Int?)
                            ForEach(availableCorporations, id: \.0) { corp in
                                Text(corp.1).tag(corp.0 as Int?)
                            }
                        }
                    }

                    // 7. 代理人类型过滤
                    Picker(
                        NSLocalizedString("Agent_Search_Type", comment: "代理人类型"),
                        selection: $selectedAgentType
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Types", comment: "所有代理人类型")).tag(
                            nil as Int?)

                        // 主要代理人类型ID列表
                        let mainAgentTypeIDs = [2, 4, 6, 9]
                        // 次要代理人类型ID列表
                        let secondaryAgentTypeIDs = [5, 10, 12]

                        // 主要类型
                        ForEach(
                            availableAgentTypes.filter { mainAgentTypeIDs.contains($0.0) }, id: \.0
                        ) { type in
                            Text(getAgentTypeName(type.0)).tag(type.0 as Int?)
                        }

                        // 第一个分隔线
                        Divider()

                        // 次要类型
                        ForEach(
                            availableAgentTypes.filter { secondaryAgentTypeIDs.contains($0.0) },
                            id: \.0
                        ) { type in
                            Text(getAgentTypeName(type.0)).tag(type.0 as Int?)
                        }

                        // 第二个分隔线
                        Divider()

                        // 其他类型
                        ForEach(
                            availableAgentTypes.filter {
                                !mainAgentTypeIDs.contains($0.0)
                                    && !secondaryAgentTypeIDs.contains($0.0)
                            }, id: \.0
                        ) { type in
                            Text(getAgentTypeName(type.0)).tag(type.0 as Int?)
                        }
                    }
                }
                
                // 定位代理人筛选选项单独放在一个Section中
                Section() {
                    // 定位代理人开关
                    HStack {
                        Toggle(isOn: $isLocatorOnly) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString("Agent_Search_Locator_Only", comment: "仅显示定位代理人")
                                )
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                                Text(
                                    NSLocalizedString(
                                        "Agent_Search_Locator_Description", comment: "提供寻人服务的代理人"
                                    )
                                )
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    // 空间代理人开关
                    HStack {
                        Toggle(isOn: $isSpaceAgentOnly) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    NSLocalizedString("Agent_Search_Space_Only", comment: "仅显示空间代理人")
                                )
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                                Text(
                                    NSLocalizedString(
                                        "Agent_inspace_Description", comment: "空间代理人描述"
                                    )
                                )
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            Button(action: {
                isNavigatingToResults = true
                searchResultsDestination = "searchResults"
            }) {
                Text(NSLocalizedString("Agent_Search_Button", comment: "搜索代理人"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle(NSLocalizedString("Agent_Search_Title", comment: "代理人搜索"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: resetFilters) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationDestination(isPresented: $isNavigatingToResults) {
            AgentListHierarchyView(
                databaseManager: databaseManager,
                level: .faction,
                searchResults: searchAgents(),
                title: NSLocalizedString("Agent_Search_Results", comment: "搜索结果")
            )
        }
        .onAppear {
            loadDivisions()
            loadFactions()
            loadAgentTypes()
        }
    }

    // 重置所有过滤条件
    private func resetFilters() {
        selectedDivisionID = nil
        selectedLevel = nil
        selectedSecurityLevel = nil
        selectedFactionID = nil
        selectedCorporationID = nil
        isLocatorOnly = false
        isSpaceAgentOnly = false  // 重置空间代理人筛选条件
        selectedAgentType = nil  // 重置为nil
    }

    // 搜索代理人
    private func searchAgents() -> [AgentItem] {
        var conditions: [String] = []
        var parameters: [Any] = []

        // 添加部门过滤条件
        if let divisionID = selectedDivisionID {
            conditions.append("a.divisionID = ?")
            parameters.append(divisionID)
        }

        // 添加等级过滤条件
        if let level = selectedLevel {
            conditions.append("a.level = ?")
            parameters.append(level)
        }

        // 添加安全等级过滤条件
        if let securityLevel = selectedSecurityLevel {
            switch securityLevel {
            case "highsec":
                conditions.append("(s.security_status >= 0.5 OR st.security >= 0.5)")
            case "lowsec":
                conditions.append(
                    "((s.security_status < 0.5 AND s.security_status >= 0.0) OR (st.security < 0.5 AND st.security >= 0.0))"
                )
            case "nullsec":
                conditions.append("((s.security_status < 0.0) OR (st.security < 0.0))")
            default:
                break
            }
        }

        // 添加势力过滤条件
        if let factionID = selectedFactionID {
            conditions.append("c.faction_id = ?")
            parameters.append(factionID)
        }

        // 添加军团过滤条件
        if let corporationID = selectedCorporationID {
            conditions.append("a.corporationID = ?")
            parameters.append(corporationID)
        }

        // 添加定位代理人过滤条件
        if isLocatorOnly {
            conditions.append("a.isLocator = 1")
        }
        
        // 添加空间代理人过滤条件
        if isSpaceAgentOnly {
            conditions.append("a.solarSystemID IS NOT NULL")
        }

        // 添加代理人类型过滤条件
        if let agentType = selectedAgentType {
            conditions.append("a.agent_type = ?")
            parameters.append(agentType)
        }

        // 构建查询
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")

        let query = """
                SELECT a.agent_id, a.agent_type, n.itemName as name, a.level, a.corporationID, a.divisionID, a.isLocator, a.locationID,
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

        var results: [AgentItem] = []

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: parameters) {
            results = rows.compactMap { row in
                guard let agentID = row["agent_id"] as? Int,
                    let name = row["name"] as? String,
                    let level = row["level"] as? Int,
                    let corporationID = row["corporationID"] as? Int,
                    let divisionID = row["divisionID"] as? Int,
                    let isLocator = row["isLocator"] as? Int,
                    let locationID = row["locationID"] as? Int
                else {
                    return nil
                }

                let locationName = row["locationName"] as? String ?? "未知位置"
                let solarSystemID = row["solarSystemID"] as? Int
                let solarSystemName = row["solarSystemName"] as? String
                let agentType = row["agent_type"] as? Int ?? 0

                return AgentItem(
                    agentID: agentID,
                    agentType: agentType,
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
        }

        return results
    }

    // 加载所有势力
    private func loadFactions() {
        let query = """
                SELECT DISTINCT f.id, f.name, f.iconName
                FROM agents a
                JOIN npcCorporations c ON a.corporationID = c.corporation_id
                JOIN factions f ON c.faction_id = f.id
                ORDER BY f.name
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            availableFactions = rows.compactMap { row in
                guard let factionID = row["id"] as? Int,
                    let name = row["name"] as? String
                else {
                    return nil
                }
                let iconName = row["iconName"] as? String ?? "not_found"
                return (factionID, name, iconName)
            }
        }
    }

    // 加载所有部门
    private func loadDivisions() {
        let query = """
                SELECT DISTINCT d.division_id, d.name
                FROM divisions d
                JOIN agents a ON d.division_id = a.divisionID
                ORDER BY d.division_id
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            var mainDivisions: [(Int, String, String)] = []
            var otherDivisions: [(Int, String, String)] = []

            // 主要部门ID列表（按指定顺序）
            let mainDivisionIDs = [24, 23, 22, 18]

            for row in rows {
                guard let divisionID = row["division_id"] as? Int,
                    let name = row["name"] as? String
                else {
                    continue
                }

                let iconName = divisionIcons[divisionID] ?? "agent"
                let divisionTuple = (divisionID, name, iconName)

                if mainDivisionIDs.contains(divisionID) {
                    mainDivisions.append(divisionTuple)
                } else {
                    otherDivisions.append(divisionTuple)
                }
            }

            // 按指定顺序排序主要部门
            mainDivisions.sort { first, second in
                guard let firstIndex = mainDivisionIDs.firstIndex(of: first.0),
                    let secondIndex = mainDivisionIDs.firstIndex(of: second.0)
                else {
                    return false
                }
                return firstIndex < secondIndex
            }

            // 按ID排序其他部门
            otherDivisions.sort { $0.0 < $1.0 }

            // 合并两组部门
            availableDivisions = mainDivisions + otherDivisions
        }
    }

    // 加载特定势力的军团
    private func loadCorporationsForFaction(_ factionID: Int) {
        let query = """
                SELECT DISTINCT c.corporation_id, c.name, c.icon_id, i.iconFile_new
                FROM agents a
                JOIN npcCorporations c ON a.corporationID = c.corporation_id
                JOIN iconIDs i ON c.icon_id = i.icon_id
                WHERE c.faction_id = ?
                ORDER BY c.name
            """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [factionID]) {
            availableCorporations = rows.compactMap { row in
                guard let corporationID = row["corporation_id"] as? Int,
                    let name = row["name"] as? String,
                    let iconFile = row["iconFile_new"] as? String
                else {
                    return nil
                }
                return (corporationID, name, iconFile)
            }
        }
    }

    // 加载可用的代理人类型
    private func loadAgentTypes() {
        let query = """
                SELECT DISTINCT agent_type
                FROM agents
                ORDER BY agent_type
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            var mainTypes: [(Int, String)] = []
            var secondaryTypes: [(Int, String)] = []
            var otherTypes: [(Int, String)] = []

            // 主要代理人类型ID列表（按指定顺序）
            let mainAgentTypeIDs = [2, 4, 6, 9]
            // 次要代理人类型ID列表（按指定顺序）
            let secondaryAgentTypeIDs = [5, 10, 12]

            for row in rows {
                if let agentType = row["agent_type"] as? Int {
                    // 直接保存类型ID和ID的字符串表示
                    let typeTuple = (agentType, "\(agentType)")

                    if mainAgentTypeIDs.contains(agentType) {
                        mainTypes.append(typeTuple)
                    } else if secondaryAgentTypeIDs.contains(agentType) {
                        secondaryTypes.append(typeTuple)
                    } else {
                        otherTypes.append(typeTuple)
                    }
                }
            }

            // 按指定顺序排序主要类型
            mainTypes.sort { first, second in
                guard let firstIndex = mainAgentTypeIDs.firstIndex(of: first.0),
                    let secondIndex = mainAgentTypeIDs.firstIndex(of: second.0)
                else {
                    return false
                }
                return firstIndex < secondIndex
            }

            // 按指定顺序排序次要类型
            secondaryTypes.sort { first, second in
                guard let firstIndex = secondaryAgentTypeIDs.firstIndex(of: first.0),
                    let secondIndex = secondaryAgentTypeIDs.firstIndex(of: second.0)
                else {
                    return false
                }
                return firstIndex < secondIndex
            }

            // 按ID排序其他类型
            otherTypes.sort { $0.0 < $1.0 }

            // 合并三组类型
            availableAgentTypes = mainTypes + secondaryTypes + otherTypes
        } else {
            // 如果查询失败，使用默认的代理人类型ID列表
            let mainAgentTypeIDs = [2, 4, 6, 9]
            let secondaryAgentTypeIDs = [5, 10, 12]
            var mainTypes: [(Int, String)] = []
            var secondaryTypes: [(Int, String)] = []
            var otherTypes: [(Int, String)] = []

            for typeID in agentTypeIDs {
                let typeTuple = (typeID, "\(typeID)")
                if mainAgentTypeIDs.contains(typeID) {
                    mainTypes.append(typeTuple)
                } else if secondaryAgentTypeIDs.contains(typeID) {
                    secondaryTypes.append(typeTuple)
                } else {
                    otherTypes.append(typeTuple)
                }
            }

            // 按指定顺序排序主要类型
            mainTypes.sort { first, second in
                guard let firstIndex = mainAgentTypeIDs.firstIndex(of: first.0),
                    let secondIndex = mainAgentTypeIDs.firstIndex(of: second.0)
                else {
                    return false
                }
                return firstIndex < secondIndex
            }

            // 按指定顺序排序次要类型
            secondaryTypes.sort { first, second in
                guard let firstIndex = secondaryAgentTypeIDs.firstIndex(of: first.0),
                    let secondIndex = secondaryAgentTypeIDs.firstIndex(of: second.0)
                else {
                    return false
                }
                return firstIndex < secondIndex
            }

            // 按ID排序其他类型
            otherTypes.sort { $0.0 < $1.0 }

            // 合并三组类型
            availableAgentTypes = mainTypes + secondaryTypes + otherTypes
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

// 代理人层级视图
enum AgentListLevel {
    case faction  // 势力层级
    case corporation  // 军团层级
    case division  // 部门层级
    case level  // 等级层级
    case agent  // 代理人层级
}

// 合并后的代理人列表层级视图
struct AgentListHierarchyView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let level: AgentListLevel
    let searchResults: [AgentItem]
    let title: String

    // 各层级所需参数
    var factionID: Int? = nil
    var factionName: String? = nil
    var corporationID: Int? = nil
    var corporationName: String? = nil
    var divisionID: Int? = nil
    var divisionName: String? = nil
    var agentLevel: Int? = nil
    var levelName: String? = nil

    // 缓存数据
    @State private var corporationToFaction: [Int: Int] = [:]
    @State private var factionAgentCounts: [Int: Int] = [:]

    // 各层级数据
    @State private var factions: [(Int, String, String)] = []  // ID, 名称, 图标
    @State private var corporations: [(Int, String, String)] = []  // ID, 名称, 图标
    @State private var divisions: [(Int, String, String)] = []  // ID, 名称, 图标
    @State private var levels: [(Int, String)] = []  // 等级, 名称

    @State private var isLoading = true

    var body: some View {
        ZStack {
            if isLoading {
                VStack {
                    ProgressView()
                    Text(NSLocalizedString("Agent_Loading", comment: "加载中..."))
                        .padding(.top, 16)
                }
            } else if searchResults.isEmpty {
                VStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                        .padding()
                    Text(NSLocalizedString("Agent_Not_Found", comment: "未找到代理人"))
                }
            } else {
                // 根据当前层级和数据项数量决定显示内容
                switch level {
                case .faction:
                    if factions.count == 1 {
                        // 如果只有一个势力，直接显示军团列表
                        let faction = factions[0]
                        AgentListHierarchyView(
                            databaseManager: databaseManager,
                            level: .corporation,
                            searchResults: searchResults.filter { agent in
                                if let corpFactionID = corporationToFaction[agent.corporationID] {
                                    return corpFactionID == faction.0
                                }
                                return false
                            },
                            title: faction.1,
                            factionID: faction.0,
                            factionName: faction.1
                        )
                    } else {
                        // 显示势力列表
                        factionsListView
                    }
                case .corporation:
                    if corporations.count == 1 {
                        // 如果只有一个军团，直接显示部门列表
                        let corporation = corporations[0]
                        AgentListHierarchyView(
                            databaseManager: databaseManager,
                            level: .division,
                            searchResults: searchResults.filter {
                                $0.corporationID == corporation.0
                            },
                            title: corporation.1,
                            corporationID: corporation.0,
                            corporationName: corporation.1
                        )
                    } else {
                        // 显示军团列表
                        corporationsListView
                    }
                case .division:
                    if divisions.count == 1 {
                        // 如果只有一个部门，直接显示等级列表
                        let division = divisions[0]
                        AgentListHierarchyView(
                            databaseManager: databaseManager,
                            level: .level,
                            searchResults: searchResults.filter { $0.divisionID == division.0 },
                            title: division.1,
                            divisionID: division.0,
                            divisionName: division.1
                        )
                    } else {
                        // 显示部门列表
                        divisionsListView
                    }
                case .level:
                    if levels.count == 1 {
                        // 如果只有一个等级，直接显示代理人列表
                        let level = levels[0]
                        AgentListHierarchyView(
                            databaseManager: databaseManager,
                            level: .agent,
                            searchResults: searchResults.filter { $0.level == level.0 },
                            title: level.1,
                            agentLevel: level.0,
                            levelName: level.1
                        )
                    } else {
                        // 显示等级列表
                        levelsListView
                    }
                case .agent:
                    // 显示代理人列表
                    agentsListView
                }
            }
        }
        .navigationTitle(title)
        .onAppear {
            loadData()
        }
    }

    // 加载数据
    private func loadData() {
        isLoading = true

        switch level {
        case .faction:
            loadFactionData()
        case .corporation:
            loadCorporationData()
        case .division:
            loadDivisionData()
        case .level:
            loadLevelData()
        case .agent:
            // 代理人列表不需要额外加载数据
            isLoading = false
        }
    }

    // 势力列表视图
    private var factionsListView: some View {
        List {
            ForEach(factions, id: \.0) { factionID, factionName, iconName in
                NavigationLink(
                    destination: AgentListHierarchyView(
                        databaseManager: databaseManager,
                        level: .corporation,
                        searchResults: searchResults.filter { agent in
                            if let corpFactionID = corporationToFaction[agent.corporationID] {
                                return corpFactionID == factionID
                            }
                            return false
                        },
                        title: factionName,
                        factionID: factionID,
                        factionName: factionName
                    )
                ) {
                    HStack {
                        IconManager.shared.loadImage(for: iconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(factionName)
                            Text(
                                String(
                                    format: NSLocalizedString("Agent_Count", comment: "%d个代理人"),
                                    countAgentsInFaction(factionID)
                                )
                            )
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

    // 军团列表视图
    private var corporationsListView: some View {
        List {
            ForEach(corporations, id: \.0) { corporationID, corporationName, iconName in
                NavigationLink(
                    destination: AgentListHierarchyView(
                        databaseManager: databaseManager,
                        level: .division,
                        searchResults: searchResults.filter { $0.corporationID == corporationID },
                        title: corporationName,
                        corporationID: corporationID,
                        corporationName: corporationName
                    )
                ) {
                    HStack {
                        IconManager.shared.loadImage(for: iconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(corporationName)
                            Text(
                                String(
                                    format: NSLocalizedString("Agent_Count", comment: "%d个代理人"),
                                    searchResults.filter { $0.corporationID == corporationID }.count
                                )
                            )
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

    // 部门列表视图
    private var divisionsListView: some View {
        List {
            ForEach(divisions, id: \.0) { divisionID, divisionName, iconName in
                NavigationLink(
                    destination: AgentListHierarchyView(
                        databaseManager: databaseManager,
                        level: .level,
                        searchResults: searchResults.filter { $0.divisionID == divisionID },
                        title: divisionName,
                        divisionID: divisionID,
                        divisionName: divisionName
                    )
                ) {
                    HStack {
                        Image(iconName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .cornerRadius(4)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(divisionName)
                            Text(
                                String(
                                    format: NSLocalizedString("Agent_Count", comment: "%d个代理人"),
                                    searchResults.filter { $0.divisionID == divisionID }.count
                                )
                            )
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

    // 等级列表视图
    private var levelsListView: some View {
        List {
            ForEach(levels, id: \.0) { level, levelName in
                NavigationLink(
                    destination: AgentListHierarchyView(
                        databaseManager: databaseManager,
                        level: .agent,
                        searchResults: searchResults.filter { $0.level == level },
                        title: levelName,
                        agentLevel: level,
                        levelName: levelName
                    )
                ) {
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
                            Text(
                                String(
                                    format: NSLocalizedString("Agent_Count", comment: "%d个代理人"),
                                    searchResults.filter { $0.level == level }.count
                                )
                            )
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

    // 代理人列表视图
    private var agentsListView: some View {
        List {
            ForEach(searchResults) { agent in
                AgentCellView(agent: agent, databaseManager: databaseManager)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    // 加载势力数据
    private func loadFactionData() {
        // 加载军团-势力映射关系
        loadCorporationFactionMapping()

        // 更新势力列表
        updateFactions()

        isLoading = false
    }

    // 加载军团数据
    private func loadCorporationData() {
        guard let factionID = factionID else {
            isLoading = false
            return
        }

        // 一次性查询指定势力下的所有军团
        let query = """
                SELECT c.corporation_id, c.name, c.icon_id, i.iconFile_new
                FROM npcCorporations c
                LEFT JOIN iconIDs i ON c.icon_id = i.icon_id
                WHERE c.faction_id = ?
                ORDER BY c.name
            """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [factionID]) {
            let allCorporations = rows.compactMap { row -> (Int, String, String)? in
                guard let corporationID = row["corporation_id"] as? Int,
                    let name = row["name"] as? String
                else {
                    return nil
                }

                let iconFile = row["iconFile_new"] as? String ?? "corporation_default"
                return (corporationID, name, iconFile)
            }

            // 过滤出有代理人的军团
            let corporationIDs = Set(searchResults.map { $0.corporationID })
            let filteredCorporations = allCorporations.filter { corporationIDs.contains($0.0) }

            corporations = filteredCorporations
        }

        isLoading = false
    }

    // 加载部门数据
    private func loadDivisionData() {
        guard let corporationID = corporationID else {
            isLoading = false
            return
        }

        var uniqueDivisions = Set<Int>()
        var divisionsList: [(Int, String, String)] = []

        // 查询部门名称
        let query = """
                SELECT division_id, name
                FROM divisions
                WHERE division_id IN (
                    SELECT DISTINCT divisionID FROM agents WHERE agent_id IN (
                        SELECT agent_id FROM agents WHERE corporationID = ?
                    )
                )
            """

        if case let .success(rows) = databaseManager.executeQuery(
            query, parameters: [corporationID]
        ) {
            var divisionNames: [Int: String] = [:]

            for row in rows {
                if let divisionID = row["division_id"] as? Int,
                    let name = row["name"] as? String
                {
                    divisionNames[divisionID] = name
                }
            }

            // 收集搜索结果中的所有部门
            for agent in searchResults {
                if !uniqueDivisions.contains(agent.divisionID) {
                    uniqueDivisions.insert(agent.divisionID)
                    let divisionName = divisionNames[agent.divisionID] ?? "unknown"
                    let iconName = divisionIcons[agent.divisionID] ?? "not_found"
                    divisionsList.append((agent.divisionID, divisionName, iconName))
                }
            }
        }

        divisions = divisionsList.sorted(by: { $0.0 > $1.0 })
        isLoading = false
    }

    // 加载等级数据
    private func loadLevelData() {
        var uniqueLevels = Set<Int>()
        var levelsList: [(Int, String)] = []

        for agent in searchResults {
            if !uniqueLevels.contains(agent.level) {
                uniqueLevels.insert(agent.level)
                levelsList.append((agent.level, "Level \(agent.level)"))
            }
        }

        levels = levelsList.sorted(by: { $0.0 > $1.0 })  // 等级从高到低排序
        isLoading = false
    }

    // 加载军团-势力映射关系
    private func loadCorporationFactionMapping() {
        // 一次性查询所有军团和势力的映射关系
        let query = """
                SELECT c.corporation_id, c.faction_id
                FROM npcCorporations c
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            var corpToFaction: [Int: Int] = [:]

            for row in rows {
                if let corporationID = row["corporation_id"] as? Int,
                    let factionID = row["faction_id"] as? Int
                {
                    corpToFaction[corporationID] = factionID
                }
            }

            corporationToFaction = corpToFaction

            // 预计算每个势力的代理人数量
            var counts: [Int: Int] = [:]
            for agent in searchResults {
                if let factionID = corpToFaction[agent.corporationID] {
                    counts[factionID, default: 0] += 1
                }
            }
            factionAgentCounts = counts
        }
    }

    // 更新势力列表
    private func updateFactions() {
        // 1. 首先获取所有代理人的军团ID
        let corporationIDs = Set(searchResults.map { $0.corporationID })

        if corporationIDs.isEmpty {
            factions = []
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

        if case let .success(rows) = databaseManager.executeQuery(
            query, parameters: Array(corporationIDs)
        ) {
            // 3. 创建军团ID到势力ID的映射
            var corporationToFaction: [Int: (Int, String, String)] = [:]
            for row in rows {
                if let corporationID = row["corporation_id"] as? Int,
                    let factionID = row["faction_id"] as? Int,
                    let factionName = row["faction_name"] as? String
                {
                    let iconName = row["faction_icon"] as? String ?? "faction_default"
                    corporationToFaction[corporationID] = (factionID, factionName, iconName)
                }
            }

            // 4. 统计每个势力下的代理人数量
            var factionData: [Int: (String, String, Int)] = [:]

            for agent in searchResults {
                if let (factionID, factionName, iconName) = corporationToFaction[
                    agent.corporationID
                ] {
                    if let (name, icon, count) = factionData[factionID] {
                        factionData[factionID] = (name, icon, count + 1)
                    } else {
                        factionData[factionID] = (factionName, iconName, 1)
                    }
                }
            }

            // 5. 创建最终的势力列表
            let factionsList = factionData.map { factionID, data in
                (factionID, data.0, data.1)
            }.sorted { $0.1 < $1.1 }

            factions = factionsList
        } else {
            factions = []
        }
    }

    // 计算势力中的代理人数量
    private func countAgentsInFaction(_ factionID: Int) -> Int {
        // 使用预先计算的缓存数据
        return factionAgentCounts[factionID] ?? 0
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
    @State private var locationInfo: (name: String, security: Double?) = ("Loading...", nil)
    @State private var affiliationInfo:
        (factionName: String, corporationName: String, factionIcon: String, corporationIcon: String) =
            ("", "", "", "")
    @State private var divisionName: String = ""

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
                    .textSelection(.enabled)

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
                if !affiliationInfo.factionName.isEmpty && !affiliationInfo.corporationName.isEmpty
                {
                    HStack(spacing: 8) {
                        // 势力图标
                        IconManager.shared.loadImage(for: affiliationInfo.factionIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .cornerRadius(2)

                        Text(affiliationInfo.factionName)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("-")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // 军团图标
                        IconManager.shared.loadImage(for: affiliationInfo.corporationIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .cornerRadius(2)

                        Text(affiliationInfo.corporationName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 标签行
                HStack(spacing: 8) {
                    // 等级标签
                    Text(
                        String(
                            format: NSLocalizedString("Agent_Level", comment: "L%d"), agent.level
                        )
                    )
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(getLevelColor(agent.level))
                    .foregroundColor(.white)
                    .cornerRadius(4)

                    // 部门标签
                    if !divisionName.isEmpty {
                        Text(divisionName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(getDivisionColor(agent.divisionID))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }

                    // 代理人类型标签 - 不显示BasicAgent类型
                    if agent.agentType != 2 {
                        Text(getAgentTypeShortName(agent.agentType))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(getAgentTypeColor(agent.agentType))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }

                    // 定位代理人标签
                    if agent.isLocator {
                        Text(NSLocalizedString("Agent_Locator", comment: "定位代理人"))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }

                    // 空间代理人标签
                    if agent.solarSystemID != nil {
                        Text(NSLocalizedString("Agent_Space", comment: "空间代理人"))
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
            loadDivisionName()
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
            if case let .success(rows) = databaseManager.executeQuery(query, parameters: [systemID])
            {
                if let row = rows.first,
                    let name = row["solarSystemName"] as? String
                {
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
            if case let .success(rows) = databaseManager.executeQuery(
                query, parameters: [agent.locationID]
            ) {
                if let row = rows.first,
                    let name = row["stationName"] as? String
                {
                    let security = row["security"] as? Double
                    locationInfo = (name, security)
                }
            }
        }

        // 查询势力和军团信息
        let affiliationQuery = """
                SELECT c.name as corporationName, f.name as factionName, 
                       f.iconName as factionIcon, c.icon_id as corporationIconID,
                       i.iconFile_new as corporationIcon
                FROM npcCorporations c
                JOIN factions f ON c.faction_id = f.id
                LEFT JOIN iconIDs i ON c.icon_id = i.icon_id
                WHERE c.corporation_id = ?
            """

        if case let .success(rows) = databaseManager.executeQuery(
            affiliationQuery, parameters: [agent.corporationID]
        ) {
            if let row = rows.first,
                let corporationName = row["corporationName"] as? String,
                let factionName = row["factionName"] as? String
            {
                let factionIcon = row["factionIcon"] as? String ?? "faction_default"
                let corporationIcon = row["corporationIcon"] as? String ?? "corporation_default"
                affiliationInfo = (factionName, corporationName, factionIcon, corporationIcon)
            }
        }
    }

    // 加载部门名称
    private func loadDivisionName() {
        let query = """
                SELECT name
                FROM divisions
                WHERE division_id = ?
            """

        if case let .success(rows) = databaseManager.executeQuery(
            query, parameters: [agent.divisionID]
        ) {
            if let row = rows.first,
                let name = row["name"] as? String
            {
                divisionName = name
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

    // 根据部门ID获取颜色
    private func getDivisionColor(_ divisionID: Int) -> Color {
        switch divisionID {
        case 18: return Color.blue.opacity(0.8)  // 研发 - 深蓝色
        case 22: return Color.purple.opacity(0.8)  // 物流 - 紫色
        case 23: return Color(red: 0.8, green: 0.6, blue: 0.0)  // 采矿 - 深黄色
        case 24: return Color.red.opacity(0.8)  // 安全 - 深红色
        default: return Color.gray.opacity(0.8)  // 其他 - 灰色
        }
    }

    // 根据代理人类型获取颜色
    private func getAgentTypeColor(_ agentType: Int) -> Color {
        switch agentType {
        case 1: return Color.gray.opacity(0.8)
        case 2: return Color.green.opacity(0.8)
        case 3: return Color.blue.opacity(0.8)
        case 4: return Color.blue.opacity(0.8)
        case 5: return Color.brown.opacity(0.8)
        case 6: return Color.green.opacity(0.8)
        case 7: return Color.green.opacity(0.8)
        case 8: return Color.yellow.opacity(0.8)
        case 9: return Color.cyan.opacity(0.8)
        case 10: return Color.mint.opacity(0.8)
        case 11: return Color.indigo.opacity(0.8)
        case 12: return Color.teal.opacity(0.8)
        case 13: return Color.brown.opacity(0.8)
        default: return Color.gray.opacity(0.8)
        }
    }
}
