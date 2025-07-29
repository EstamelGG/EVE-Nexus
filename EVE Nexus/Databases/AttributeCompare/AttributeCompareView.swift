import Foundation
import SwiftUI

// 属性对比列表项目
struct AttributeCompare: Identifiable, Codable {
    let id: UUID
    var name: String
    var items: [AttributeCompareItem]
    var lastUpdated: Date

    init(
        id: UUID = UUID(), name: String, items: [AttributeCompareItem] = []
    ) {
        self.id = id
        self.name = name
        self.items = items
        lastUpdated = Date()
    }
}

struct AttributeCompareItem: Codable, Equatable {
    let typeID: Int

    init(typeID: Int) {
        self.typeID = typeID
    }
}

// 管理属性对比列表的文件存储
class AttributeCompareManager {
    static let shared = AttributeCompareManager()

    private init() {
        createCompareDirectory()
    }

    private var compareDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("AttributeCompares", isDirectory: true)
    }

    private func createCompareDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: compareDirectory, withIntermediateDirectories: true
            )
        } catch {
            Logger.error("创建属性对比列表目录失败: \(error)")
        }
    }

    func saveCompare(_ compare: AttributeCompare) {
        let fileName = "attribute_compare_\(compare.id).json"
        let fileURL = compareDirectory.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
            let data = try encoder.encode(compare)
            try data.write(to: fileURL)
            Logger.debug("保存属性对比列表成功: \(fileName)")
        } catch {
            Logger.error("保存属性对比列表失败: \(error)")
        }
    }

    func loadCompares() -> [AttributeCompare] {
        let fileManager = FileManager.default

        do {
            Logger.debug("开始加载属性对比列表")
            let files = try fileManager.contentsOfDirectory(
                at: compareDirectory, includingPropertiesForKeys: nil
            )
            Logger.debug("找到文件数量: \(files.count)")

            let compares = files.filter { url in
                url.lastPathComponent.hasPrefix("attribute_compare_") && url.pathExtension == "json"
            }.compactMap { url -> AttributeCompare? in
                do {
                    Logger.debug("尝试解析文件: \(url.lastPathComponent)")
                    let data = try Data(contentsOf: url)

                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                    let compare = try decoder.decode(AttributeCompare.self, from: data)
                    return compare
                } catch {
                    Logger.error("读取属性对比列表失败: \(error)")
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
            }
            .sorted { $0.lastUpdated < $1.lastUpdated }

            Logger.debug("成功加载属性对比列表数量: \(compares.count)")
            return compares

        } catch {
            Logger.error("读取属性对比列表目录失败: \(error)")
            return []
        }
    }

    func deleteCompare(_ compare: AttributeCompare) {
        let fileName = "attribute_compare_\(compare.id).json"
        let fileURL = compareDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.removeItem(at: fileURL)
            Logger.debug("删除属性对比列表成功: \(fileName)")
        } catch {
            Logger.error("删除属性对比列表失败: \(error)")
        }
    }
}

// 属性对比物品选择器视图（使用过滤的顶级市场分组）
struct AttributeItemSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showSelected = true
    let allowedTopMarketGroupIDs: Set<Int>
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MarketItemSelectorIntegratedView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Main_Attribute_Compare_Add_Item", comment: ""),
                allowedMarketGroups: allowedTopMarketGroupIDs,
                allowTypeIDs: [],
                existingItems: existingItems,
                onItemSelected: onItemSelected,
                onItemDeselected: onItemDeselected,
                onDismiss: { dismiss() },
                showSelected: showSelected
            )
            .interactiveDismissDisabled()
        }
    }
}

// 属性对比列表主视图
struct AttributeCompareView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var compares: [AttributeCompare] = []
    @State private var isShowingAddAlert = false
    @State private var tempCompareName = ""  // 临时变量，用于接收用户输入
    @State private var searchText = ""

    private var filteredCompares: [AttributeCompare] {
        if searchText.isEmpty {
            return compares
        } else {
            return compares.filter { compare in
                compare.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        return List {
            if filteredCompares.isEmpty {
                if searchText.isEmpty {
                    Text(NSLocalizedString("Main_Attribute_Compare_Empty", comment: ""))
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                } else {
                    Text(String(format: NSLocalizedString("Main_EVE_Mail_No_Results", comment: "")))
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            } else {
                ForEach(filteredCompares) { compare in
                    NavigationLink {
                        AttributeCompareDetailView(
                            databaseManager: databaseManager,
                            compare: compare
                        )
                    } label: {
                        compareRowView(compare)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                .onDelete(perform: deleteCompare)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Attribute_Compare", comment: ""))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    tempCompareName = ""  // 清空临时变量
                    isShowingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(
            NSLocalizedString("Main_Attribute_Compare_Add", comment: ""),
            isPresented: $isShowingAddAlert
        ) {
            TextField(
                NSLocalizedString("Main_Attribute_Compare_Name", comment: ""),
                text: $tempCompareName  // 绑定到临时变量
            )

            Button(NSLocalizedString("Misc_Done", comment: "")) {
                Logger.info("用户新增对比列表: \(tempCompareName)")
                if !tempCompareName.isEmpty {
                    let newCompare = AttributeCompare(
                        name: tempCompareName,  // 使用临时变量的值
                        items: []
                    )
                    compares.append(newCompare)
                    AttributeCompareManager.shared.saveCompare(newCompare)
                    tempCompareName = ""  // 清空临时变量
                }
            }
            .disabled(tempCompareName.isEmpty)  // 根据临时变量判断是否禁用

            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                tempCompareName = ""  // 取消时清空临时变量
            }
        }
        .task {
            compares = AttributeCompareManager.shared.loadCompares()
        }
    }

    private func compareRowView(_ compare: AttributeCompare) -> some View {
        return HStack {
            // 显示列表图标
            if !compare.items.isEmpty, let firstItem = compare.items.first {
                // 直接查询并显示第一个物品的图标
                let icon = getItemIcon(typeID: firstItem.typeID)
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .padding(.trailing, 8)
            } else {
                Image("Folder")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .padding(.trailing, 8)
            }

            Text(compare.name)
                .lineLimit(1)
            Spacer()
            Text(
                String(
                    format: NSLocalizedString("Main_Attribute_Compare_Items", comment: ""),
                    compare.items.count
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // 获取物品图标的辅助函数
    private func getItemIcon(typeID: Int) -> UIImage {
        Logger.info("获取物品图标: \(typeID)")
        let itemData = databaseManager.loadMarketItems(
            whereClause: "t.type_id = ?",
            parameters: [typeID]
        )

        if let item = itemData.first {
            return IconManager.shared.loadUIImage(for: item.iconFileName)
        } else {
            // 如果找不到图标，返回一个默认图标
            return UIImage(named: "not_found") ?? UIImage()
        }
    }

    private func deleteCompare(at offsets: IndexSet) {
        let comparesToDelete = offsets.map { filteredCompares[$0] }
        for compare in comparesToDelete {
            AttributeCompareManager.shared.deleteCompare(compare)
            if let index = compares.firstIndex(where: { $0.id == compare.id }) {
                compares.remove(at: index)
            }
        }
    }
}

// 属性对比列表详情视图
struct AttributeCompareDetailView: View {
    let databaseManager: DatabaseManager
    @State var compare: AttributeCompare
    @State private var isShowingItemSelector = false
    @State private var items: [DatabaseListItem] = []
    @State private var isExpanded: Bool = false
    @State private var compareResult: AttributeCompareUtil.CompareResult?
    @State private var isCalculating: Bool = false
    @State private var marketPrices: [Int: Double] = [:]
    @State private var isLoadingPrices: Bool = false
    @AppStorage("showOnlyDifferences") private var showOnlyDifferences: Bool = false

    // 允许的顶级市场分组ID
    private static let allowedTopMarketGroupIDs: Set<Int> = [4, 9, 157, 11, 2202, 2203, 24, 955]

    init(databaseManager: DatabaseManager, compare: AttributeCompare) {
        self.databaseManager = databaseManager

        // 在初始化时加载数据
        var initialCompare = compare
        var temporaryItems: [DatabaseListItem] = []

        if !compare.items.isEmpty {
            let itemIDs = compare.items.map { String($0.typeID) }.joined(separator: ",")
            let loadedItems = databaseManager.loadMarketItems(
                whereClause: "t.type_id IN (\(itemIDs))",
                parameters: []
            )
            // 按 type_id 排序
            temporaryItems = loadedItems.sorted(by: { $0.id < $1.id })

            // 确保 compare.items 的顺序与加载的物品顺序一致
            if !temporaryItems.isEmpty {
                initialCompare.items = temporaryItems.map { item in
                    AttributeCompareItem(typeID: item.id)
                }
            }
        }

        // 设置初始状态
        self._compare = State(initialValue: initialCompare)
        self._items = State(initialValue: temporaryItems)
    }

    var body: some View {
        List {
            if compare.items.isEmpty {
                Text(NSLocalizedString("Main_Attribute_Compare_Empty", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                // 物品列表部分
                Section {
                    DisclosureGroup(
                        isExpanded: $isExpanded,
                        content: {
                            ForEach(items) { item in
                                NavigationLink {
                                    MarketItemDetailView(
                                        databaseManager: databaseManager,
                                        itemID: item.id
                                    )
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(
                                            uiImage: IconManager.shared.loadUIImage(
                                                for: item.iconFileName)
                                        )
                                        .resizable()
                                        .frame(width: 36, height: 36)
                                        .cornerRadius(6)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .lineLimit(1)

                                            Text(item.groupName ?? "")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            // .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                            .onDelete { indexSet in
                                let itemsToDelete = indexSet.map { items[$0].id }
                                compare.items.removeAll { itemsToDelete.contains($0.typeID) }
                                items.remove(atOffsets: indexSet)
                                AttributeCompareManager.shared.saveCompare(compare)

                                // 删除物品后，如果还有至少两个物品，重新计算对比结果
                                if items.count >= 2 {
                                    calculateCompare()
                                } else {
                                    // 如果物品少于2个，清空对比结果和市场价格
                                    compareResult = nil
                                    marketPrices = [:]
                                }
                            }
                        },
                        label: {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Main_Attribute_Compare_Items", comment: ""),
                                    compare.items.count
                                )
                            )
                        }
                    )

                    // 在物品列表下方添加"只展示有差异的属性"开关
                    if items.count >= 2 {
                        Toggle(
                            NSLocalizedString(
                                "Main_Attribute_Compare_Show_Only_Differences", comment: ""),
                            isOn: $showOnlyDifferences
                        )
                        .onChange(of: showOnlyDifferences) { _, _ in
                            // 切换时不需要重新计算，只需要更新显示
                            UserDefaults.standard.set(
                                showOnlyDifferences, forKey: "showOnlyDifferences")
                        }
                        .padding(.top, 4)
                    }
                } header: {
                    Text(NSLocalizedString("Main_Attribute_Compare_Item_List", comment: ""))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                }

                // 市场价格部分 - 只在超过2个物品时显示
                if items.count >= 2 {
                    Section {
                        if isLoadingPrices {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                        } else {
                            ForEach(items) { item in
                                HStack {
                                    // 物品图标
                                    Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(4)

                                    // 物品名称
                                    Text(item.name)
                                        .font(.body)

                                    Spacer()

                                    // 市场价格
                                    if let price = marketPrices[item.id] {
                                        Text(FormatUtil.formatISK(price))
                                            .font(.body)
                                            .foregroundColor(getPriceColor(for: item))
                                    } else {
                                        Text("N/A")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Image("isk")
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(6)
                            
                            Text(NSLocalizedString("Main_Market_Price_Jita", comment: "Jita 市场价格"))
                                .font(.headline)
                        }
                    }
                }

                // 计算中指示器
                if isCalculating {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    } header: {
                        Text(NSLocalizedString("Misc_Calculating", comment: ""))
                    }
                }

                // 对比结果部分 - 显示每个属性的对比
                if let result = compareResult, items.count >= 2 {
                    // 合并已发布和未发布的属性
                    let allAttributes = result.publishedAttributeInfo
                    //                     let allAttributes = result.publishedAttributeInfo.merging(
                    //                         result.unpublishedAttributeInfo
                    //                     ) { (published, _) in published }

                    // 获取所有属性ID，并按数字大小排序
                    let sortedAttributeIDs = allAttributes.keys.sorted {
                        (Int($0) ?? 0) < (Int($1) ?? 0)
                    }

                    // 过滤出要显示的属性
                    let attributesToShow =
                        showOnlyDifferences
                        ? getAttributesWithDifferences(result) : sortedAttributeIDs

                    // 过滤并按属性ID排序显示属性
                    let filteredAttributes = sortedAttributeIDs.filter {
                        attributesToShow.contains($0)
                    }

                    // 每个属性单独一个Section
                    ForEach(filteredAttributes, id: \.self) { attributeID in
                        if let attributeValues = result.compareResult[attributeID],
                            let attributeName = allAttributes[attributeID]
                        {

                            AttributeCompareSection(
                                attributeName: attributeName,
                                attributeID: attributeID,
                                values: attributeValues,
                                typeInfo: result.typeInfo,
                                items: items,
                                attributeIcons: result.attributeIcons,
                                highIsGood: result.attributeHighIsGood[attributeID] ?? true
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle(compare.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    isShowingItemSelector = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingItemSelector) {
            AttributeItemSelectorView(
                databaseManager: databaseManager,
                allowedTopMarketGroupIDs: AttributeCompareDetailView.allowedTopMarketGroupIDs,
                existingItems: Set(compare.items.map { $0.typeID }),
                onItemSelected: { item in
                    if !compare.items.contains(where: { $0.typeID == item.id }) {
                        items.append(item)
                        compare.items.append(AttributeCompareItem(typeID: item.id))
                        // 重新排序并保存
                        let sorted = items.sorted(by: { $0.id < $1.id })
                        items = sorted
                        compare.items = sorted.map { item in
                            AttributeCompareItem(typeID: item.id)
                        }
                        AttributeCompareManager.shared.saveCompare(compare)

                        // 添加新物品后，如果有至少两个物品，计算属性对比
                        if items.count >= 2 {
                            calculateCompare()
                        }
                    }
                },
                onItemDeselected: { item in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items.remove(at: index)
                        compare.items.removeAll { $0.typeID == item.id }
                        AttributeCompareManager.shared.saveCompare(compare)

                        // 删除物品后，如果还有至少两个物品，重新计算对比结果
                        if items.count >= 2 {
                            calculateCompare()
                        } else {
                            // 如果物品少于2个，清空对比结果和市场价格
                            compareResult = nil
                            marketPrices = [:]
                        }
                    }
                }
            )
        }
        .onAppear {
            // 视图出现时，如果有至少两个物品，自动计算属性对比
            if items.count >= 2 {
                calculateCompare()
            }
        }
    }

    // 获取属性对比中有差异的属性
    private func getAttributesWithDifferences(_ result: AttributeCompareUtil.CompareResult)
        -> [String]
    {
        var attributesWithDifferences: [String] = []

        // 物品总数
        let totalItemCount = items.count

        for (attributeID, values) in result.compareResult {
            // 如果不是所有物品都有这个属性，则视为有差异
            if values.count != totalItemCount {
                attributesWithDifferences.append(attributeID)
                continue
            }

            // 检查是否所有值都相同
            var allSame = true
            let firstValue = values.values.first?.value

            for (_, info) in values {
                if info.value != firstValue {
                    allSame = false
                    break
                }
            }

            // 只有存在差异的属性才加入结果
            if !allSame {
                attributesWithDifferences.append(attributeID)
            }
        }

        // 返回按属性ID排序的结果
        return attributesWithDifferences.sorted { Int($0) ?? 0 < Int($1) ?? 0 }
    }

    // 获取市场价格颜色
    private func getPriceColor(for item: DatabaseListItem) -> Color {
        // 如果该物品没有价格信息，返回默认颜色
        guard let currentPrice = marketPrices[item.id] else {
            return .secondary
        }
        
        // 获取所有有效价格
        let allPrices = marketPrices.values.filter { $0 > 0 }
        
        // 如果价格数量少于2个，不标颜色
        if allPrices.count < 2 {
            return .secondary
        }
        
        // 找到最高价和最低价
        let maxPrice = allPrices.max() ?? currentPrice
        let minPrice = allPrices.min() ?? currentPrice
        
        // 如果最高价和最低价相同，说明所有价格都一样，不标颜色
        if maxPrice == minPrice {
            return .secondary
        }
        
        // 根据价格判断颜色：最贵标橙色，最便宜标绿色
        if currentPrice == maxPrice {
            return .green  // 最贵的
        } else if currentPrice == minPrice {
            return .orange   // 最便宜的
        } else {
            return .secondary
        }
    }

    // 获取市场价格
    private func loadMarketPrices() {
        if items.count < 2 {
            Logger.info("需要至少两个物品才能获取市场价格")
            return
        }

        let typeIDs = items.map { $0.id }
        isLoadingPrices = true

        Task {
            do {
                Logger.info("开始获取市场价格，物品数量: \(typeIDs.count)")
                let prices = await MarketPriceUtil.getMarketOrderPrices(typeIds: typeIDs)
                
                await MainActor.run {
                    self.marketPrices = prices
                    self.isLoadingPrices = false
                    Logger.info("市场价格获取完成，获得价格数量: \(prices.count)")
                }
            }
        }
    }

    // 计算属性对比
    private func calculateCompare() {
        if items.count < 2 {
            Logger.info("需要至少两个物品才能进行对比")
            return
        }

        // 获取所有物品的typeID
        let typeIDs = items.map { $0.id }

        isCalculating = true

        // 同时获取市场价格
        loadMarketPrices()

        // 使用后台线程进行计算
        DispatchQueue.global(qos: .userInitiated).async {
            // 使用静态工具方法获取对比结果
            let result = AttributeCompareUtil.compareAttributesWithResult(
                typeIDs: typeIDs, databaseManager: databaseManager)

            // 回到主线程更新UI
            DispatchQueue.main.async {
                self.compareResult = result
                self.isCalculating = false
            }
        }
    }
}

// 单个属性对比的Section
struct AttributeCompareSection: View {
    let attributeName: String
    let attributeID: String
    let values: [String: AttributeCompareUtil.AttributeValueInfo]
    let typeInfo: [String: String]
    let items: [DatabaseListItem]
    let attributeIcons: [String: String]
    let highIsGood: Bool

    var body: some View {
        // 使用包含图标的自定义标题作为Section header
        Section {
            ForEach(items) { item in
                let typeIDString = String(item.id)
                HStack {
                    // 物品图标
                    Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(4)

                    // 物品名称
                    Text(item.name)
                        .font(.body)

                    Spacer()

                    // 属性值和单位 - 如果没有此属性，显示N/A
                    if let valueInfo = values[typeIDString] {
                        Text(getFormattedValue(valueInfo))
                            .font(.body)
                            .foregroundColor(getValueColor(for: item))
                    } else {
                        Text("N/A")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            // 使用包含图标的自定义标题
            HStack {
                // 如果有图标则显示图标
                if let iconFileName = attributeIcons[attributeID] {
                    IconManager.shared.loadImage(for: iconFileName)
                        .resizable()
                        .frame(width: 24, height: 24)
                }

                Text(attributeName)
                    .font(.headline)
            }
        }
    }

    // 格式化属性值和单位
    private func getFormattedValue(_ valueInfo: AttributeCompareUtil.AttributeValueInfo) -> String {
        // 使用新的AttributeValueFormatter格式化属性值
        return AttributeValueFormatter.format(
            value: valueInfo.value,
            unitID: valueInfo.unitID,
            attributeID: Int(attributeID)
        )
    }

    // 计算每个物品的颜色
    private func getValueColor(for item: DatabaseListItem) -> Color {
        let typeIDString = String(item.id)
        
        // 如果该物品没有这个属性值，返回默认颜色
        guard let currentValueInfo = values[typeIDString] else {
            return .secondary
        }
        
        // 获取所有存在的属性值
        let existingValues = values.values.map { $0.value }
        
        // 如果只有一个物品有这个属性，不标颜色
        if existingValues.count <= 1 {
            return .secondary
        }
        
        let currentValue = currentValueInfo.value
        
        // 根据highIsGood确定最好和最差的值
        let bestValue: Double
        let worstValue: Double
        
        if highIsGood {
            // 数值越大越好
            bestValue = existingValues.max() ?? currentValue
            worstValue = existingValues.min() ?? currentValue
        } else {
            // 数值越小越好
            bestValue = existingValues.min() ?? currentValue
            worstValue = existingValues.max() ?? currentValue
        }
        
        // 如果最好和最差的值相同，说明所有值都一样，不标颜色
        if bestValue == worstValue {
            return .secondary
        }
        
        // 根据当前值判断颜色
        if currentValue == bestValue {
            return .green
        } else if currentValue == worstValue {
            return .orange
        } else {
            return .secondary
        }
    }
}

// 修改AttributeCompareUtil，添加返回结果的方法
extension AttributeCompareUtil {
    // 获取多个物品的属性对比数据，并返回结果
    static func compareAttributesWithResult(typeIDs: [Int], databaseManager: DatabaseManager)
        -> CompareResult?
    {
        // 如果物品数量少于2个，不进行对比
        if typeIDs.count < 2 {
            Logger.info("需要至少两个物品才能进行对比")
            return nil
        }

        // 去重处理
        let uniqueTypeIDs = Array(Set(typeIDs))

        if uniqueTypeIDs.count < 2 {
            Logger.info("去重后物品数量少于2个，无法进行对比")
            return nil
        }

        Logger.info("开始属性对比，物品ID: \(uniqueTypeIDs)")

        // 首先加载属性单位信息并初始化AttributeDisplayConfig
        let attributeUnits = databaseManager.loadAttributeUnits()
        AttributeDisplayConfig.initializeUnits(with: attributeUnits)
        Logger.info("加载了 \(attributeUnits.count) 个属性单位")

        // 构建SQL查询条件
        let typeIDsString = uniqueTypeIDs.map { String($0) }.joined(separator: ",")

        // 查询SQL - 获取属性值和单位信息
        let query = """
                SELECT
                    ta.type_id,
                    ta.attribute_id,
                    a.display_name,
                    a.name,
                    ta.value,
                    COALESCE(ta.unitID, a.unitID) as unitID,
                    a.unitName,
                    a.iconID,
                    COALESCE(a.icon_filename, '') as icon_filename,
                    a.highIsGood
                FROM
                    typeAttributes ta
                LEFT JOIN
                    dogmaAttributes a ON ta.attribute_id = a.attribute_id
                WHERE
                    ta.type_id IN (\(typeIDsString))
                ORDER BY 
                    ta.attribute_id
            """

        // 执行查询
        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            Logger.error("获取物品属性对比数据失败")
            return nil
        }

        Logger.info("查询到 \(rows.count) 行原始数据")

        // 初始化结果字典 - 格式: [attributeID: [typeID: {value, unitID}]]
        var attributeValues: [String: [String: AttributeValueInfo]] = [:]

        // 存储属性图标信息
        var attributeIcons: [String: String] = [:]

        // 存储属性的highIsGood信息
        var attributeHighIsGood: [String: Bool] = [:]

        // 处理查询结果
        for row in rows {
            guard let typeID = row["type_id"] as? Int,
                let attributeID = row["attribute_id"] as? Int,
                let value = row["value"] as? Double
            else {
                continue
            }

            let unitID = row["unitID"] as? Int
            let displayName = row["display_name"] as? String
            // let name = row["name"] as? String
            let iconID = row["iconID"] as? Int
            let iconFileName = (row["icon_filename"] as? String) ?? ""
            let highIsGood = (row["highIsGood"] as? Int) == 1

            // 属性名称处理
            let attributeName = displayName ?? "Unknown Attribute"
            // let attributeName = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? name ?? "未知属性"

            let attributeIDString = String(attributeID)
            let typeIDString = String(typeID)

            // 如果该属性ID还没有在结果字典中，添加它
            if attributeValues[attributeIDString] == nil {
                attributeValues[attributeIDString] = [:]
            }

            // 添加当前物品的属性值信息
            attributeValues[attributeIDString]?[typeIDString] = AttributeValueInfo(
                value: value, unitID: unitID)

            // 保存属性图标信息（只需保存一次）
            if !attributeIcons.keys.contains(attributeIDString) && iconID != nil && iconID != 0 {
                let finalIconFileName =
                    iconFileName.isEmpty ? DatabaseConfig.defaultIcon : iconFileName
                attributeIcons[attributeIDString] = finalIconFileName
            }

            // 保存属性的highIsGood信息（只需保存一次）
            if !attributeHighIsGood.keys.contains(attributeIDString) {
                attributeHighIsGood[attributeIDString] = highIsGood
            }

            // 此处可以添加属性名称到日志，用于调试
            Logger.debug(
                "处理属性: \(attributeIDString) (\(attributeName)), 物品ID: \(typeIDString), 值: \(value)")
        }

        // 查询 types 表中的额外属性值 - mass(4), capacity(38), volume(161)
        let typesQuery = """
                SELECT 
                    type_id, 
                    name,
                    volume,
                    capacity,
                    mass
                FROM 
                    types
                WHERE 
                    type_id IN (\(typeIDsString))
            """

        var typeInfo: [String: String] = [:]
        
        // 定义 types 表属性的真实属性ID映射
        let typesAttributeMapping = [
            (161, "volume"),    // 体积
            (38, "capacity"),   // 容量  
            (4, "mass")         // 质量
        ]
        
        if case let .success(typeRows) = databaseManager.executeQuery(typesQuery) {
            for row in typeRows {
                guard let typeID = row["type_id"] as? Int,
                    let name = row["name"] as? String
                else {
                    continue
                }

                typeInfo[String(typeID)] = name
                
                // 处理 types 表中的属性值，使用真实的属性ID
                for (realAttributeID, columnName) in typesAttributeMapping {
                    if let value = row[columnName] as? Double {
                        let attributeIDString = String(realAttributeID)
                        let typeIDString = String(typeID)
                        
                        // 如果该属性ID还没有在结果字典中，添加它
                        if attributeValues[attributeIDString] == nil {
                            attributeValues[attributeIDString] = [:]
                        }
                        
                        // 添加当前物品的属性值信息，单位ID先设为nil，后面从dogmaAttributes获取
                        attributeValues[attributeIDString]?[typeIDString] = AttributeValueInfo(
                            value: value, unitID: nil)
                        
                        Logger.debug("添加 types 属性: \(attributeIDString) (\(columnName)), 物品ID: \(typeIDString), 值: \(value)")
                    }
                }
            }
        }

        // 获取属性信息并区分已发布和未发布
        let attributeIDs = Array(attributeValues.keys).compactMap { Int($0) }
        let attributeIDsString = attributeIDs.map { String($0) }.joined(separator: ",")

        let attributeQuery = """
                SELECT 
                    attribute_id, 
                    display_name,
                    name,
                    highIsGood,
                    COALESCE(unitID, 0) as unitID,
                    iconID,
                    COALESCE(icon_filename, '') as icon_filename
                FROM 
                    dogmaAttributes
                WHERE 
                    attribute_id IN (\(attributeIDsString))
                AND unitID NOT IN (115, 116, 119)  -- typeid类的属性值不看
            """

        // 已发布属性信息 (有display_name的)
        var publishedAttributeInfo: [String: String] = [:]

        if case let .success(attributeRows) = databaseManager.executeQuery(attributeQuery) {
            for row in attributeRows {
                guard let attributeID = row["attribute_id"] as? Int else {
                    continue
                }

                let displayName = row["display_name"] as? String
                let attributeIDString = String(attributeID)
                let unitID = row["unitID"] as? Int
                let iconID = row["iconID"] as? Int
                let iconFileName = (row["icon_filename"] as? String) ?? ""
                let highIsGood = (row["highIsGood"] as? Int) == 1

                if let displayName = displayName, !displayName.isEmpty {
                    // 有display_name的属性放入已发布列表
                    publishedAttributeInfo[attributeIDString] = displayName
                }

                // 更新 types 表属性的单位ID
                if let attributeTypeValues = attributeValues[attributeIDString] {
                    var updatedValues: [String: AttributeValueInfo] = [:]
                    for (typeIDString, valueInfo) in attributeTypeValues {
                        updatedValues[typeIDString] = AttributeValueInfo(
                            value: valueInfo.value,
                            unitID: unitID
                        )
                    }
                    attributeValues[attributeIDString] = updatedValues
                }

                // 保存属性图标信息（只需保存一次）
                if !attributeIcons.keys.contains(attributeIDString) && iconID != nil && iconID != 0 {
                    let finalIconFileName =
                        iconFileName.isEmpty ? DatabaseConfig.defaultIcon : iconFileName
                    attributeIcons[attributeIDString] = finalIconFileName
                }

                // 保存属性的highIsGood信息（只需保存一次）
                if !attributeHighIsGood.keys.contains(attributeIDString) {
                    attributeHighIsGood[attributeIDString] = highIsGood
                }
            }
        }

        // 构建符合Codable的结果对象
        let result = CompareResult(
            compareResult: attributeValues,
            typeInfo: typeInfo,
            publishedAttributeInfo: publishedAttributeInfo,
            // unpublishedAttributeInfo: unpublishedAttributeInfo,
            attributeIcons: attributeIcons,
            attributeHighIsGood: attributeHighIsGood
        )

        // 使用JSONEncoder直接序列化Codable对象
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(result)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Logger.info("属性对比结果JSON:\n\(jsonString)")
            }
        } catch {
            Logger.error("无法将结果转换为JSON: \(error)")
        }

        return result
    }
}
