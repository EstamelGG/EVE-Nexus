import Charts
import SwiftUI

// 星域数据模型
struct Region: Identifiable {
    let id: Int
    let name: String
    let nameEn: String
    let nameZh: String
}

struct MarketItemBasicInfoView: View {
    let itemDetails: ItemDetails
    let marketPath: [String]

    var body: some View {
        HStack {
            IconManager.shared.loadImage(for: itemDetails.iconFileName)
                .resizable()
                .frame(width: 60, height: 60)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(itemDetails.name)
                    .font(.title)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = itemDetails.name
                        } label: {
                            Label(NSLocalizedString("Misc_Copy_Name", comment: ""), systemImage: "doc.on.doc")
                        }
                    }
                Text(
                    "\(itemDetails.categoryName) / \(itemDetails.groupName) / ID:\(itemDetails.typeId)"
                )
                .font(.subheadline)
                .foregroundColor(.gray)
            }
        }
    }
}

// 星域选择器视图
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

    // 常见星系映射表
    private let commonSystemMap: [String: String] = [
        "Jita": "30000142",
        "Amarr": "30002187",
        "Rens": "30002510",
        "Hek": "30002053",
    ]

    // 常见星系数据模型
    struct CommonSystem: Identifiable {
        let id: String
        let name: String
        var regionID: Int?
        var regionName: String?
        var systemName: String?  // 添加星系名称字段
        var systemNameEn: String?  // 添加英文星系名称
        var systemNameZh: String?  // 添加中文星系名称
    }

    private var unpinnedRegions: [Region] {
        allRegions.filter { region in
            !pinnedRegions.contains { $0.id == region.id }
        }
    }

    // 加载星域数据
    private func loadRegions() {
        let query = """
                SELECT r.regionID, r.regionName, r.regionName_en, r.regionName_zh
                FROM regions r
                WHERE r.regionID < 11000000
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            allRegions = rows.compactMap { row in
                guard let id = row["regionID"] as? Int,
                    let nameLocal = row["regionName"] as? String,
                    let nameEn = row["regionName_en"] as? String,
                    let nameZh = row["regionName_zh"] as? String
                else {
                    return nil
                }
                let name = nameLocal
                return Region(id: id, name: name, nameEn: nameEn, nameZh: nameZh)
            }

            // 对星域名称进行排序
            allRegions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

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
    }

    // 加载常见星系数据
    private func loadCommonSystems() {
        var systems: [CommonSystem] = []

        // 从映射表创建常见星系对象
        for (name, id) in commonSystemMap {
            systems.append(CommonSystem(id: id, name: name))
        }

        // 获取所有星系ID
        let systemIDs = systems.map { Int($0.id) ?? 0 }

        // 使用 IN 语句一次性查询所有星系信息
        let query = """
                SELECT r.regionID, r.regionName, s.solarSystemName, s.solarSystemID, 
                s.solarSystemName_en, s.solarSystemName_zh
                FROM universe u
                JOIN regions r ON u.region_id = r.regionID
                JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                WHERE s.solarSystemID IN (\(systemIDs.map { String($0) }.joined(separator: ",")))
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            // 创建星系ID到星系信息的映射
            let systemInfoMap = Dictionary(
                uniqueKeysWithValues: rows.compactMap {
                    row -> (Int, (Int, String, String, String, String))? in
                    guard let systemID = row["solarSystemID"] as? Int,
                        let regionID = row["regionID"] as? Int,
                        let regionName = row["regionName"] as? String,
                        let systemName = row["solarSystemName"] as? String,
                        let systemNameEn = row["solarSystemName_en"] as? String,
                        let systemNameZh = row["solarSystemName_zh"] as? String
                    else {
                        return nil
                    }
                    return (
                        systemID, (regionID, regionName, systemName, systemNameEn, systemNameZh)
                    )
                })

            // 更新所有星系信息
            for i in 0..<systems.count {
                if let systemID = Int(systems[i].id),
                    let info = systemInfoMap[systemID]
                {
                    systems[i].regionID = info.0
                    systems[i].regionName = info.1
                    systems[i].systemName = info.2
                    systems[i].systemNameEn = info.3
                    systems[i].systemNameZh = info.4
                }
            }
        }

        commonSystems = systems
    }

    // 更新分组数据
    private func updateSections() {
        var filteredData = unpinnedRegions

        // 如果有搜索文本，过滤数据
        if !searchText.isEmpty {
            filteredData = unpinnedRegions.filter { region in
                // 搜索名称、英文名称和中文名称
                let nameMatch = region.name.localizedCaseInsensitiveContains(searchText)
                let nameEnMatch = region.nameEn.localizedCaseInsensitiveContains(searchText)
                let nameZhMatch = region.nameZh.localizedCaseInsensitiveContains(searchText)

                // 检查该星域是否有常见星系，如果有则同时搜索星系名称
                let systemMatch = commonSystems.contains { system in
                    system.regionID == region.id
                        && (system.systemName?.localizedCaseInsensitiveContains(searchText) ?? false
                            || system.systemNameEn?.localizedCaseInsensitiveContains(searchText)
                                ?? false
                            || system.systemNameZh?.localizedCaseInsensitiveContains(searchText)
                                ?? false)
                }

                return nameMatch || nameEnMatch || nameZhMatch || systemMatch
            }
        }

        // 按首字母分组
        let grouped = Dictionary(grouping: filteredData) { region -> String in
            // 获取首字母（包括处理中文拼音）
            let name = region.name
            if let firstChar = name.first {
                let firstLetter = getFirstLetter(of: String(firstChar))
                return firstLetter
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

    // 获取字符的首字母（包括中文拼音）
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

    // 获取星域对应的常见星系名称
    private func getCommonSystemName(for regionID: Int) -> String? {
        return commonSystems.first { $0.regionID == regionID }?.systemName
    }

    var body: some View {
        NavigationStack {
            List {
                // 置顶星域 Section
                Section(header: Text(NSLocalizedString("Main_Market_Pinned_Regions", comment: "")))
                {
                    if !pinnedRegions.isEmpty {
                        ForEach(pinnedRegions) { region in
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
                                onUnpin: {
                                    withAnimation {
                                        pinnedRegions.removeAll { $0.id == region.id }
                                        savePinnedRegions()
                                        updateSections()
                                    }
                                },
                                commonSystemName: getCommonSystemName(for: region.id)
                            )
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
                placement: .navigationBarDrawer(displayMode: .always),
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
        }
    }
}

// 星域行视图
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

struct MarketItemDetailView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let itemID: Int
    @State private var marketPath: [String] = []
    @State private var itemDetails: ItemDetails?
    @State private var lowestPrice: Double?
    @State private var isLoadingPrice: Bool = false
    @State private var marketOrders: [MarketOrder]?
    @State private var marketHistory: [MarketHistory]?
    @State private var isLoadingHistory: Bool = false
    @State private var isFromParent: Bool = true
    @State private var showRegionPicker = false
    @State private var selectedRegionID: Int
    @State private var selectedRegionName: String = ""
    @State private var saveSelection: Bool = true
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var chartHeight: CGFloat {
        // 根据设备类型和方向调整高度
        if horizontalSizeClass == .regular {
            // iPad 或大屏设备
            return 300
        } else {
            // iPhone 或小屏设备
            return UIScreen.main.bounds.height * 0.25  // 使用屏幕高度的 25%
        }
    }

    init(databaseManager: DatabaseManager, itemID: Int, selectedRegionID: Int = 0) {
        self.databaseManager = databaseManager
        self.itemID = itemID
        _selectedRegionID = State(initialValue: selectedRegionID)
    }

    var body: some View {
        List {
            // 基本信息部分
            Section {
                if let details = itemDetails {
                    NavigationLink {
                        ItemInfoMap.getItemInfoView(
                            itemID: itemID,
                            databaseManager: databaseManager
                        )
                    } label: {
                        MarketItemBasicInfoView(
                            itemDetails: details,
                            marketPath: marketPath
                        )
                    }
                }
            }

            // 价格信息部分
            Section {
                // 当前价格
                HStack {
                    IconManager.shared.loadImage(for: "icon_52996_64.png")
                        .resizable()
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(NSLocalizedString("Main_Market_Current_Price", comment: ""))
                            Button(action: {
                                Task {
                                    await loadMarketData(forceRefresh: true)
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                        }
                        HStack {
                            if isLoadingPrice {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else if let price = lowestPrice {
                                Text(formatPrice(price))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("-")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .frame(height: 15)
                    }
                }

                // 市场订单按钮
                NavigationLink {
                    if let details = itemDetails {
                        MarketOrdersView(
                            itemID: itemID,
                            itemName: details.name,
                            regionID: selectedRegionID,
                            initialOrders: marketOrders ?? [],
                            databaseManager: databaseManager
                        )
                    }
                } label: {
                    HStack {
                        Text(NSLocalizedString("Main_Market_Show_market_orders", comment: ""))
                        Spacer()
                        if isLoadingPrice {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }
.disabled(isLoadingPrice)
            }

            // 历史价格图表部分
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text(NSLocalizedString("Main_Market_Price_History", comment: ""))
                            .font(.headline)
                        if !isLoadingHistory {
                            Button(action: {
                                Task {
                                    await loadHistoryData(forceRefresh: true)
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    // 使用 ZStack 来保持固定高度
                    ZStack {
                        if isLoadingHistory {
                            ProgressView()
                        } else if let history = marketHistory, !history.isEmpty {
                            MarketHistoryChartView(
                                history: history,
                                orders: marketOrders ?? []
                            )
                        } else {
                            Text("-")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: chartHeight)  // 使用动态高度
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Market", comment: "市场详情"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showRegionPicker = true
                }) {
                    Text(selectedRegionName)
                        .foregroundColor(.blue)
                }
            }
        }
        .sheet(isPresented: $showRegionPicker) {
            MarketRegionPickerView(
                selectedRegionID: $selectedRegionID, selectedRegionName: $selectedRegionName,
                saveSelection: $saveSelection,
                databaseManager: databaseManager
            )
        }
        .onChange(of: selectedRegionID) { _, _ in
            Task {
                await loadAllMarketData(forceRefresh: true)
            }
        }
        .onAppear {
            let defaults = UserDefaultsManager.shared
            if selectedRegionID == 0 {
                selectedRegionID = defaults.selectedRegionID
                selectedRegionName = getRegionName(for: defaults.selectedRegionID)
            } else {
                selectedRegionName = getRegionName(for: selectedRegionID)
            }

            itemDetails = databaseManager.getItemDetails(for: itemID)

            if isFromParent {
                Task {
                    await loadAllMarketData()
                }
                isFromParent = false
            }
        }
    }

    private func loadMarketData(forceRefresh: Bool = false) async {
        guard !isLoadingPrice else { return }

        // 开始加载前清除旧数据
        marketOrders = nil
        lowestPrice = nil
        isLoadingPrice = true

        defer { isLoadingPrice = false }

        do {
            // 从 MarketOrdersAPI 获取数据
            let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                typeID: itemID,
                regionID: selectedRegionID,
                forceRefresh: forceRefresh
            )

            // 更新UI
            marketOrders = orders
            let sellOrders = orders.filter { !$0.isBuyOrder }
            lowestPrice = sellOrders.map { $0.price }.min()
        } catch {
            Logger.error("加载市场订单失败: \(error)")
            marketOrders = []
            lowestPrice = nil
        }
    }

    private func loadHistoryData(forceRefresh: Bool = false) async {
        guard !isLoadingHistory else { return }

        // 开始加载前清除旧数据
        marketHistory = nil
        isLoadingHistory = true

        defer { isLoadingHistory = false }

        do {
            // 从 MarketHistoryAPI 获取数据
            let history = try await MarketHistoryAPI.shared.fetchMarketHistory(
                typeID: itemID,
                regionID: selectedRegionID,
                forceRefresh: forceRefresh
            )

            // 更新UI
            marketHistory = history
        } catch {
            Logger.error("加载市场历史数据失败: \(error)")
            marketHistory = []
        }
    }

    // 格式化价格显示
    private func formatPrice(_ price: Double) -> String {
        let billion = 1_000_000_000.0
        let million = 1_000_000.0

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumFractionDigits = 2

        let formattedFullPrice =
            numberFormatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)

        if price >= billion {
            let value = price / billion
            return String(format: "%.2fB (%@ ISK)", value, formattedFullPrice)
        } else if price >= million {
            let value = price / million
            return String(format: "%.2fM (%@ ISK)", value, formattedFullPrice)
        } else {
            return "\(formattedFullPrice) ISK"
        }
    }

    // 并发加载所有市场数据
    private func loadAllMarketData(forceRefresh: Bool = false) async {
        // 并发执行两个加载任务
        async let marketDataTask: () = loadMarketData(forceRefresh: forceRefresh)
        async let historyDataTask: () = loadHistoryData(forceRefresh: forceRefresh)

        // 等待两个任务都完成
        await _ = (marketDataTask, historyDataTask)
    }

    // 根据区域ID获取区域名称的方法
    private func getRegionName(for regionID: Int) -> String {
        // 查询数据库获取区域名称
        let query = """
                SELECT regionName
                FROM regions
                WHERE regionID = ?
            """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [regionID]) {
            if let row = rows.first {
                let nameLocal = row["regionName"] as? String ?? ""
                return nameLocal
            }
        }

        // 如果查询失败或未找到，返回一个默认值
        return "Unknown Region"
    }
}
