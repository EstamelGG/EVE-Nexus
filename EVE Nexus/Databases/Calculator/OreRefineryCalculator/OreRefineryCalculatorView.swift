import SwiftUI

// 精炼结果数据结构
struct RefineryResultData: Identifiable {
    let id = UUID()
    let outputs: [Int: Int]
    let materialNames: [Int: String]
    let remaining: [Int: Int64]
}

struct OreRefineryCalculatorView: View {
    @ObservedObject var databaseManager: DatabaseManager

    // 精炼设置相关状态
    @State private var selectedRegionID: Int = 10_000_002 // 默认The Forge
    @State private var selectedRegionName: String = ""
    @State private var orderType: OrderType = .sell
    @State private var showRegionPicker = false
    @State private var showRefinerySettings = false
    @State private var isShowingItemSelector = false

    // 精炼设置参数
    @State private var systemSecurity: SystemSecurity = .nullSec
    @State private var structure: Structure = .structure2
    @State private var structureRigs: StructureRigs = .t2
    @State private var implant: Implant = .implant3
    @State private var taxRate: Double = UserDefaultsManager.shared.refineryTaxRate

    // 记录选择的typeID
    @State private var selectedStructureTypeID: Int = 35836 // 默认精炼建筑
    @State private var selectedImplantTypeID: Int = 27174 // 默认精炼植入体

    // 技能相关状态
    @State private var selectedCharacterSkills: [Int: Int] = [:]
    @State private var selectedCharacterName: String = ""
    @State private var selectedCharacterId: Int = 0

    // 计算相关状态
    @State private var isLoadingOrders = false
    @State private var marketOrders: [Int: [MarketOrder]] = [:]
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil
    @State private var isEditingQuantity = false
    @State private var considerOrderQuantity = true // 是否考虑订单数量，默认选中

    // 导入导出相关状态
    @State private var isShowingClipboardAlert = false
    @State private var clipboardResult = ""
    @State private var isShowingExportAlert = false
    @State private var exportResult = ""
    @State private var isShowingImportConfirmation = false
    @State private var clipboardContentToImport = ""

    // 矿石列表和相关数据
    @State private var oreItems: [QuickbarItem] = []
    @State private var items: [DatabaseListItem] = []
    @State private var itemQuantities: [Int: Int64] = [:]
    @State private var itemVolumes: [Int: Double] = [:]

    // 精炼比例状态
    @State private var itemRefineryRatios: [Int: Double] = [:] // 物品ID -> 精炼比例
    @State private var itemRefineryStatus: [Int: RefineryStatus] = [:] // 物品ID -> 精炼状态

    // 精炼结果状态
    @State private var refineryResultData: RefineryResultData? = nil

    // 订单类型枚举
    private enum OrderType: String, CaseIterable {
        case buy = "Main_Market_Order_Buy"
        case sell = "Main_Market_Order_Sell"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    // 星系安等枚举
    enum SystemSecurity: String, CaseIterable {
        case highSec = "Security_HighSec"
        case lowSec = "Security_LowSec"
        case nullSec = "Security_NullSec"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    // 建筑枚举
    enum Structure: String, CaseIterable {
        case structure1 = "35835" // 精炼建筑1
        case structure2 = "35836" // 精炼建筑2

        var typeID: Int {
            Int(rawValue) ?? 0
        }

        var displayName: String {
            // 从数据库获取名称
            let query = "SELECT name FROM types WHERE type_id = ?"
            if case let .success(rows) = DatabaseManager.shared.executeQuery(
                query, parameters: [typeID]
            ),
                let row = rows.first,
                let name = row["name"] as? String
            {
                return name
            }

            // 如果查询失败，返回默认名称
            return "Unknown Structure"
        }
    }

    // 建筑插件枚举
    enum StructureRigs: String, CaseIterable {
        case none = "Ore_Refinery_Rig_None"
        case t1 = "Ore_Refinery_Rig_T1"
        case t2 = "Ore_Refinery_Rig_T2"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    // 植入体枚举
    enum Implant: String, CaseIterable {
        case none = "0" // 无植入体
        case implant1 = "27175" // 精炼植入体1
        case implant2 = "27169" // 精炼植入体2
        case implant3 = "27174" // 精炼植入体3

        var typeID: Int {
            Int(rawValue) ?? 0
        }

        var displayName: String {
            // 特殊处理"无"的情况
            if self == .none {
                return NSLocalizedString("Ore_Refinery_Implant_None", comment: "")
            }

            // 从数据库获取名称
            let query = "SELECT name FROM types WHERE type_id = ?"
            if case let .success(rows) = DatabaseManager.shared.executeQuery(
                query, parameters: [typeID]
            ),
                let row = rows.first,
                let name = row["name"] as? String
            {
                return name
            }

            // 如果查询失败，返回默认名称
            return "Unknown Implant"
        }
    }

    var body: some View {
        VStack {
            List {
                Section {
                    // 市场地点选择器
                    HStack {
                        Text(NSLocalizedString("Main_Market_Location", comment: ""))
                        Spacer()
                        Button {
                            selectedRegionID = selectedRegionID
                            showRegionPicker = true
                        } label: {
                            HStack {
                                Text(selectedRegionName)
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundColor(.secondary)
                                    .imageScale(.small)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }

                    // 订单类型选择器
                    HStack {
                        Text(NSLocalizedString("Main_Market_Order_Type", comment: ""))
                        Spacer()
                        Picker("", selection: $orderType) {
                            Text(OrderType.sell.localizedName).tag(OrderType.sell)
                            Text(OrderType.buy.localizedName).tag(OrderType.buy)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }

                    // 精炼设置按钮
                    Button {
                        showRefinerySettings = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Ore_Refinery_Settings", comment: ""))

                                // 显示当前选择的建筑和植入体
                                HStack {
                                    Text(
                                        "\(NSLocalizedString("Ore_Refinery_Structure_Label", comment: "")): \(structure.displayName)"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    Spacer()
                                }

                                HStack {
                                    Text(
                                        "\(NSLocalizedString("Ore_Refinery_Implant_Label", comment: "")): \(implant.displayName)"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    Spacer()
                                }

                                // 显示当前选择的技能
                                HStack {
                                    let skillText =
                                        selectedCharacterName.isEmpty
                                            ? NSLocalizedString(
                                                "Ore_Refinery_All_Skills_Level", comment: ""
                                            )
                                            : selectedCharacterName
                                    Text(
                                        "\(NSLocalizedString("Ore_Refinery_Skills_Label", comment: "")): \(skillText)"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .imageScale(.small)
                        }
                    }
                    .foregroundColor(.primary)

                    // 市场价格显示
                    HStack {
                        Text(NSLocalizedString("Main_Market_Price", comment: ""))
                        Spacer()
                        if isLoadingOrders {
                            // 显示详细的页数进度（只在这里显示）
                            if StructureMarketManager.isStructureId(selectedRegionID),
                               let progress = structureOrdersProgress
                            {
                                switch progress {
                                case let .loading(currentPage, totalPages):
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("\(currentPage)/\(totalPages)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                case .completed:
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                            } else {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        } else {
                            let priceInfo = calculateTotalPrice()
                            if priceInfo.total > 0 {
                                Text("\(FormatUtil.formatISK(priceInfo.total))")
                                    .foregroundColor(
                                        priceInfo.hasInsufficientStock ? .red : .secondary)
                            } else {
                                Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // 总体积显示
                    HStack {
                        Text(NSLocalizedString("Total_volume", comment: ""))
                        Spacer()
                        let totalVolume = calculateTotalVolume()
                        Text("\(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text(NSLocalizedString("Ore_Refinery_Basic_Settings", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                // 矿石列表部分 - 如果为空则显示空状态
                if oreItems.isEmpty {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "cube.box")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)

                            Text(NSLocalizedString("Ore_Refinery_No_Items", comment: ""))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } header: {
                        Text(NSLocalizedString("Main_Market_Item_List", comment: ""))
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                    }
                } else {
                    Section {
                        ForEach(items, id: \.id) { item in
                            oreItemRow(item)
                        }
                        .onDelete { indexSet in
                            let itemsToDelete = indexSet.map { items[$0].id }
                            oreItems.removeAll { itemsToDelete.contains($0.typeID) }
                            items.removeAll { itemsToDelete.contains($0.id) }
                            for itemID in itemsToDelete {
                                itemVolumes.removeValue(forKey: itemID)
                                itemQuantities.removeValue(forKey: itemID)
                            }
                            // 删除后重新加载市场订单
                            Task {
                                await loadAllMarketOrders()
                            }
                        }
                    } header: {
                        HStack {
                            Text(NSLocalizedString("Main_Market_Item_List", comment: ""))
                                .fontWeight(.semibold)
                                .font(.system(size: 18))
                                .foregroundColor(.primary)
                                .textCase(.none)

                            Spacer()

                            Button {
                                considerOrderQuantity.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(
                                        systemName: considerOrderQuantity
                                            ? "checkmark.circle.fill" : "circle"
                                    )
                                    .foregroundColor(considerOrderQuantity ? .blue : .secondary)
                                    Text(
                                        NSLocalizedString(
                                            "Blueprint_Calculator_Consider_Quantity",
                                            comment: "考虑订单数量"
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(
                                isEditingQuantity
                                    ? NSLocalizedString("Main_Market_Done_Edit", comment: "")
                                    : NSLocalizedString("Main_Market_Edit_Quantity", comment: "")
                            ) {
                                withAnimation {
                                    isEditingQuantity.toggle()
                                }
                            }
                            .foregroundColor(.accentColor)
                            .font(.system(size: 14))
                        }
                    }
                }
            }
            .refreshable {
                // 强制刷新市场订单
                await loadAllMarketOrders(forceRefresh: true)
            }

            // 底部计算按钮
            Button(action: {
                // 执行精炼计算
                performRefineryCalculation()
            }) {
                Text(NSLocalizedString("Ore_Refinery_Calculate", comment: ""))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(oreItems.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(oreItems.isEmpty)
            .padding()
        }
        .navigationTitle(NSLocalizedString("Ore_Refinery_Calculator", comment: ""))
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // 导入按钮
                Button {
                    prepareImportFromClipboard()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }

                // 导出按钮
                Button {
                    exportToClipboard()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(oreItems.isEmpty)

                // 添加物品按钮
                Button {
                    isShowingItemSelector = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showRegionPicker) {
            MarketRegionPickerView(
                selectedRegionID: $selectedRegionID,
                selectedRegionName: $selectedRegionName,
                saveSelection: .constant(false),
                databaseManager: databaseManager
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRefinerySettings) {
            RefinerySettingsView(
                systemSecurity: $systemSecurity,
                structure: $structure,
                structureRigs: $structureRigs,
                implant: $implant,
                taxRate: $taxRate,
                selectedCharacterSkills: $selectedCharacterSkills,
                selectedCharacterName: $selectedCharacterName,
                selectedCharacterId: $selectedCharacterId
            )
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $refineryResultData) { data in
            NavigationView {
                RefineryResultView(
                    databaseManager: databaseManager,
                    taxRate: taxRate,
                    refineryOutputs: data.outputs,
                    materialNameMap: data.materialNames,
                    remainingItems: data.remaining
                )
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isShowingItemSelector) {
            // TODO: 实现矿石选择器 - 可以复用MarketItemSelectorView但需要限制只显示矿石
            MarketItemSelectorView(
                databaseManager: databaseManager,
                existingItems: Set(oreItems.map { $0.typeID }),
                onItemSelected: { applyOreSelectorItems([$0]) },
                onBatchItemsSelected: { applyOreSelectorItems($0) },
                onItemDeselected: { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        oreItems.removeAll { $0.typeID == item.id }
                        itemVolumes.removeValue(forKey: item.id)
                        // 移除物品后更新精炼比例
                        itemRefineryStatus.removeValue(forKey: item.id)
                        itemRefineryRatios.removeValue(forKey: item.id)
                    }
                },
                showSelected: true,
                allowTypeIDs: nil // TODO: 这里应该限制只显示矿石类物品
            )
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedRegionID) { oldValue, newValue in
            if oldValue != newValue {
                loadRegionName()
                // 地区变化时重新加载市场订单
                Task {
                    await loadAllMarketOrders()
                }
            }
        }
        .onChange(of: structure) { _, newStructure in
            selectedStructureTypeID = newStructure.typeID
            // 建筑变化时重新计算精炼比例
            calculateBatchRefineryRatios()
        }
        .onChange(of: implant) { _, newImplant in
            selectedImplantTypeID = newImplant.typeID
            // 植入体变化时重新计算精炼比例
            calculateBatchRefineryRatios()
        }
        .onChange(of: structureRigs) { _, _ in
            // 建筑插件变化时重新计算精炼比例
            calculateBatchRefineryRatios()
        }
        .onChange(of: systemSecurity) { _, _ in
            // 安全等级变化时重新计算精炼比例
            calculateBatchRefineryRatios()
        }
        .onChange(of: selectedCharacterSkills) { _, _ in
            // 技能变化时重新计算精炼比例
            calculateBatchRefineryRatios()
        }
        .alert(
            NSLocalizedString("Main_Market_Clipboard_Import", comment: ""),
            isPresented: $isShowingClipboardAlert
        ) {
            Button(NSLocalizedString("Misc_Done", comment: "")) {
                clipboardResult = ""
            }
        } message: {
            Text(clipboardResult)
        }
        .alert(
            NSLocalizedString("Main_Market_Clipboard_Export", comment: ""),
            isPresented: $isShowingExportAlert
        ) {
            Button(NSLocalizedString("Misc_Done", comment: "")) {
                exportResult = ""
            }
        } message: {
            Text(exportResult)
        }
        .alert(
            NSLocalizedString("Main_Market_Clipboard_Import_Confirm", comment: ""),
            isPresented: $isShowingImportConfirmation
        ) {
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                clipboardContentToImport = ""
            }
            Button(
                NSLocalizedString("Main_Market_Clipboard_Import_Confirm_Yes", comment: ""),
                role: .destructive
            ) {
                importFromClipboard()
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Main_Market_Clipboard_Import_Confirm_Message", comment: ""
                    ), oreItems.count
                ))
        }
        .onAppear {
            loadRegionName()
            loadItems()

            // 确保税率从UserDefaults正确加载
            taxRate = UserDefaultsManager.shared.refineryTaxRate
            Logger.info("主视图 onAppear - 加载保存的税率: \(taxRate)%")

            // 初始化技能为all5
            if selectedCharacterSkills.isEmpty {
                selectedCharacterSkills = CharacterSkillsUtils.getCharacterSkills(type: .all5)
                selectedCharacterName = String(
                    format: NSLocalizedString("Fitting_All_Skills", comment: "全n级"), 5
                )
                selectedCharacterId = 0
            }

            // 初始化时计算精炼比例
            calculateBatchRefineryRatios()
        }
    }

    /// 选择器批量添加矿石：一次体积与精炼比例更新、一次订单任务
    private func applyOreSelectorItems(_ newItems: [DatabaseListItem]) {
        let existingTypeIDs = Set(oreItems.map(\.typeID))
        let toAdd = newItems.filter { !existingTypeIDs.contains($0.id) }
        guard !toAdd.isEmpty else { return }
        for item in toAdd {
            items.append(item)
            oreItems.append(QuickbarItem(typeID: item.id))
        }
        let sorted = items.sorted(by: { $0.id < $1.id })
        items = sorted
        oreItems = sorted.map { item in
            QuickbarItem(
                typeID: item.id,
                quantity: oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
            )
        }
        itemQuantities = Dictionary(uniqueKeysWithValues: oreItems.map { ($0.typeID, $0.quantity) })
        loadItemVolumes()
        calculateBatchRefineryRatios()
        Task {
            await loadAllMarketOrders()
        }
    }

    // 矿石项目行视图
    @ViewBuilder
    private func oreItemRow(_ item: DatabaseListItem) -> some View {
        if isEditingQuantity {
            HStack(spacing: 12) {
                Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .lineLimit(1)

                    let priceInfo = getListPrice(for: item)
                    if let price = priceInfo.price {
                        Text(
                            NSLocalizedString("Main_Market_Avg_Price", comment: "")
                                + FormatUtil.format(price)
                                + " ISK"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Text(
                                NSLocalizedString("Main_Market_Total_Price", comment: "")
                                    + FormatUtil.format(
                                        price * Double(itemQuantities[item.id] ?? 1))
                                    + " ISK"
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                            if priceInfo.insufficientStock {
                                Text(
                                    NSLocalizedString("Main_Market_Insufficient_Stock", comment: "")
                                )
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }
                    } else {
                        Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                TextField(
                    "",
                    text: Binding(
                        get: { String(itemQuantities[item.id] ?? 1) },
                        set: { newValue in
                            if let quantity = Int64(newValue) {
                                let validValue = max(1, min(999_999_999, quantity))
                                itemQuantities[item.id] = validValue
                                if let index = oreItems.firstIndex(where: {
                                    $0.typeID == item.id
                                }) {
                                    oreItems[index].quantity = validValue
                                }
                            } else {
                                itemQuantities[item.id] = 1
                                if let index = oreItems.firstIndex(where: {
                                    $0.typeID == item.id
                                }) {
                                    oreItems[index].quantity = 1
                                }
                            }
                        }
                    )
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.numberPad)
                .multilineTextAlignment(.leading)
                .frame(width: 80)
            }
        } else {
            NavigationLink {
                MarketItemDetailView(
                    databaseManager: databaseManager,
                    itemID: item.id,
                    selectedRegionID: selectedRegionID // 传递当前选中的星域ID
                )
            } label: {
                HStack(spacing: 12) {
                    Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)

                        if isLoadingOrders {
                            // 显示简单的加载指示器
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text(NSLocalizedString("Main_Database_Loading", comment: "加载中..."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            // 显示价格信息
                            let priceInfo = getListPrice(for: item)
                            if let price = priceInfo.price {
                                Text(
                                    NSLocalizedString("Main_Market_Avg_Price", comment: "")
                                        + FormatUtil.format(price)
                                        + " ISK"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                Text(
                                    NSLocalizedString("Main_Market_Total_Price", comment: "")
                                        + FormatUtil.format(
                                            price
                                                * Double(
                                                    oreItems.first(where: { $0.typeID == item.id }
                                                    )?.quantity ?? 1))
                                        + " ISK"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                if priceInfo.insufficientStock {
                                    Text(
                                        NSLocalizedString(
                                            "Main_Market_Insufficient_Stock", comment: ""
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                            } else {
                                Text(NSLocalizedString("Main_Market_No_Orders", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        // 精炼比例显示（在价格下方）
                        let refineryStatus = itemRefineryStatus[item.id] ?? .unknown
                        HStack(spacing: 4) {
                            Text(NSLocalizedString("Ore_Refinery_Ratio_Label", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(refineryStatus.displayText)
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .fontWeight(.medium)
                                .foregroundColor(refineryStatus.isRefinable ? .green : .red)
                        }
                    }

                    Spacer()

                    Text(getItemQuantity(for: item))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // 计算总价格
    private func calculateTotalPrice() -> (total: Double, hasInsufficientStock: Bool) {
        var total: Double = 0
        var hasInsufficientStock = false

        for item in items {
            let priceInfo = getListPrice(for: item)
            if let price = priceInfo.price {
                let quantity = oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
                total += price * Double(quantity)
            }
            if priceInfo.insufficientStock {
                hasInsufficientStock = true
            }
        }
        return (total, hasInsufficientStock)
    }

    // 计算总体积
    private func calculateTotalVolume() -> Double {
        var totalVolume: Double = 0

        for item in items {
            if let volume = itemVolumes[item.id] {
                let quantity = oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
                totalVolume += volume * Double(quantity)
            }
        }

        return totalVolume
    }

    // 获取物品价格信息
    private func getListPrice(for item: DatabaseListItem) -> (
        price: Double?, insufficientStock: Bool
    ) {
        guard let orders = marketOrders[item.id] else { return (nil, true) }
        let quantity = oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1

        var filteredOrders = orders.filter { $0.isBuyOrder == (orderType == .buy) }
        filteredOrders.sort { orderType == .buy ? $0.price > $1.price : $0.price < $1.price }

        if filteredOrders.isEmpty {
            return (nil, true)
        }

        // 如果不考虑订单数量，直接使用最优价格
        if !considerOrderQuantity {
            let bestPrice = filteredOrders.first?.price ?? 0
            return (bestPrice, false)
        }

        // 考虑订单数量的原有逻辑
        var remainingQuantity = quantity
        var totalPrice: Double = 0
        var availableQuantity: Int64 = 0

        for order in filteredOrders {
            if remainingQuantity <= 0 { break }

            let orderQuantity = min(remainingQuantity, Int64(order.volumeRemain))
            totalPrice += Double(orderQuantity) * order.price
            remainingQuantity -= orderQuantity
            availableQuantity += orderQuantity
        }

        if remainingQuantity > 0, availableQuantity > 0 {
            return (totalPrice / Double(availableQuantity), true)
        } else if remainingQuantity > 0 {
            return (nil, true)
        }

        return (totalPrice / Double(quantity), false)
    }

    // 获取物品数量显示文本
    private func getItemQuantity(for item: DatabaseListItem) -> String {
        let quantity = oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: quantity)) ?? "1"
    }

    // 加载区域名称
    private func loadRegionName() {
        if StructureMarketManager.isStructureId(selectedRegionID) {
            // 是建筑ID，查找建筑名称
            if let structureId = StructureMarketManager.getStructureId(from: selectedRegionID),
               let structure = getStructureById(structureId)
            {
                selectedRegionName = structure.structureName
            } else {
                selectedRegionName = "Unknown Structure"
            }
        } else {
            // 是星域ID，查找星域名称
            let query = """
                SELECT regionName
                FROM regions
                WHERE regionID = ?
            """

            if case let .success(rows) = databaseManager.executeQuery(
                query, parameters: [selectedRegionID]
            ) {
                if let row = rows.first, let name = row["regionName"] as? String {
                    selectedRegionName = name
                }
            }
        }
    }

    // 根据建筑ID获取建筑信息
    private func getStructureById(_ structureId: Int64) -> MarketStructure? {
        return MarketStructureManager.shared.structures.first { $0.structureId == Int(structureId) }
    }

    // 加载物品列表
    private func loadItems() {
        if !oreItems.isEmpty {
            let itemIDs = oreItems.map { String($0.typeID) }.joined(separator: ",")
            items = databaseManager.loadMarketItems(
                whereClause: "t.type_id IN (\(itemIDs))",
                parameters: []
            )
            // 按 type_id 排序并更新
            let sorted = items.sorted(by: { $0.id < $1.id })
            items = sorted
            // 更新 itemQuantities
            itemQuantities = Dictionary(
                uniqueKeysWithValues: oreItems.map { ($0.typeID, $0.quantity) })
            // 确保 oreItems 的顺序与加载的物品顺序一致
            oreItems = sorted.map { item in
                QuickbarItem(
                    typeID: item.id,
                    quantity: oreItems.first(where: { $0.typeID == item.id })?.quantity ?? 1
                )
            }
            // 加载物品体积信息
            loadItemVolumes()
        }
    }

    // 加载物品体积信息
    private func loadItemVolumes() {
        guard !items.isEmpty else { return }

        let typeIDs = items.map { String($0.id) }.joined(separator: ",")
        let query = "SELECT type_id, volume FROM types WHERE type_id IN (\(typeIDs))"

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let volume = row["volume"] as? Double
                {
                    itemVolumes[typeID] = volume
                }
            }
        }
    }

    // 加载所有物品的市场订单
    private func loadAllMarketOrders(forceRefresh: Bool = false) async {
        guard !items.isEmpty else { return }

        // 防止重复加载
        if isLoadingOrders, !forceRefresh {
            return
        }

        await MainActor.run {
            isLoadingOrders = true
        }

        defer {
            Task { @MainActor in
                isLoadingOrders = false
            }
        }

        await MainActor.run {
            marketOrders.removeAll()
        }

        let typeIds = items.map { $0.id }
        let newOrders = await loadOrdersForItems(
            typeIds: typeIds,
            regionID: selectedRegionID,
            forceRefresh: forceRefresh,
            progressCallback: { progress in
                Task { @MainActor in
                    structureOrdersProgress = progress
                }
            }
        )

        await MainActor.run {
            marketOrders = newOrders
        }
    }

    // MARK: - 通用订单加载方法

    private func loadOrdersForItems(
        typeIds: [Int],
        regionID: Int,
        forceRefresh: Bool = false,
        progressCallback: ((StructureOrdersProgress) -> Void)? = nil
    ) async -> [Int: [MarketOrder]] {
        if StructureMarketManager.isStructureId(regionID) {
            // 建筑订单
            guard let structureId = StructureMarketManager.getStructureId(from: regionID),
                  let structure = getStructureById(structureId)
            else {
                Logger.error("无效的建筑ID或未找到建筑信息: \(regionID)")
                return [:]
            }

            do {
                Logger.info("开始加载建筑订单，物品数量: \(typeIds.count)")

                let batchOrders = try await StructureMarketManager.shared
                    .getBatchItemOrdersInStructure(
                        structureId: structureId,
                        characterId: structure.characterId,
                        typeIds: typeIds,
                        forceRefresh: forceRefresh,
                        progressCallback: progressCallback
                    )

                Logger.success("成功加载建筑订单，获得 \(batchOrders.count) 个物品的订单数据")
                return batchOrders
            } catch {
                Logger.error("批量加载建筑订单失败: \(error)")
                return [:]
            }
        } else {
            // 星域订单
            let concurrency = max(1, min(10, typeIds.count))
            Logger.info("开始加载星域订单，物品数量: \(typeIds.count)，并发数: \(concurrency)")

            var newOrders: [Int: [MarketOrder]] = [:]

            await withTaskGroup(of: (Int, [MarketOrder])?.self) { group in
                var pendingTypeIds = typeIds

                for _ in 0 ..< concurrency {
                    if !pendingTypeIds.isEmpty {
                        let typeId = pendingTypeIds.removeFirst()
                        group.addTask {
                            do {
                                let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                    typeID: typeId,
                                    regionID: regionID,
                                    forceRefresh: forceRefresh
                                )
                                return (typeId, orders)
                            } catch {
                                Logger.error("加载市场订单失败 (物品ID: \(typeId)): \(error)")
                                return nil
                            }
                        }
                    }
                }

                while let result = await group.next() {
                    if let (typeID, orders) = result {
                        newOrders[typeID] = orders
                    }

                    if !pendingTypeIds.isEmpty {
                        let typeId = pendingTypeIds.removeFirst()
                        group.addTask {
                            do {
                                let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                    typeID: typeId,
                                    regionID: regionID,
                                    forceRefresh: forceRefresh
                                )
                                return (typeId, orders)
                            } catch {
                                Logger.error("加载市场订单失败 (物品ID: \(typeId)): \(error)")
                                return nil
                            }
                        }
                    }
                }
            }

            Logger.info("完成星域订单加载，成功获取 \(newOrders.count) 个物品的订单数据")
            return newOrders
        }
    }

    // 准备从剪贴板导入物品（显示确认对话框）
    private func prepareImportFromClipboard() {
        guard let clipboardContent = UIPasteboard.general.string else {
            clipboardResult = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
            isShowingClipboardAlert = true
            return
        }

        // 检查剪贴板内容是否为空
        if clipboardContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clipboardResult = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
            isShowingClipboardAlert = true
            return
        }

        // 存储剪贴板内容
        clipboardContentToImport = clipboardContent

        // 如果当前列表有内容，显示确认对话框
        if oreItems.count > 0 {
            isShowingImportConfirmation = true
        } else {
            // 当前列表为空，直接导入
            importFromClipboard()
        }
    }

    // 从剪贴板导入物品
    private func importFromClipboard() {
        guard !clipboardContentToImport.isEmpty else {
            clipboardResult = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
            isShowingClipboardAlert = true
            return
        }

        let importResult = MarketClipboardParser.parseClipboardContent(
            clipboardContentToImport,
            databaseManager: databaseManager,
            existingItems: oreItems
        )

        // 根据解析结果处理不同情况
        if importResult.successCount == 0, importResult.failedItems.isEmpty {
            // 情况1: 剪贴板内容为空或无有效内容
            clipboardResult = NSLocalizedString("Main_Market_Clipboard_Empty", comment: "剪贴板为空")
            isShowingClipboardAlert = true
        } else if importResult.successCount == 0, importResult.failedItems.count > 0 {
            // 情况2: 全部解析失败
            clipboardResult = NSLocalizedString(
                "Main_Market_Clipboard_All_Failed", comment: "全部解析失败"
            )
            isShowingClipboardAlert = true
        } else if importResult.successCount > 0 {
            // 情况3和4: 有成功的解析结果，更新列表
            oreItems = importResult.updatedItems

            // 重新加载物品列表
            loadItems()
            // 重新加载物品体积信息
            loadItemVolumes()
            // 导入物品后立即计算精炼比例
            calculateBatchRefineryRatios()
            // 重新加载市场订单
            Task {
                await loadAllMarketOrders()
            }

            if importResult.failedItems.count > 0 {
                // 情况3: 部分成功，部分失败
                var resultMessage = String(
                    format: NSLocalizedString("Main_Market_Clipboard_Partial_Success", comment: ""),
                    importResult.successCount
                )

                // 显示失败的前三行内容
                let failedToShow = Array(importResult.failedItems.prefix(3))
                if !failedToShow.isEmpty {
                    resultMessage +=
                        "\n\n"
                        + NSLocalizedString(
                            "Main_Market_Clipboard_Failed_Items", comment: "解析失败的项目:"
                        )
                    resultMessage += "\n" + failedToShow.joined(separator: "\n")

                    // 如果失败项目超过3个，显示省略提示
                    if importResult.failedItems.count > 3 {
                        resultMessage += "\n..."
                        resultMessage += String(
                            format: NSLocalizedString(
                                "Main_Market_Clipboard_More_Failed", comment: ""
                            ),
                            importResult.failedItems.count - 3
                        )
                    }
                }

                clipboardResult = resultMessage
            } else {
                // 情况4: 全部成功
                clipboardResult = String(
                    format: NSLocalizedString("Main_Market_Clipboard_All_Success", comment: ""),
                    importResult.successCount
                )
            }

            isShowingClipboardAlert = true
        }

        clipboardContentToImport = "" // 清空临时存储的内容
    }

    // 执行精炼计算
    private func performRefineryCalculation() {
        Logger.info("=== 开始精炼计算 ===")

        // 1. 检查是否有待精炼物品
        guard !oreItems.isEmpty else {
            Logger.warning("没有待精炼物品")
            return
        }

        // 2. 获取所选人物的技能数据
        Logger.info("角色技能信息:")
        Logger.info("- 角色名称: \(selectedCharacterName)")
        Logger.info("- 角色ID: \(selectedCharacterId)")
        Logger.info("- 技能数量: \(selectedCharacterSkills.count)")

        // 显示前10个技能作为示例
        let skillExamples = Array(selectedCharacterSkills.prefix(10))
        for (skillId, level) in skillExamples {
            Logger.info("  - 技能ID \(skillId): 等级 \(level)")
        }
        if selectedCharacterSkills.count > 10 {
            Logger.info("  ... 还有 \(selectedCharacterSkills.count - 10) 个技能")
        }

        // 3. 获取精炼设置
        Logger.info("精炼设置:")
        Logger.info("- 星系安等: \(systemSecurity.localizedName)")
        Logger.info("- 建筑: \(structure.displayName) (TypeID: \(structure.typeID))")
        Logger.info("- 建筑插件: \(structureRigs.localizedName)")
        Logger.info("- 植入体: \(implant.displayName) (TypeID: \(implant.typeID))")
        Logger.info("- 建筑税率: \(taxRate)%")

        // 4. 获取当前页面已添加的待精炼物品
        Logger.info("待精炼物品列表:")
        for (index, oreItem) in oreItems.enumerated() {
            if let item = items.first(where: { $0.id == oreItem.typeID }) {
                let quantity = itemQuantities[item.id] ?? 1
                let volume = itemVolumes[item.id] ?? 0.0
                let totalVolume = volume * Double(quantity)

                Logger.info("  \(index + 1). \(item.name)")
                Logger.info("     - 物品ID: \(item.id)")
                Logger.info("     - 数量: \(quantity)")
                Logger.info(
                    "     - 单个体积: \(FormatUtil.formatForUI(volume, maxFractionDigits: 2)) m³")
                Logger.info(
                    "     - 总体积: \(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³")
            }
        }

        // 5. 计算总体积和总价值
        let totalVolume = calculateTotalVolume()
        let totalPrice = calculateTotalPrice()

        Logger.info("总计:")
        Logger.info("- 物品种类: \(oreItems.count)")
        Logger.info("- 总体积: \(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³")
        Logger.info("- 总价值: \(FormatUtil.formatISK(totalPrice.total)) ISK")
        if totalPrice.hasInsufficientStock {
            Logger.warning("- 部分物品库存不足")
        }

        // 6. 获取精炼输出信息
        Logger.info("=== 精炼输出信息 ===")
        var totalRefineryOutputs: [Int: Int] = [:] // 输出材料ID -> 总数量
        var materialNameMap: [Int: String] = [:] // 材料ID -> 材料名称

        // 批量获取所有物品的精炼信息和分类信息
        let allTypeIDs = items.map { $0.id }
        let allTypeMaterials = getBatchTypeMaterials(for: allTypeIDs)
        var itemCategories = getBatchItemCategories(for: allTypeIDs)

        // 更新物品分类：将没有精炼产出的物品标记为noOutput
        for typeID in allTypeIDs {
            if itemCategories[typeID] != nil, allTypeMaterials[typeID] == nil {
                // 有分类信息但没有精炼产出，标记为noOutput
                if let existingInfo = itemCategories[typeID] {
                    itemCategories[typeID] = ItemCategoryInfo(
                        typeID: existingInfo.typeID,
                        categoryID: existingInfo.categoryID,
                        groupID: existingInfo.groupID,
                        itemType: .noOutput,
                        reprocessingSkillType: existingInfo.reprocessingSkillType
                    )
                }
            }
        }

        for (index, oreItem) in oreItems.enumerated() {
            if let item = items.first(where: { $0.id == oreItem.typeID }) {
                let inputQuantity = itemQuantities[item.id] ?? 1
                let categoryInfo = itemCategories[item.id]

                Logger.info("  \(index + 1). \(item.name) (TypeID: \(item.id))")
                Logger.info("     - 输入数量: \(inputQuantity)")
                Logger.info("     - 物品类型: \(categoryInfo?.itemType.description ?? "未知")")

                // 从批量查询结果中获取该物品的精炼输出信息
                if let typeMaterials = allTypeMaterials[item.id] {
                    Logger.info("     - 精炼批次大小: \(typeMaterials.first?.process_size ?? 0)")

                    // 计算可以进行多少次精炼
                    let processSize = typeMaterials.first?.process_size ?? 1
                    let refineryCount = inputQuantity / Int64(processSize)
                    let remainder = inputQuantity % Int64(processSize)

                    Logger.info("     - 可精炼次数: \(refineryCount)")
                    if remainder > 0 {
                        Logger.info("     - 剩余无法精炼: \(remainder)")
                    }

                    // 计算精炼加成系数（使用重构后的可复用逻辑）
                    var refineryBonus = 1.0
                    if let categoryInfo = categoryInfo {
                        let context = getCurrentRefineryContext()
                        refineryBonus = calculateRefineryBonus(
                            itemID: item.id,
                            categoryInfo: categoryInfo,
                            context: context
                        )

                        // 根据物品类型记录日志
                        switch categoryInfo.itemType {
                        case .oreAndIce:
                            Logger.info("     - 精炼加成系数: \(refineryBonus)")
                        case .gas:
                            Logger.info("     - 气云解压效率: \(refineryBonus)")
                        case .other:
                            Logger.info("     - 其他物品精炼系数: \(refineryBonus)")
                        case .noOutput:
                            Logger.info("     - 无精炼产出，原样输出")
                        }
                    }

                    // 根据物品类型计算输出
                    switch categoryInfo?.itemType {
                    case .noOutput:
                        // 无精炼产出，原样输出
                        Logger.info("     - 原样输出: \(inputQuantity)")
                    // 这里可以添加原样输出的逻辑，比如添加到总输出中

                    default:
                        // 有精炼产出，计算输出材料
                        if let typeMaterials = allTypeMaterials[item.id] {
                            Logger.info("     - 精炼输出:")
                            for material in typeMaterials {
                                let baseOutputQuantity =
                                    Int64(material.outputQuantity) * refineryCount
                                let finalOutputQuantity: Int64

                                switch categoryInfo?.itemType {
                                case .gas:
                                    // 气云解压：直接应用效率系数
                                    finalOutputQuantity = Int64(
                                        Double(baseOutputQuantity) * refineryBonus)
                                case .other:
                                    // 其他物品：应用精炼系数
                                    finalOutputQuantity = Int64(
                                        Double(baseOutputQuantity) * refineryBonus)
                                default:
                                    // 矿石和冰矿：应用精炼加成
                                    finalOutputQuantity = Int64(
                                        Double(baseOutputQuantity) * refineryBonus)
                                }

                                Logger.info(
                                    "       * \(material.outputMaterialName) (TypeID: \(material.outputMaterial)): \(finalOutputQuantity) (基础: \(baseOutputQuantity), 加成后: \(finalOutputQuantity))"
                                )

                                // 累计到总输出中
                                totalRefineryOutputs[material.outputMaterial, default: 0] += Int(
                                    finalOutputQuantity)

                                // 保存材料名称映射
                                materialNameMap[material.outputMaterial] =
                                    material.outputMaterialName
                            }
                        }
                    }
                } else {
                    Logger.warning("     - 未找到精炼输出信息")
                }
            }
        }

        // 7. 输出总精炼结果
        if !totalRefineryOutputs.isEmpty {
            Logger.info("=== 总精炼输出 ===")

            // 输出总精炼结果
            for (materialID, totalQuantity) in totalRefineryOutputs.sorted(by: { $0.key < $1.key }) {
                let materialName = materialNameMap[materialID] ?? "Unknown Material"
                Logger.info("  - \(materialName) (TypeID: \(materialID)): \(totalQuantity)")
            }
        } else {
            Logger.warning("没有找到任何精炼输出信息")
        }

        // 8. 计算剩余物品
        var remainingItems: [Int: Int64] = [:]
        for (_, oreItem) in oreItems.enumerated() {
            if let item = items.first(where: { $0.id == oreItem.typeID }) {
                let inputQuantity = itemQuantities[item.id] ?? 1

                // 检查是否有精炼产出
                if let typeMaterials = allTypeMaterials[item.id] {
                    let processSize = typeMaterials.first?.process_size ?? 1
                    let remainder = inputQuantity % Int64(processSize)

                    if remainder > 0 {
                        remainingItems[item.id] = remainder
                        Logger.info("剩余物品: \(item.name) (TypeID: \(item.id)): \(remainder)")
                    }
                } else {
                    // 没有精炼产出的物品，全部作为剩余物品
                    remainingItems[item.id] = inputQuantity
                    Logger.info("无精炼产出物品: \(item.name) (TypeID: \(item.id)): \(inputQuantity)")
                }
            }
        }

        // 9. 保存结果数据并显示结果页面
        refineryResultData = RefineryResultData(
            outputs: totalRefineryOutputs,
            materialNames: materialNameMap,
            remaining: remainingItems
        )

        Logger.info("=== 精炼计算完成 ===")
        Logger.info("精炼输出: \(totalRefineryOutputs.count) 种材料")
        Logger.info("剩余物品: \(remainingItems.count) 种物品")

        // 详细记录传递给结果页面的数据
        Logger.info("=== 传递给RefineryResultView的数据 ===")
        Logger.info("refineryResultData.outputs count: \(refineryResultData?.outputs.count ?? 0)")
        Logger.info(
            "refineryResultData.materialNames count: \(refineryResultData?.materialNames.count ?? 0)"
        )
        Logger.info(
            "refineryResultData.remaining count: \(refineryResultData?.remaining.count ?? 0)")

        if let data = refineryResultData {
            for (materialID, quantity) in data.outputs {
                let materialName = data.materialNames[materialID] ?? "Unknown"
                Logger.info("Output: \(materialID) (\(materialName)) -> \(quantity)")
            }

            for (itemID, quantity) in data.remaining {
                Logger.info("Remaining: \(itemID) -> \(quantity)")
            }
        }

        // 显示结果页面
        // showRefineryResult = true  // 不再需要，使用item参数自动显示
    }

    // MARK: - 精炼计算核心逻辑

    // 精炼计算上下文
    struct RefineryContext {
        let structureID: Int
        let rigLevel: StructureRigs
        let systemSecurity: SystemSecurity
        let characterSkills: [Int: Int]
        let structure: Structure
    }

    // 获取当前精炼上下文
    private func getCurrentRefineryContext() -> RefineryContext {
        return RefineryContext(
            structureID: structure.typeID,
            rigLevel: structureRigs,
            systemSecurity: systemSecurity,
            characterSkills: selectedCharacterSkills,
            structure: structure
        )
    }

    // 计算精炼加成系数（核心逻辑，可复用）
    private func calculateRefineryBonus(
        itemID: Int,
        categoryInfo: ItemCategoryInfo,
        context: RefineryContext
    ) -> Double {
        switch categoryInfo.itemType {
        case .oreAndIce:
            return calculateOreRefineryBonus(
                itemID: itemID,
                structureID: context.structureID,
                rigLevel: context.rigLevel,
                systemSecurity: context.systemSecurity,
                characterSkills: context.characterSkills,
                itemCategoryInfo: categoryInfo
            )
        case .gas:
            return calculateGasRefineryBonus(
                structureID: context.structureID,
                characterSkills: context.characterSkills
            )
        case .other:
            return calculateOtherRefineryBonus(
                characterSkills: context.characterSkills
            )
        case .noOutput:
            return 0.0
        }
    }

    // 验证物品是否可以精炼
    private func validateItemForRefinery(itemID: Int, quantity _: Int64) -> (
        typeMaterials: [DatabaseManager.TypeMaterial]?, categoryInfo: ItemCategoryInfo?,
        processSize: Int
    ) {
        // 1. 检查是否有精炼产出
        guard let typeMaterials = databaseManager.getTypeMaterials(for: itemID),
              !typeMaterials.isEmpty
        else {
            return (nil, nil, 0)
        }

        // 2. 获取物品分类信息
        let itemCategories = getBatchItemCategories(for: [itemID])
        guard let categoryInfo = itemCategories[itemID] else {
            return (typeMaterials, nil, 0)
        }

        // 3. 精炼比例与数量无关，只要有精炼产出就可以计算比例
        let processSize = typeMaterials.first?.process_size ?? 0

        return (typeMaterials, categoryInfo, processSize)
    }

    // 更新精炼状态（可复用）
    private func updateRefineryStatus(itemID: Int, status: RefineryStatus) {
        itemRefineryStatus[itemID] = status

        if case let .canRefine(ratio) = status {
            itemRefineryRatios[itemID] = ratio
        } else {
            itemRefineryRatios[itemID] = 0.0
        }
    }

    // 计算单个物品的精炼比例（重构后）
    private func calculateItemRefineryRatio(itemID: Int, quantity: Int64) -> RefineryStatus {
        let validation = validateItemForRefinery(itemID: itemID, quantity: quantity)

        // 检查验证结果
        if validation.typeMaterials == nil {
            return .noOutput
        }

        if validation.categoryInfo == nil {
            return .unknown
        }

        // 精炼比例与数量无关，只要有精炼产出就可以计算比例
        // 计算精炼比例
        let context = getCurrentRefineryContext()
        let refineryRatio = calculateRefineryBonus(
            itemID: itemID,
            categoryInfo: validation.categoryInfo!,
            context: context
        )

        return .canRefine(ratio: refineryRatio)
    }

    // 批量计算物品精炼比例（重构后）
    private func calculateBatchRefineryRatios() {
        for oreItem in oreItems {
            let status = calculateItemRefineryRatio(
                itemID: oreItem.typeID, quantity: oreItem.quantity
            )
            updateRefineryStatus(itemID: oreItem.typeID, status: status)
        }
    }

    // 批量获取多个物品的精炼信息
    private func getBatchTypeMaterials(for typeIDs: [Int]) -> [Int: [DatabaseManager.TypeMaterial]] {
        guard !typeIDs.isEmpty else { return [:] }

        // 构建IN查询的占位符
        let placeholders = String(repeating: "?,", count: typeIDs.count).dropLast()
        let query = """
            SELECT typeid, process_size, output_material, output_quantity, output_material_name, output_material_icon
            FROM typeMaterials
            WHERE typeid IN (\(placeholders))
            ORDER BY typeid, output_material
        """

        var result: [Int: [DatabaseManager.TypeMaterial]] = [:]

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: typeIDs) {
            for row in rows {
                guard let typeID = row["typeid"] as? Int,
                      let processSize = row["process_size"] as? Int,
                      let outputMaterial = row["output_material"] as? Int,
                      let outputQuantity = row["output_quantity"] as? Int,
                      let outputMaterialName = row["output_material_name"] as? String,
                      let outputMaterialIcon = row["output_material_icon"] as? String
                else {
                    continue
                }

                let material = DatabaseManager.TypeMaterial(
                    process_size: processSize,
                    outputMaterial: outputMaterial,
                    outputQuantity: outputQuantity,
                    outputMaterialName: outputMaterialName,
                    outputMaterialIcon: outputMaterialIcon.isEmpty
                        ? DatabaseConfig.defaultItemIcon : outputMaterialIcon
                )

                if result[typeID] == nil {
                    result[typeID] = []
                }
                result[typeID]?.append(material)
            }
        }

        Logger.info("批量查询精炼信息: 查询了 \(typeIDs.count) 个物品，找到 \(result.count) 个物品的精炼数据")
        return result
    }

    // 精炼状态枚举
    enum RefineryStatus {
        case canRefine(ratio: Double) // 可以精炼，显示比例
        case noOutput // 无精炼产出
        case unknown // 未知状态

        var isRefinable: Bool {
            switch self {
            case .canRefine:
                return true
            default:
                return false
            }
        }

        var displayText: String {
            switch self {
            case let .canRefine(ratio):
                return String(format: "%.1f%%", ratio * 100)
            case .noOutput:
                return NSLocalizedString("Ore_Refinery_No_Output", comment: "")
            case .unknown:
                return NSLocalizedString("Ore_Refinery_Unknown", comment: "")
            }
        }
    }

    // 物品分类枚举
    enum RefineryItemType {
        case oreAndIce // 矿石与冰矿
        case gas // 压缩气云
        case other // 其他
        case noOutput // 没有精炼产出的物品

        var description: String {
            switch self {
            case .oreAndIce:
                return "矿石与冰矿"
            case .gas:
                return "压缩气云"
            case .other:
                return "其他"
            case .noOutput:
                return "无精炼产出"
            }
        }
    }

    // 物品分类信息结构
    struct ItemCategoryInfo {
        let typeID: Int
        let categoryID: Int
        let groupID: Int
        let itemType: RefineryItemType
        let reprocessingSkillType: Int? // 矿石和冰矿的专业技能ID
    }

    // 批量获取物品分类信息
    private func getBatchItemCategories(for typeIDs: [Int]) -> [Int: ItemCategoryInfo] {
        guard !typeIDs.isEmpty else { return [:] }

        let placeholders = String(repeating: "?,", count: typeIDs.count).dropLast()
        let query = """
            SELECT type_id, categoryID, groupID
            FROM types
            WHERE type_id IN (\(placeholders))
        """

        var result: [Int: ItemCategoryInfo] = [:]

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: typeIDs) {
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let categoryID = row["categoryID"] as? Int,
                      let groupID = row["groupID"] as? Int
                else {
                    continue
                }

                // 确定物品类型
                let itemType: RefineryItemType
                if categoryID == 25 {
                    itemType = .oreAndIce
                } else if categoryID == 2, groupID == 4168 {
                    itemType = .gas
                } else {
                    itemType = .other
                }

                result[typeID] = ItemCategoryInfo(
                    typeID: typeID,
                    categoryID: categoryID,
                    groupID: groupID,
                    itemType: itemType,
                    reprocessingSkillType: nil // 稍后单独查询
                )
            }
        }

        // 对于矿石和冰矿，查询专业技能类型
        let oreAndIceTypeIDs = result.values.filter { $0.itemType == .oreAndIce }.map { $0.typeID }
        if !oreAndIceTypeIDs.isEmpty {
            let skillPlaceholders = String(repeating: "?,", count: oreAndIceTypeIDs.count)
                .dropLast()
            let skillQuery = """
                SELECT type_id, value
                FROM typeAttributes
                WHERE attribute_id = 790 AND type_id IN (\(skillPlaceholders))
            """

            if case let .success(skillRows) = databaseManager.executeQuery(
                skillQuery, parameters: oreAndIceTypeIDs
            ) {
                for row in skillRows {
                    if let typeID = row["type_id"] as? Int,
                       let skillType = row["value"] as? Double
                    {
                        // 更新现有的ItemCategoryInfo
                        if let existingInfo = result[typeID] {
                            result[typeID] = ItemCategoryInfo(
                                typeID: existingInfo.typeID,
                                categoryID: existingInfo.categoryID,
                                groupID: existingInfo.groupID,
                                itemType: existingInfo.itemType,
                                reprocessingSkillType: Int(skillType)
                            )
                        }
                    }
                }
            }
        }

        Logger.info(
            "批量查询物品分类: 查询了 \(typeIDs.count) 个物品，分类结果: 矿石冰矿 \(result.values.filter { $0.itemType == .oreAndIce }.count) 个, 气云 \(result.values.filter { $0.itemType == .gas }.count) 个, 其他 \(result.values.filter { $0.itemType == .other }.count) 个, 无产出 \(result.values.filter { $0.itemType == .noOutput }.count) 个"
        )
        return result
    }

    // 计算矿石和冰矿的精炼加成系数
    private func calculateOreRefineryBonus(
        itemID: Int,
        structureID: Int,
        rigLevel: StructureRigs,
        systemSecurity: SystemSecurity,
        characterSkills: [Int: Int],
        itemCategoryInfo: ItemCategoryInfo
    ) -> Double {
        // 1. 获取插件基础精炼比例
        let baseRigRatio: Double
        switch rigLevel {
        case .none:
            baseRigRatio = 0.5 // 无插件默认50%
        case .t1:
            baseRigRatio = 0.51 // T1插件51%
        case .t2:
            baseRigRatio = 0.53 // T2插件53%
        }

        // 2. 安全等级加成系数
        let securityBonus: Double
        switch systemSecurity {
        case .highSec:
            securityBonus = 1.0
        case .lowSec:
            securityBonus = 1.06
        case .nullSec:
            securityBonus = 1.12
        }

        // 3. 建筑加成
        let structureBonus = getStructureRefineryBonus(structureID: structureID)

        // 4. 植入体加成
        let implantBonus = getImplantRefineryBonus(implantID: implant.typeID)

        // 5. 通用技能加成 (3389 和 3385)
        let generalSkillBonus = calculateGeneralSkillBonus(characterSkills: characterSkills)

        // 6. 专业技能加成
        let specificSkillBonus = calculateSpecificSkillBonus(
            skillType: itemCategoryInfo.reprocessingSkillType,
            characterSkills: characterSkills
        )

        // 计算总加成系数
        let totalBonus =
            baseRigRatio * securityBonus * structureBonus * implantBonus * generalSkillBonus
                * specificSkillBonus

        Logger.debug("精炼加成计算 - 物品ID: \(itemID)")
        Logger.debug("  插件基础比例: \(baseRigRatio)")
        Logger.debug("  安全等级加成: \(securityBonus)")
        Logger.debug("  建筑加成: \(structureBonus)")
        Logger.debug("  植入体加成: \(implantBonus)")
        Logger.debug("  通用技能加成: \(generalSkillBonus)")
        Logger.debug("  专业技能加成: \(specificSkillBonus)")
        Logger.debug("  总加成系数: \(totalBonus)")

        return totalBonus
    }

    // 获取建筑精炼加成
    private func getStructureRefineryBonus(structureID: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 2722 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [structureID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return 1.0 + (value / 100.0) // 转换为百分比加成
        }

        return 1.0 // 默认无加成
    }

    // 获取植入体精炼加成
    private func getImplantRefineryBonus(implantID: Int) -> Double {
        if implantID == 0 { return 1.0 } // 无植入体

        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 379 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [implantID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return 1.0 + (value / 100.0) // 转换为百分比加成
        }

        return 1.0 // 默认无加成
    }

    // 计算通用技能加成 (3389 和 3385)
    private func calculateGeneralSkillBonus(characterSkills: [Int: Int]) -> Double {
        let skillIDs = [3389, 3385] // 通用精炼技能
        var totalBonus = 1.0

        for skillID in skillIDs {
            let skillLevel = characterSkills[skillID] ?? 0
            let skillBonus = getSkillRefineryBonus(skillID: skillID, skillLevel: skillLevel)
            totalBonus *= skillBonus
        }

        return totalBonus
    }

    // 计算专业技能加成
    private func calculateSpecificSkillBonus(skillType: Int?, characterSkills: [Int: Int]) -> Double {
        guard let skillType = skillType else {
            return 1.0
        }

        let skillLevel = characterSkills[skillType] ?? 0
        return getSkillRefineryBonus(skillID: skillType, skillLevel: skillLevel)
    }

    // 获取技能精炼加成
    private func getSkillRefineryBonus(skillID: Int, skillLevel: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 379 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [skillID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return 1.0 + ((value * Double(skillLevel)) / 100.0) // 技能等级 * 每级加成
        }

        return 1.0 // 默认无加成
    }

    // 计算压缩气云的精炼加成系数
    private func calculateGasRefineryBonus(
        structureID: Int,
        characterSkills: [Int: Int]
    ) -> Double {
        // 1. 基础加成 80%
        let baseBonus = 0.8

        // 2. 技能62452加成
        let skillID = 62452
        let skillLevel = characterSkills[skillID] ?? 0
        let skillBonus = getGasSkillBonus(skillID: skillID, skillLevel: skillLevel)

        // 3. 建筑加成
        let structureBonus = getGasStructureBonus(structureID: structureID)

        // 直接相加：基础加成 + 技能加成 + 建筑加成
        let totalBonus = baseBonus + skillBonus + structureBonus

        Logger.debug("气云精炼加成计算:")
        Logger.debug("  基础加成: \(baseBonus)")
        Logger.debug("  技能加成: \(skillBonus)")
        Logger.debug("  建筑加成: \(structureBonus)")
        Logger.debug("  总加成: \(totalBonus)")

        return totalBonus
    }

    // 获取气云技能加成
    private func getGasSkillBonus(skillID: Int, skillLevel: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 3260 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [skillID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return (value * Double(skillLevel)) / 100.0 // 技能等级 * 每级加成
        }

        return 0.0 // 默认无加成
    }

    // 获取气云建筑加成
    private func getGasStructureBonus(structureID: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 3261 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [structureID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return value // 直接返回加成值（如0.1表示10%）
        }

        return 0.0 // 默认无加成
    }

    // 计算其他物品的精炼加成系数
    private func calculateOtherRefineryBonus(
        characterSkills: [Int: Int]
    ) -> Double {
        // 1. 基础比例 50%
        let baseRatio = 0.5

        // 2. 技能12196加成
        let skillID = 12196
        let skillLevel = characterSkills[skillID] ?? 0
        let skillBonus = getOtherSkillBonus(skillID: skillID, skillLevel: skillLevel)

        // 相乘：基础比例 * 技能加成
        let totalBonus = baseRatio * skillBonus

        Logger.debug("其他物品精炼加成计算:")
        Logger.debug("  基础比例: \(baseRatio)")
        Logger.debug("  技能加成: \(skillBonus)")
        Logger.debug("  总加成: \(totalBonus)")

        return totalBonus
    }

    // 获取其他物品技能加成
    private func getOtherSkillBonus(skillID: Int, skillLevel: Int) -> Double {
        let query = "SELECT value FROM typeAttributes WHERE attribute_id = 379 AND type_id = ?"

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [skillID]),
           let row = rows.first,
           let value = row["value"] as? Double
        {
            return 1.0 + ((value * Double(skillLevel)) / 100.0) // 技能等级 * 每级加成
        }

        return 1.0 // 默认无加成
    }

    // 导出到剪贴板
    private func exportToClipboard() {
        // 构建导出内容：物品名称和数量，以\t分割
        var exportLines: [String] = []

        for oreItem in oreItems {
            // 查找对应的物品信息
            if let item = items.first(where: { $0.id == oreItem.typeID }) {
                let line = "\(item.name)\t\(oreItem.quantity)"
                exportLines.append(line)
            }
        }

        // 将所有行合并为一个字符串，以换行符分隔
        let exportContent = exportLines.joined(separator: "\n")

        // 复制到剪贴板
        UIPasteboard.general.string = exportContent

        // 显示导出结果
        exportResult = String(
            format: NSLocalizedString("Main_Market_Clipboard_Export_Success", comment: ""),
            exportLines.count
        )
        isShowingExportAlert = true

        Logger.success("成功导出 \(exportLines.count) 个物品到剪贴板")
    }
}

// 精炼设置弹窗视图
struct RefinerySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var systemSecurity: OreRefineryCalculatorView.SystemSecurity
    @Binding var structure: OreRefineryCalculatorView.Structure
    @Binding var structureRigs: OreRefineryCalculatorView.StructureRigs
    @Binding var implant: OreRefineryCalculatorView.Implant
    @Binding var taxRate: Double
    @Binding var selectedCharacterSkills: [Int: Int]
    @Binding var selectedCharacterName: String
    @Binding var selectedCharacterId: Int

    @State private var taxRateText: String = ""
    @State private var showCharacterSelector = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // 星系安等选择器
                    Picker(
                        NSLocalizedString("Ore_Refinery_System_Security", comment: ""),
                        selection: $systemSecurity
                    ) {
                        ForEach(OreRefineryCalculatorView.SystemSecurity.allCases, id: \.self) {
                            security in
                            Text(security.localizedName).tag(security)
                        }
                    }
                    .pickerStyle(.menu)

                    // 建筑选择器
                    Picker(
                        NSLocalizedString("Ore_Refinery_Structure", comment: ""),
                        selection: $structure
                    ) {
                        ForEach(OreRefineryCalculatorView.Structure.allCases, id: \.self) {
                            struct_ in
                            Text(struct_.displayName).tag(struct_)
                        }
                    }
                    .pickerStyle(.menu)

                    // 建筑插件选择器
                    Picker(
                        NSLocalizedString("Ore_Refinery_Structure_Rigs", comment: ""),
                        selection: $structureRigs
                    ) {
                        ForEach(OreRefineryCalculatorView.StructureRigs.allCases, id: \.self) {
                            rig in
                            Text(rig.localizedName).tag(rig)
                        }
                    }
                    .pickerStyle(.menu)

                    // 植入体选择器
                    Picker(
                        NSLocalizedString("Ore_Refinery_Implant", comment: ""), selection: $implant
                    ) {
                        ForEach(OreRefineryCalculatorView.Implant.allCases, id: \.self) { implant in
                            Text(implant.displayName).tag(implant)
                        }
                    }
                    .pickerStyle(.menu)

                    // 建筑税率输入
                    HStack {
                        Text(NSLocalizedString("Ore_Refinery_Tax_Rate", comment: ""))
                        Spacer()
                        TextField(
                            NSLocalizedString("Ore_Refinery_Tax_Rate_Placeholder", comment: ""),
                            text: $taxRateText
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("%")
                            .foregroundColor(.secondary)
                    }
                }

                // 技能设置section
                Section(header: Text(NSLocalizedString("Fitting_Setting_Skills", comment: "技能设置"))) {
                    Button {
                        showCharacterSelector = true
                    } label: {
                        HStack {
                            Image("skill")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            Text(NSLocalizedString("Fitting_Skills_Mode", comment: "技能模式"))
                            Spacer()
                            Text(
                                selectedCharacterSkills.isEmpty
                                    ? NSLocalizedString("Fitting_Unknown_Skills", comment: "未知技能模式")
                                    : selectedCharacterName
                            )
                            .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle(NSLocalizedString("Ore_Refinery_Settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "")) {
                        // 保存输入的数值
                        if let newTaxRate = Double(taxRateText) {
                            taxRate = max(0, min(100, newTaxRate))
                            // 保存税率到UserDefaults
                            UserDefaultsManager.shared.refineryTaxRate = taxRate
                        }
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // 初始化文本字段的值，从UserDefaults读取保存的税率
            let savedTaxRate = UserDefaultsManager.shared.refineryTaxRate
            taxRateText = String(savedTaxRate)
            // 同时更新当前税率状态
            taxRate = savedTaxRate

            Logger.info("RefinerySettingsView onAppear - 加载保存的税率: \(savedTaxRate)%")
        }
        .onChange(of: taxRateText) { _, newValue in
            // 实时验证税率输入
            if let value = Double(newValue) {
                if value > 100 {
                    taxRateText = "100"
                } else if value < 0 {
                    taxRateText = "0"
                } else {
                    // 实时保存有效的税率
                    taxRate = value
                    UserDefaultsManager.shared.refineryTaxRate = value
                }
            }
        }

        .sheet(isPresented: $showCharacterSelector) {
            NavigationView {
                CharacterSkillsSelectorView(
                    databaseManager: DatabaseManager.shared,
                    onSelectSkills: { skills, skillModeName, characterId in
                        selectedCharacterSkills = skills
                        selectedCharacterName = skillModeName
                        selectedCharacterId = characterId
                        showCharacterSelector = false
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDragIndicator(.visible)
        }
    }
}
