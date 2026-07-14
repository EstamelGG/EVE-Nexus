import Foundation
import SwiftUI

struct AgentSearchView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var isNavigatingToResults = false
    @State private var searchResultsDestination: String? = nil
    @State private var searchResults: [AgentItem] = [] // 添加存储搜索结果的状态变量

    // 过滤条件
    @State private var selectedDivisionID: Int?
    @State private var selectedLevel: Int?
    @State private var selectedSecurityLevel: String?
    @State private var selectedFactionID: Int?
    @State private var selectedCorporationID: Int?
    @State private var isLocatorOnly = false
    @State private var isSpaceAgentOnly = false // 添加空间代理人筛选条件
    @State private var selectedAgentType: Int? = nil // 不默认选择任何代理人类型
    @State private var selectedRegionID: Int? = nil // 添加选中的星域ID
    @State private var selectedRegionName: String? = nil // 添加选中的星域名称
    @State private var selectedSolarSystemID: Int? = nil // 添加选中的星系ID
    @State private var selectedSolarSystemName: String? = nil // 添加选中的星系名称

    // 可用的选项数据
    @State private var availableFactions: [(Int, String, String)] = []
    @State private var availableCorporations: [(Int, String, String)] = []
    @State private var availableDivisions: [(Int, String, String)] = []
    @State private var availableAgentTypes: [(Int, String)] = []

    /// 等级数据
    let levels = [
        (1, String.localizedStringWithFormat(NSLocalizedString("Misc_Level", comment: "lv1"), 1)),
        (2, String.localizedStringWithFormat(NSLocalizedString("Misc_Level", comment: "lv2"), 2)),
        (3, String.localizedStringWithFormat(NSLocalizedString("Misc_Level", comment: "lv3"), 3)),
        (4, String.localizedStringWithFormat(NSLocalizedString("Misc_Level", comment: "lv4"), 4)),
        (5, String.localizedStringWithFormat(NSLocalizedString("Misc_Level", comment: "lv5"), 5)),
    ]

    /// 安全等级选项
    let securityLevels = [
        ("highsec", NSLocalizedString("Security_HighSec", comment: "高安")),
        ("lowsec", NSLocalizedString("Security_LowSec", comment: "低安")),
        ("nullsec", NSLocalizedString("Security_NullSec", comment: "零安")),
    ]

    var body: some View {
        VStack {
            List {
                // 所有其他过滤条件放在一个Section中
                Section(header: Text(NSLocalizedString("Agent_Search_Filter", comment: "过滤条件"))) {
                    // 1. 等级过滤
                    Picker(
                        NSLocalizedString("Agent_Search_Level", comment: "等级"),
                        selection: $selectedLevel
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Levels", comment: "所有等级")).tag(
                            nil as Int?
                        )
                        ForEach(levels, id: \.0) { level in
                            Text(level.1).tag(level.0 as Int?)
                        }
                    }

                    // 2. 安全等级过滤
                    Picker(
                        NSLocalizedString("Agent_Search_Security", comment: "安全等级"),
                        selection: $selectedSecurityLevel
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Security", comment: "所有安全等级")).tag(
                            nil as String?
                        )
                        ForEach(securityLevels, id: \.0) { security in
                            Text(security.1).tag(security.0 as String?)
                        }
                    }

                    // 3. 势力过滤
                    Picker(
                        selection: $selectedFactionID,
                        label: Text(NSLocalizedString("Agent_Search_Faction", comment: "势力"))
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Factions", comment: "所有势力")).tag(
                            nil as Int?
                        )
                        ForEach(availableFactions, id: \.0) { faction in
                            Text(faction.1).tag(faction.0 as Int?)
                        }
                    }
                    .onChange(of: selectedFactionID) { _, newValue in
                        selectedCorporationID = nil
                        if let factionID = newValue {
                            availableCorporations = AgentDataStore.shared.corporations(
                                forFaction: factionID
                            )
                        } else {
                            availableCorporations = []
                        }
                    }

                    // 4. 军团过滤 (仅当选择了势力时显示)
                    if selectedFactionID != nil {
                        Picker(
                            selection: $selectedCorporationID,
                            label: Text(
                                NSLocalizedString("Agent_Search_Corporation", comment: "军团")
                            )
                        ) {
                            Text(
                                NSLocalizedString("Agent_Search_All_Corporations", comment: "所有军团")
                            ).tag(nil as Int?)
                            ForEach(availableCorporations, id: \.0) { corp in
                                Text(corp.1).tag(corp.0 as Int?)
                            }
                        }
                    }

                    // 5. 部门过滤
                    Picker(
                        selection: $selectedDivisionID,
                        label: Text(NSLocalizedString("Agent_Search_Division", comment: "部门"))
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Divisions", comment: "所有部门")).tag(
                            nil as Int?
                        )

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

                    // 6. 代理人类型过滤
                    Picker(
                        NSLocalizedString("Agent_Search_Type", comment: "代理人类型"),
                        selection: $selectedAgentType
                    ) {
                        Text(NSLocalizedString("Agent_Search_All_Types", comment: "所有代理人类型")).tag(
                            nil as Int?
                        )

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
                Section {
                    // 定位代理人开关
                    HStack {
                        Toggle(isOn: $isLocatorOnly) {
                            VStack(alignment: .leading) {
                                Text(
                                    NSLocalizedString(
                                        "Agent_Search_Locator_Only", comment: "仅显示寻人代理人"
                                    )
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
                            VStack(alignment: .leading) {
                                Text(
                                    NSLocalizedString(
                                        "Agent_Search_Space_Only", comment: "仅显示空间代理人"
                                    )
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

                // 位置过滤条件放在最后一个Section中
                Section(header: Text(NSLocalizedString("Location_Filter", comment: "位置过滤"))) {
                    // 星域过滤
                    NavigationLink(
                        destination: RegionSearchView(
                            databaseManager: databaseManager,
                            selectedRegionID: $selectedRegionID,
                            selectedRegionName: $selectedRegionName
                        )
                    ) {
                        HStack {
                            Text(NSLocalizedString("Region_Filter", comment: "过滤星域"))
                            Spacer()
                            Text(
                                selectedRegionName
                                    ?? NSLocalizedString("Region_All", comment: "所有星域")
                            )
                            .foregroundColor(.gray)
                        }
                    }

                    // 星系过滤
                    NavigationLink(
                        destination: SolarSystemSearchView(
                            databaseManager: databaseManager,
                            selectedSolarSystemID: $selectedSolarSystemID,
                            selectedSolarSystemName: $selectedSolarSystemName,
                            regionID: selectedRegionID
                        )
                    ) {
                        HStack {
                            Text(NSLocalizedString("System_Filter", comment: "过滤星系"))
                            Spacer()
                            Text(
                                selectedSolarSystemName
                                    ?? (selectedRegionID == nil
                                        ? NSLocalizedString("System_All", comment: "所有星系")
                                        : NSLocalizedString(
                                            "System_All_In_Region", comment: "该星域内所有星系"
                                        ))
                            )
                            .foregroundColor(.gray)
                        }
                    }
                }
            }

            Button(action: {
                // 在点击按钮时执行搜索
                searchResults = searchAgents()
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
                searchResults: searchResults, // 使用存储的搜索结果
                title: NSLocalizedString("Agent_Search_Results", comment: "搜索结果")
            )
        }
        .onAppear {
            AgentDataStore.shared.ensureLoaded(databaseManager: databaseManager)
            availableFactions = AgentDataStore.shared.factions
            availableDivisions = AgentDataStore.shared.divisions
            availableAgentTypes = AgentDataStore.shared.agentTypes
            if let factionID = selectedFactionID {
                availableCorporations = AgentDataStore.shared.corporations(forFaction: factionID)
            }
        }
    }

    private func resetFilters() {
        selectedDivisionID = nil
        selectedLevel = nil
        selectedSecurityLevel = nil
        selectedFactionID = nil
        selectedCorporationID = nil
        isLocatorOnly = false
        isSpaceAgentOnly = false
        selectedAgentType = nil
        selectedRegionID = nil
        selectedRegionName = nil
        selectedSolarSystemID = nil
        selectedSolarSystemName = nil
        availableCorporations = []
    }

    private func searchAgents() -> [AgentItem] {
        AgentDataStore.shared.ensureLoaded(databaseManager: databaseManager)
        return AgentDataStore.shared.search(
            .init(
                divisionID: selectedDivisionID,
                level: selectedLevel,
                securityLevel: selectedSecurityLevel,
                factionID: selectedFactionID,
                corporationID: selectedCorporationID,
                isLocatorOnly: isLocatorOnly,
                isSpaceAgentOnly: isSpaceAgentOnly,
                agentType: selectedAgentType,
                regionID: selectedRegionID,
                solarSystemID: selectedSolarSystemID
            )
        )
    }
}
