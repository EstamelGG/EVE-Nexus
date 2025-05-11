import SwiftUI

// 星系选择器Sheet
struct PISolarSystemSelectorSheet: View {
    let title: String
    let onSelect: (Int, String) -> Void  // 接收星系ID和名称
    let onCancel: () -> Void
    let currentSelection: Int?

    @State private var searchText: String = ""
    @State private var systems:
        [(
            id: Int, name: String, name_en: String, name_zh: String, security: Double,
            region: String
        )] = []
    @State private var selectedSystemId: Int?
    @State private var isLoading = true

    private let databaseManager = DatabaseManager.shared

    init(
        title: String, currentSelection: Int? = nil, onSelect: @escaping (Int, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.currentSelection = currentSelection
        _selectedSystemId = State(initialValue: currentSelection)
    }

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text(NSLocalizedString("PI_Output_Loading_Systems", comment: ""))
                        .foregroundColor(.gray)
                } else {
                    List {
                        ForEach(filteredSystems, id: \.id) { system in
                            Button(action: {
                                selectedSystemId = system.id
                                onSelect(system.id, system.name)
                            }) {
                                HStack {
                                    // 添加安全等级显示
                                    Text(formatSystemSecurity(system.security))
                                        .foregroundColor(getSecurityColor(system.security))
                                        .font(.system(.body, design: .monospaced))
                                        .padding(.trailing, 4)

                                    Text("\(system.name) / ")
                                        .foregroundColor(.primary)
                                        + Text(system.region)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    // 选中状态
                                    if selectedSystemId == system.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: NSLocalizedString("PI_Output_Search_Solar_System", comment: "")
                    )
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(
                        NSLocalizedString("Common_Cancel", comment: ""),
                        action: {
                            onCancel()
                        })
                }
            }
            .onAppear {
                loadSystems()
            }
        }
    }

    // 过滤后的星系列表
    private var filteredSystems:
        [(
            id: Int, name: String, name_en: String, name_zh: String, security: Double,
            region: String
        )]
    {
        if searchText.isEmpty {
            return systems
        } else {
            return systems.filter { system in
                system.name.localizedCaseInsensitiveContains(searchText)
                    || system.name_en.localizedCaseInsensitiveContains(searchText)
                    || system.name_zh.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.name < $1.name }
        }
    }

    // 加载星系数据
    private func loadSystems() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            var loadedSystems:
                [(
                    id: Int, name: String, name_en: String, name_zh: String, security: Double,
                    region: String
                )] = []

            // 查询所有星系，包含中英文名称
            let query = """
                    SELECT s.solarSystemID, s.solarSystemName, 
                           s.solarSystemName_en, s.solarSystemName_zh, 
                           u.system_security, r.regionName 
                    FROM solarsystems s
                    JOIN universe u ON s.solarSystemID = u.solarsystem_id
                    JOIN regions r ON r.regionID = u.region_id
                    ORDER BY s.solarSystemName
                """

            if case let .success(rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    if let solarSystemID = row["solarSystemID"] as? Int,
                        let solarSystemName = row["solarSystemName"] as? String,
                        let security = row["system_security"] as? Double,
                        let regionName = row["regionName"] as? String
                    {
                        // 获取中英文名称，如果不存在则使用默认名称
                        let solarSystemName_en =
                            row["solarSystemName_en"] as? String ?? solarSystemName
                        let solarSystemName_zh =
                            row["solarSystemName_zh"] as? String ?? solarSystemName

                        loadedSystems.append(
                            (
                                id: solarSystemID,
                                name: solarSystemName,
                                name_en: solarSystemName_en,
                                name_zh: solarSystemName_zh,
                                security: security,
                                region: regionName
                            ))
                    }
                }
            }

            // 在主线程更新UI
            DispatchQueue.main.async {
                systems = loadedSystems
                isLoading = false
            }
        }
    }
}
