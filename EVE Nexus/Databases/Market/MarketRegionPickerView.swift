import SwiftUI

/// 星域数据模型
struct Region: Identifiable {
    let id: Int

    var name: String {
        SDEMemoryStore.regionName(for: id) ?? "Region \(id)"
    }
}

/// 星域选择器视图
struct MarketRegionPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedRegionID: Int
    @Binding var selectedRegionName: String
    @Binding var saveSelection: Bool
    let databaseManager: DatabaseManager

    @State private var isEditMode = false
    @State private var allRegions: [Region] = []
    @State private var pinnedRegions: [Region] = []
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var sectionedRegions: [String: [Region]] = [:]
    @State private var sectionTitles: [String] = []
    @State private var commonSystems: [CommonSystem] = []
    @StateObject private var structureManager = MarketStructureManager.shared

    /// 常见星系映射表
    private let commonSystemMap: [String: String] = [
        "Jita": "30000142",
        "Amarr": "30002187",
        "Rens": "30002510",
        "Hek": "30002053",
        "Zarzakh": "30100000",
    ]

    /// 常见星系数据模型
    struct CommonSystem: Identifiable {
        let id: String
        var regionID: Int?

        var systemName: String? {
            guard let systemId = Int(id) else { return nil }
            return SDEMemoryStore.solarSystemName(for: systemId)
        }
    }

    private var unpinnedRegions: [Region] {
        allRegions.filter { region in
            !pinnedRegions.contains { $0.id == region.id }
        }
    }

    /// 加载星域数据
    private func loadRegions() {
        allRegions = SDEMemoryStore.regionNames.compactMap { id, text in
            guard id < 11_000_000 else { return nil }
            let name = text.resolved()
            guard !name.isEmpty else { return nil }
            return Region(id: id)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // 从 UserDefaults 加载置顶的星域，保持用户设置的顺序
        let pinnedRegionIDs = UserDefaultsManager.shared.pinnedRegionIDs
        // 按照 pinnedRegionIDs 的顺序加载星域
        pinnedRegions = pinnedRegionIDs.compactMap { id in
            allRegions.first { $0.id == id }
        }

        // 如果当前选中的星域存在，确保它显示在正确的位置
        if let currentRegion = allRegions.first(where: { $0.id == selectedRegionID }) {
            if pinnedRegionIDs.contains(currentRegion.id) {
                // 如果是置顶星域，确保它在置顶列表中
                if !pinnedRegions.contains(where: { $0.id == currentRegion.id }) {
                    pinnedRegions.append(currentRegion)
                }
            }
        }

        // 加载常见星系数据
        loadCommonSystems()

        // 更新分组数据
        updateSections()
    }

    /// 加载常见星系数据
    private func loadCommonSystems() {
        var systems: [CommonSystem] = []

        // 从映射表创建常见星系对象
        for (_, id) in commonSystemMap {
            systems.append(CommonSystem(id: id))
        }

        // 获取所有星系ID
        let systemIDs = systems.compactMap { Int($0.id) }
        guard !systemIDs.isEmpty else {
            commonSystems = systems
            return
        }

        let query = """
            SELECT solarsystem_id, region_id
            FROM universe
            WHERE solarsystem_id IN (\(systemIDs.map { String($0) }.joined(separator: ",")))
        """

        var regionBySystem: [Int: Int] = [:]
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let systemID = row["solarsystem_id"] as? Int,
                   let regionID = row["region_id"] as? Int
                {
                    regionBySystem[systemID] = regionID
                }
            }
        }

        for i in 0 ..< systems.count {
            guard let systemID = Int(systems[i].id),
                  let regionID = regionBySystem[systemID]
            else { continue }
            systems[i].regionID = regionID
        }

        commonSystems = systems
    }

    /// 更新分组数据
    private func updateSections() {
        var filteredData = unpinnedRegions

        // 如果有搜索文本，过滤数据
        if !searchText.isEmpty {
            filteredData = unpinnedRegions.filter { region in
                if SDEMemoryStore.regionNames[region.id]?.matchesSearch(searchText) == true {
                    return true
                }
                return commonSystems.contains { system in
                    system.regionID == region.id
                        && Int(system.id).map {
                            SDEMemoryStore.solarSystemNames[$0]?.matchesSearch(searchText) == true
                        } == true
                }
            }
        }

        // 按首字母分组
        let grouped = Dictionary(grouping: filteredData) { region -> String in
            // 获取首字母（包括处理中文拼音）
            let name = region.name
            if let firstChar = name.first {
                return getFirstLetter(of: String(firstChar))
            }
            return "#"
        }

        sectionedRegions = grouped
        sectionTitles = grouped.keys.sorted()

        // 对每个组内的数据进行排序
        for (key, _) in sectionedRegions {
            sectionedRegions[key]?.sort {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    /// 获取字符的首字母（包括中文拼音）
    private func getFirstLetter(of char: String) -> String {
        // 转换为大写
        let uppercaseChar = char.uppercased()

        // 判断是否为英文字母
        if uppercaseChar >= "A" && uppercaseChar <= "Z" {
            return uppercaseChar
        }

        // 中文字符转拼音
        let pinyin = NSMutableString(string: char) as CFMutableString
        CFStringTransform(pinyin, nil, kCFStringTransformToLatin, false)
        CFStringTransform(pinyin, nil, kCFStringTransformStripDiacritics, false)

        if let firstPinyinChar = String(pinyin as String).first {
            let letter = String(firstPinyinChar).uppercased()
            if letter >= "A" && letter <= "Z" {
                return letter
            }
        }

        // 其他字符
        return "#"
    }

    private func savePinnedRegions() {
        let pinnedIDs = pinnedRegions.map { $0.id }
        UserDefaultsManager.shared.pinnedRegionIDs = pinnedIDs
    }

    /// The Forge (Jita) 不允许移除置顶，其他星域返回取消置顶操作
    private func unpinAction(for region: Region) -> (() -> Void)? {
        guard region.id != MarketManager.theForgeRegionID else { return nil }
        return {
            withAnimation {
                pinnedRegions.removeAll { $0.id == region.id }
                savePinnedRegions()
                updateSections()
            }
        }
    }

    /// 获取星域对应的常见星系名称
    private func getCommonSystemName(for regionID: Int) -> String? {
        return commonSystems.first { $0.regionID == regionID }?.systemName
    }

    /// 置顶星域行
    private func pinnedRegionRow(_ region: Region) -> some View {
        RegionRow(
            region: region,
            isSelected: region.id == selectedRegionID,
            isEditMode: isEditMode,
            onSelect: {
                selectedRegionID = region.id
                selectedRegionName = region.name
                if saveSelection {
                    let defaults = UserDefaultsManager.shared
                    defaults.selectedRegionID = region.id
                }
                if !isEditMode {
                    dismiss()
                }
            },
            onUnpin: unpinAction(for: region),
            commonSystemName: getCommonSystemName(for: region.id)
        )
    }

    /// 市场建筑行
    private func marketStructureRow(_ structure: MarketStructure) -> some View {
        let virtualID = MarketLocation.structure(Int64(structure.structureId)).virtualRegionID
        return MarketStructureRow(
            structure: structure,
            isSelected: selectedRegionID == virtualID,
            onSelect: {
                // 选择建筑：编码为虚拟 regionID（负数）
                selectedRegionID = virtualID
                selectedRegionName = structure.structureName
                if saveSelection {
                    let defaults = UserDefaultsManager.shared
                    defaults.selectedRegionID = selectedRegionID
                }
                if !isEditMode {
                    dismiss()
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                // 置顶星域 Section
                Section(header: Text(NSLocalizedString("Main_Market_Pinned_Regions", comment: ""))) {
                    if !pinnedRegions.isEmpty {
                        ForEach(pinnedRegions) { region in
                            pinnedRegionRow(region)
                        }
                        .onMove { from, to in
                            pinnedRegions.move(fromOffsets: from, toOffset: to)
                            savePinnedRegions()
                        }
                    }

                    if !isEditMode {
                        Button(action: {
                            withAnimation {
                                isEditMode = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                Text(NSLocalizedString("Main_Market_Add_Region", comment: ""))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // 市场建筑 Section（编辑模式时隐藏）
                if !isEditMode {
                    Section(
                        header: Text(
                            NSLocalizedString("Main_Setting_Market_Structure_Select", comment: "")
                        )
                    ) {
                        if !structureManager.structures.isEmpty {
                            ForEach(structureManager.structures) { structure in
                                marketStructureRow(structure)
                            }
                        } else {
                            // 没有建筑时显示设置按钮
                            NavigationLink(destination: MarketStructureSettingsView()) {
                                HStack {
                                    Image(systemName: "gear")
                                        .foregroundColor(.blue)
                                        .font(.title2)

                                    Text(
                                        NSLocalizedString(
                                            "Main_Market_Setup_Structure", comment: "设置建筑市场"
                                        )
                                    )
                                    .foregroundColor(.primary)

                                    Spacer()
                                }
                            }
                        }
                    }
                }

                // 按首字母分组显示星域列表
                ForEach(sectionTitles, id: \.self) { sectionTitle in
                    if let regionsInSection = sectionedRegions[sectionTitle],
                       !regionsInSection.isEmpty
                    {
                        Section(header: Text(sectionTitle)) {
                            ForEach(regionsInSection) { region in
                                RegionRow(
                                    region: region,
                                    isSelected: region.id == selectedRegionID,
                                    isEditMode: isEditMode,
                                    onSelect: {
                                        selectedRegionID = region.id
                                        selectedRegionName = region.name
                                        if saveSelection {
                                            let defaults = UserDefaultsManager.shared
                                            defaults.selectedRegionID = region.id
                                        }
                                        if !isEditMode {
                                            dismiss()
                                        }
                                    },
                                    onPin: isEditMode
                                        ? {
                                            withAnimation {
                                                pinnedRegions.append(region)
                                                savePinnedRegions()
                                                updateSections()
                                            }
                                        } : nil,
                                    commonSystemName: getCommonSystemName(for: region.id)
                                )
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $searchText,
                isPresented: $isSearchActive,
                // placement: .navigationBarDrawer(displayMode: .always),
                prompt: NSLocalizedString("Region_Search_Placeholder", comment: "搜索星域...")
            )
            .onChange(of: searchText) { _, _ in
                updateSections()
            }
            .onChange(of: isSearchActive) { _, _ in
                // 当搜索状态改变时，也需要更新分组
                updateSections()
            }
            .navigationTitle(NSLocalizedString("Main_Market_Select_Region", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditMode {
                        Button(NSLocalizedString("Main_Market_Done", comment: "")) {
                            withAnimation {
                                isEditMode = false
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
        }
        .onAppear {
            loadRegions()
            structureManager.loadStructures()
        }
    }
}

/// 星域行视图
struct RegionRow: View {
    let region: Region
    let isSelected: Bool
    let isEditMode: Bool
    let onSelect: () -> Void
    var onPin: (() -> Void)?
    var onUnpin: (() -> Void)?
    var commonSystemName: String?

    var body: some View {
        HStack {
            HStack {
                Text(region.name)
                    .foregroundColor(isSelected ? .blue : .primary)
                if let systemName = commonSystemName {
                    Text("(\(systemName))")
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isEditMode {
                if onUnpin != nil {
                    Button(role: .destructive, action: { onUnpin?() }) {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                } else if onPin != nil {
                    Button(action: { onPin?() }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditMode {
                onSelect()
            }
        }
    }
}
