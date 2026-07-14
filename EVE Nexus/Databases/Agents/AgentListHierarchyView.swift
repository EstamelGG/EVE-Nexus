import Foundation
import SwiftUI

enum AgentListLevel {
    case faction // 势力层级
    case corporation // 军团层级
    case division // 部门层级
    case level // 等级层级
    case agent // 代理人层级
}

/// 合并后的代理人列表层级视图
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

    /// 缓存数据
    @State private var factionAgentCounts: [Int: Int] = [:]

    // 各层级数据
    @State private var factions: [(Int, String, String)] = [] // ID, 名称, 图标
    @State private var corporations: [(Int, String, String)] = [] // ID, 名称, 图标
    @State private var divisions: [(Int, String, String)] = [] // ID, 名称, 图标
    @State private var levels: [(Int, String)] = [] // 等级, 名称

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
                            searchResults: searchResults.filter { $0.factionID == faction.0 },
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

    /// 加载数据
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

    /// 势力列表视图
    private var factionsListView: some View {
        List {
            ForEach(factions, id: \.0) { factionID, factionName, iconName in
                NavigationLink(
                    destination: AgentListHierarchyView(
                        databaseManager: databaseManager,
                        level: .corporation,
                        searchResults: searchResults.filter { $0.factionID == factionID },
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

    /// 军团列表视图
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

    /// 部门列表视图
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

    /// 等级列表视图
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
                                .font(.system(size: 18, weight: .semibold))
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

    /// 代理人列表视图
    private var agentsListView: some View {
        List {
            ForEach(searchResults) { agent in
                AgentCellView(agent: agent, databaseManager: databaseManager)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    /// 加载势力数据
    private func loadFactionData() {
        AgentDataStore.shared.ensureLoaded(databaseManager: databaseManager)
        factions = AgentDataStore.shared.factions(in: searchResults)
        factionAgentCounts = AgentDataStore.shared.factionAgentCounts(in: searchResults)
        isLoading = false
    }

    /// 加载军团数据
    private func loadCorporationData() {
        guard let factionID = factionID else {
            isLoading = false
            return
        }
        AgentDataStore.shared.ensureLoaded(databaseManager: databaseManager)
        corporations = AgentDataStore.shared.corporations(in: searchResults, factionID: factionID)
        isLoading = false
    }

    /// 加载部门数据
    private func loadDivisionData() {
        guard let corporationID = corporationID else {
            isLoading = false
            return
        }
        divisions = AgentDataStore.shared.divisions(in: searchResults, corporationID: corporationID)
        isLoading = false
    }

    /// 加载等级数据
    private func loadLevelData() {
        var uniqueLevels = Set<Int>()
        var levelsList: [(Int, String)] = []
        for agent in searchResults {
            if uniqueLevels.insert(agent.level).inserted {
                levelsList.append((
                    agent.level,
                    String(format: NSLocalizedString("Misc_Level", comment: "lv%d"), agent.level)
                ))
            }
        }
        levels = levelsList.sorted(by: { $0.0 > $1.0 })
        isLoading = false
    }

    /// 计算势力中的代理人数量
    private func countAgentsInFaction(_ factionID: Int) -> Int {
        factionAgentCounts[factionID] ?? 0
    }

    /// 根据等级获取颜色
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
