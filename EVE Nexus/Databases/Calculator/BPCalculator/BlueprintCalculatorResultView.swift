import SwiftUI
import Foundation

struct BlueprintCalculatorResultView: View {
    let databaseManager: DatabaseManager
    let calculationResult: BlueprintCalcUtil.BlueprintCalcResult
    let blueprintInfo: DatabaseListItem
    let runs: Int
    
    // 用于传递给子蓝图计算器的参数
    let originalStructure: IndustryFacilityInfo?
    let originalSystemId: Int?
    let originalFacilityTax: Double
    let originalCharacterSkills: [Int: Int]
    let originalCharacterName: String
    let originalCharacterId: Int
    
    init(
        databaseManager: DatabaseManager,
        calculationResult: BlueprintCalcUtil.BlueprintCalcResult,
        blueprintInfo: DatabaseListItem,
        runs: Int,
        originalStructure: IndustryFacilityInfo? = nil,
        originalSystemId: Int? = nil,
        originalFacilityTax: Double = 1.0,
        originalCharacterSkills: [Int: Int] = [:],
        originalCharacterName: String = "",
        originalCharacterId: Int = 0
    ) {
        self.databaseManager = databaseManager
        self.calculationResult = calculationResult
        self.blueprintInfo = blueprintInfo
        self.runs = runs
        self.originalStructure = originalStructure
        self.originalSystemId = originalSystemId
        self.originalFacilityTax = originalFacilityTax
        self.originalCharacterSkills = originalCharacterSkills
        self.originalCharacterName = originalCharacterName
        self.originalCharacterId = originalCharacterId
    }
    
    @State private var selectedRegionID: Int = 10_000_002  // 默认 The Forge
    @State private var selectedRegionName: String = ""
    @State private var showRegionPicker = false
    @State private var saveSelection = false  // 不保存默认市场位置
    @State private var orderType: OrderType = .sell
    @State private var regions: [(id: Int, name: String)] = []
    @State private var marketOrders: [Int: [MarketOrder]] = [:]
    @State private var isLoadingOrders = false
    @State private var hasLoadedOrders = false
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil
    @State private var itemVolumes: [Int: Double] = [:]
    @State private var considerOrderQuantity = true  // 是否考虑订单数量，默认选中
    
    // 产品市场设置
    @State private var productSelectedRegionID: Int = 10_000_002  // 默认 The Forge
    @State private var productSelectedRegionName: String = ""
    @State private var showProductRegionPicker = false
    @State private var productOrderType: OrderType = .sell
    @State private var productMarketOrders: [MarketOrder] = []
    @State private var isLoadingProductOrders = false
    @State private var productOrdersProgress: StructureOrdersProgress? = nil
    
    // 材料源蓝图信息
    @State private var materialBlueprintMapping: [Int: [Int]] = [:]
    @State private var blueprintInfos: [Int: (name: String, iconFileName: String)] = [:]
    
    // 导航相关
    @State private var showNewBlueprintCalculator = false
    @State private var newBlueprintInitParams: BlueprintCalculatorInitParams? = nil
    
    // 复制相关
    @State private var showingCopyAlert = false
    
    // 订单类型枚举
    private enum OrderType: String, CaseIterable {
        case buy = "Main_Market_Order_Buy"
        case sell = "Main_Market_Order_Sell"
        
        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }
    
    var body: some View {
        List {
            // 第一个section：蓝图信息
            Section {
                // 第一行：蓝图图标、名称和流程数
                HStack(spacing: 12) {
                    IconManager.shared.loadImage(for: blueprintInfo.iconFileName)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(6)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(blueprintInfo.name)
                            .font(.headline)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            // 星系信息
                            if let systemId = originalSystemId {
                                let systemInfo = getSystemInfo(systemId: systemId, databaseManager: databaseManager)
                                if let systemName = systemInfo.name, let security = systemInfo.security {
                                    HStack(spacing: 4) {
                                        Text(formatSystemSecurity(security))
                                            .foregroundColor(getSecurityColor(security))
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.medium)
                                        
                                        Text(systemName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Text("·")
                            Text(String(format: NSLocalizedString("Blueprint_Calculator_Runs_Count", comment: "流程数: %d"), runs))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                
                // 第二行：加工所需时间
                HStack {
                    Text(NSLocalizedString("Blueprint_Calculator_Production_Time", comment: "加工时间"))
                    Spacer()
                    Text(formatTime(calculationResult.timeRequirement.finalTime))
                        .foregroundColor(.secondary)
                }
                
                // 第三行：预期手续费
                HStack {
                    Text(NSLocalizedString("Blueprint_Calculator_Facility_Cost", comment: "手续费"))
                    Spacer()
                    Text(FormatUtil.formatISK(calculationResult.facilityCost))
                        .foregroundColor(.secondary)
                }
                
                // 第四行：利润估算
                HStack {
                    Text(NSLocalizedString("Blueprint_Calculator_Profit_Estimation", comment: "利润估算"))
                    Spacer()
                    let profitInfo = calculateProfit()
                    if let profit = profitInfo.profit, let profitMargin = profitInfo.profitMargin {
                        Text(String(format: "%@(%.1f%%)", FormatUtil.formatISK(profit), profitMargin * 100))
                            .foregroundColor(getProfitColor(profit: profit, profitMargin: profitMargin))
                    } else {
                        Text(NSLocalizedString("Main_Market_No_Orders", comment: "无订单"))
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text(NSLocalizedString("Blueprint_Calculator_Production_Info", comment: "生产信息"))
                    .fontWeight(.semibold)
                    .font(.system(size: 18))
                    .foregroundColor(.primary)
                    .textCase(.none)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            
            // 第二个section：产出
            if let product = calculationResult.product {
                Section {
                    // 第一行：产品图标、名称和数量（可点击跳转）
                    NavigationLink {
                        MarketItemDetailView(
                            databaseManager: databaseManager,
                            itemID: product.typeId,
                            selectedRegionID: productSelectedRegionID
                        )
                    } label: {
                        HStack(spacing: 12) {
                            IconManager.shared.loadImage(for: product.typeIcon)
                                .resizable()
                                .frame(width: 40, height: 40)
                                .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.typeName)
                                    .font(.headline)
                                    .lineLimit(1)
                                
                                if isLoadingProductOrders {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                        Text(NSLocalizedString("Main_Database_Loading", comment: "加载中..."))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    let productPriceInfo = getProductPrice()
                                    if let price = productPriceInfo.price {
                                        HStack(spacing: 4) {
                                            Text(String(format: NSLocalizedString("Main_Market_Unit_Price", comment: "单价: %@"), FormatUtil.formatISK(price)))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            
                                            if productPriceInfo.insufficientStock {
                                                Text(NSLocalizedString("Main_Market_Insufficient_Stock", comment: "库存不足"))
                                                    .font(.caption)
                                                    .foregroundColor(.red)
                                            }
                                        }
                                    } else {
                                        Text(NSLocalizedString("Main_Market_No_Orders", comment: "无订单"))
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Text(formatQuantity(product.totalQuantity))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // 第二行：产品市场选择
                    HStack {
                        Text(NSLocalizedString("Blueprint_Calculator_Product_Market", comment: "产品市场"))
                        Spacer()
                        Button {
                            showProductRegionPicker = true
                        } label: {
                            HStack {
                                Text(productSelectedRegionName.isEmpty ? NSLocalizedString("Main_Market_Select_Location", comment: "选择位置") : productSelectedRegionName)
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
                    
                    // 第三行：产品订单类型选择器
                    HStack {
                        Text(NSLocalizedString("Main_Market_Order_Type", comment: "订单类型"))
                        Spacer()
                        Picker("", selection: $productOrderType) {
                            Text(OrderType.sell.localizedName).tag(OrderType.sell)
                            Text(OrderType.buy.localizedName).tag(OrderType.buy)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }
                    
                    // 第四行：产品总价
                    HStack {
                        Text(NSLocalizedString("Main_Market_Price", comment: "价格"))
                        Spacer()
                        if isLoadingProductOrders {
                            if StructureMarketManager.isStructureId(productSelectedRegionID),
                               let progress = productOrdersProgress {
                                switch progress {
                                case .loading(let currentPage, let totalPages):
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
                            let productPriceInfo = getProductPrice()
                            if let price = productPriceInfo.price {
                                let totalPrice = price * Double(product.totalQuantity)
                                Text(FormatUtil.formatISK(totalPrice))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(NSLocalizedString("Main_Market_No_Orders", comment: "无订单"))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 第五行：产品总体积
                    HStack {
                        Text(NSLocalizedString("Total_volume", comment: "总体积"))
                        Spacer()
                        let productVolume = getProductVolume()
                        Text("\(FormatUtil.formatForUI(productVolume, maxFractionDigits: 2)) m³")
                            .foregroundColor(.secondary)
                    }
                    

                } header: {
                    Text(NSLocalizedString("Blueprint_Calculator_Product_Output", comment: "产出"))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
            
            // 第三个section：材料市场设置
            Section {
                // 第一行：市场选择器
                HStack {
                    Text(NSLocalizedString("Blueprint_Calculator_Material_Market", comment: "市场位置"))
                    Spacer()
                    Button {
                        showRegionPicker = true
                    } label: {
                        HStack {
                            Text(selectedRegionName.isEmpty ? NSLocalizedString("Main_Market_Select_Location", comment: "选择位置") : selectedRegionName)
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
                
                // 第二行：订单类型选择器
                HStack {
                    Text(NSLocalizedString("Main_Market_Order_Type", comment: "订单类型"))
                    Spacer()
                    Picker("", selection: $orderType) {
                        Text(OrderType.sell.localizedName).tag(OrderType.sell)
                        Text(OrderType.buy.localizedName).tag(OrderType.buy)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                
                // 第三行：总价格
                HStack {
                    Text(NSLocalizedString("Main_Market_Price", comment: "价格"))
                    Spacer()
                    if isLoadingOrders {
                        if StructureMarketManager.isStructureId(selectedRegionID),
                           let progress = structureOrdersProgress {
                            switch progress {
                            case .loading(let currentPage, let totalPages):
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
                            Text(FormatUtil.formatISK(priceInfo.total))
                                .foregroundColor(priceInfo.hasInsufficientStock ? .red : .secondary)
                        } else {
                            Text(NSLocalizedString("Main_Market_No_Orders", comment: "无订单"))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // 第四行：总体积
                HStack {
                    Text(NSLocalizedString("Total_volume", comment: "总体积"))
                    Spacer()
                    let totalVolume = calculateTotalVolume()
                    Text("\(FormatUtil.formatForUI(totalVolume, maxFractionDigits: 2)) m³")
                        .foregroundColor(.secondary)
                }
                            } header: {
                    HStack {
                        Text(NSLocalizedString("Blueprint_Calculator_Material_Market_Settings", comment: "材料市场设置"))
                            .fontWeight(.semibold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(.none)
                        
                        Spacer()
                        
                        Button {
                            considerOrderQuantity.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: considerOrderQuantity ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(considerOrderQuantity ? .blue : .secondary)
                                Text(NSLocalizedString("Blueprint_Calculator_Consider_Quantity", comment: "考虑订单数量"))
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            
            // 第三个section：材料需求列表
            Section {
                ForEach(calculationResult.materials, id: \.typeId) { material in
                    materialRow(material)
                }
            } header: {
                HStack {
                    Text(NSLocalizedString("Blueprint_Calculator_Materials_Required", comment: "所需材料"))
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    
                    Spacer()
                    
                    // 默认复制中文版按钮
                    Button(action: {
                        copyMaterialsToClipboard(useEnglishNames: false)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                            Text(NSLocalizedString("Blueprint_Copy_Materials", comment: ""))
                                .font(.system(size: 14))
                        }
                    }
                    .buttonStyle(.borderless)
                    
                    // 如果有不同的英文名称，显示复制英文版按钮
                    if hasDifferentEnglishNames() {
                        Button(action: {
                            copyMaterialsToClipboard(useEnglishNames: true)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 14))
                                Text(NSLocalizedString("Blueprint_Copy_Materials_EN", comment: ""))
                                    .font(.system(size: 14))
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
        }
        .navigationTitle(NSLocalizedString("Blueprint_Calculator_Result", comment: "计算结果"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await loadAllMarketOrders(forceRefresh: true)
            await loadProductMarketOrders(forceRefresh: true)
        }
        .sheet(isPresented: $showRegionPicker) {
            MarketRegionPickerView(
                selectedRegionID: $selectedRegionID,
                selectedRegionName: $selectedRegionName,
                saveSelection: $saveSelection,
                databaseManager: databaseManager
            )
        }
        .sheet(isPresented: $showProductRegionPicker) {
            MarketRegionPickerView(
                selectedRegionID: $productSelectedRegionID,
                selectedRegionName: $productSelectedRegionName,
                saveSelection: $saveSelection,
                databaseManager: databaseManager
            )
        }
        .onChange(of: selectedRegionID) { oldValue, newValue in
            if oldValue != newValue {
                updateRegionName()
                Task {
                    await loadAllMarketOrders()
                }
            }
        }
        .onChange(of: orderType) { _, _ in
            // 订单类型改变时不需要重新加载，只需要重新计算价格
        }
        .onChange(of: productSelectedRegionID) { oldValue, newValue in
            if oldValue != newValue {
                updateProductRegionName()
                Task {
                    await loadProductMarketOrders()
                }
            }
        }
        .task {
            loadRegions()
            updateRegionName()
            updateProductRegionName()
            loadItemVolumes()
            loadMaterialBlueprints()
            if !hasLoadedOrders {
                await loadAllMarketOrders()
                await loadProductMarketOrders()
                hasLoadedOrders = true
            }
        }
        .navigationDestination(isPresented: $showNewBlueprintCalculator) {
            if let initParams = newBlueprintInitParams {
                BlueprintCalculatorView(initParams: initParams)
            }
        }
        .alert(NSLocalizedString("Blueprint_Copy_Success", comment: "材料已复制"), isPresented: $showingCopyAlert) {
            Button("OK", role: .cancel) { }
        }
    }
    
    // MARK: - 私有方法
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        
        if days > 0 {
            return String(format: NSLocalizedString("Time_Format_Days", comment: "%d天 %02d:%02d:%02d"), days, hours, minutes, remainingSeconds)
        } else {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
    }
    
    private func updateRegionName() {
        if StructureMarketManager.isStructureId(selectedRegionID) {
            // 是建筑ID，查找建筑名称
            if let structureId = StructureMarketManager.getStructureId(from: selectedRegionID),
               let structure = getStructureById(structureId) {
                selectedRegionName = structure.structureName
            } else {
                selectedRegionName = "Unknown Structure"
            }
        } else {
            // 是星域ID，查找星域名称
            selectedRegionName = regions.first(where: { $0.id == selectedRegionID })?.name ?? ""
        }
    }
    
    private func getStructureById(_ structureId: Int64) -> MarketStructure? {
        return MarketStructureManager.shared.structures.first { $0.structureId == Int(structureId) }
    }
    
    private func loadRegions() {
        let query = """
            SELECT r.regionID, r.regionName
            FROM regions r
            WHERE r.regionID < 11000000
            ORDER BY r.regionName
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let regionId = row["regionID"] as? Int,
                   let regionName = row["regionName"] as? String {
                    regions.append((id: regionId, name: regionName))
                }
            }
        }
    }
    
    private func loadItemVolumes() {
        var allTypeIDs: [String] = []
        
        // 添加材料ID
        allTypeIDs.append(contentsOf: calculationResult.materials.map { String($0.typeId) })
        
        // 添加产品ID
        if let product = calculationResult.product {
            allTypeIDs.append(String(product.typeId))
        }
        
        guard !allTypeIDs.isEmpty else { return }
        
        let typeIDsString = allTypeIDs.joined(separator: ",")
        let query = "SELECT type_id, volume FROM types WHERE type_id IN (\(typeIDsString))"
        
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let typeID = row["type_id"] as? Int,
                   let volume = row["volume"] as? Double {
                    itemVolumes[typeID] = volume
                }
            }
        }
    }
    
    private func loadMaterialBlueprints() {
        // 获取所有材料的类型ID
        let materialTypeIds = calculationResult.materials.map { $0.typeId }
        
        // 批量查询材料的源蓝图
        materialBlueprintMapping = databaseManager.getBlueprintIDsForProducts(materialTypeIds)
        
        // 获取所有蓝图ID
        var allBlueprintIds: Set<Int> = []
        for blueprintIds in materialBlueprintMapping.values {
            allBlueprintIds.formUnion(blueprintIds)
        }
        
        // 批量获取蓝图信息
        if !allBlueprintIds.isEmpty {
            blueprintInfos = databaseManager.getBlueprintInfos(Array(allBlueprintIds))
        }
        
        Logger.info("已加载 \(materialTypeIds.count) 个材料的源蓝图信息")
        Logger.info("找到 \(materialBlueprintMapping.count) 个材料有源蓝图")
        Logger.info("共 \(allBlueprintIds.count) 个不同的源蓝图")
    }
    
    private func loadAllMarketOrders(forceRefresh: Bool = false) async {
        guard !calculationResult.materials.isEmpty else { return }
        
        // 防止重复加载
        if isLoadingOrders && !forceRefresh {
            return
        }
        
        await MainActor.run {
            isLoadingOrders = true
        }
        
        defer {
            Task { @MainActor in
                isLoadingOrders = false
                hasLoadedOrders = true
            }
        }
        
        await MainActor.run {
            marketOrders.removeAll()
        }
        
        let typeIds = calculationResult.materials.map { $0.typeId }
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
                  let structure = getStructureById(structureId) else {
                Logger.error("无效的建筑ID或未找到建筑信息: \(regionID)")
                return [:]
            }
            
            do {
                Logger.info("开始加载建筑订单，物品数量: \(typeIds.count)")
                
                let batchOrders = try await StructureMarketManager.shared.getBatchItemOrdersInStructure(
                    structureId: structureId,
                    characterId: structure.characterId,
                    typeIds: typeIds,
                    forceRefresh: forceRefresh,
                    progressCallback: progressCallback
                )
                
                Logger.info("成功加载建筑订单，获得 \(batchOrders.count) 个物品的订单数据")
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
                
                for _ in 0..<concurrency {
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
    
    private func calculateTotalPrice() -> (total: Double, hasInsufficientStock: Bool) {
        var total: Double = 0
        var hasInsufficientStock = false
        
        for material in calculationResult.materials {
            let priceInfo = getListPrice(for: material)
            if let price = priceInfo.price {
                total += price * Double(material.finalQuantity)
            }
            if priceInfo.insufficientStock {
                hasInsufficientStock = true
            }
        }
        
        return (total, hasInsufficientStock)
    }
    
    private func calculateTotalVolume() -> Double {
        var totalVolume: Double = 0
        
        for material in calculationResult.materials {
            if let volume = itemVolumes[material.typeId] {
                totalVolume += volume * Double(material.finalQuantity)
            }
        }
        
        return totalVolume
    }
    
    private func getListPrice(for material: BlueprintCalcUtil.MaterialRequirement) -> (price: Double?, insufficientStock: Bool) {
        guard let orders = marketOrders[material.typeId] else { 
            Logger.debug("未找到物品 \(material.typeName) (ID: \(material.typeId)) 的订单数据")
            return (nil, true) 
        }
        
        let quantity = Int64(material.finalQuantity)
        
        var filteredOrders = orders.filter { $0.isBuyOrder == (orderType == .buy) }
        filteredOrders.sort { orderType == .buy ? $0.price > $1.price : $0.price < $1.price }
        
        Logger.debug("物品 \(material.typeName): 总订单数 \(orders.count), 过滤后订单数 \(filteredOrders.count), 需求数量 \(quantity)")
        
        if filteredOrders.isEmpty {
            Logger.debug("物品 \(material.typeName): 没有符合条件的订单")
            return (nil, true)
        }
        
        // 如果不考虑订单数量，直接使用最优价格
        if !considerOrderQuantity {
            let bestPrice = filteredOrders.first?.price ?? 0
            Logger.debug("物品 \(material.typeName): 不考虑订单数量，使用最优价格 \(bestPrice)")
            return (bestPrice, false)
        }
        
        // 考虑订单数量的原有逻辑
        var remainingQuantity = quantity
        var totalPrice: Double = 0
        var availableQuantity: Int64 = 0
        
        for order in filteredOrders {
            if remainingQuantity <= 0 {
                break
            }
            
            let orderQuantity = min(remainingQuantity, Int64(order.volumeRemain))
            totalPrice += Double(orderQuantity) * order.price
            remainingQuantity -= orderQuantity
            availableQuantity += orderQuantity
        }
        
        if remainingQuantity > 0 && availableQuantity > 0 {
            Logger.debug("物品 \(material.typeName): 部分满足需求，可用数量 \(availableQuantity)，总价 \(totalPrice)")
            return (totalPrice / Double(availableQuantity), true)
        } else if remainingQuantity > 0 {
            Logger.debug("物品 \(material.typeName): 完全无法满足需求")
            return (nil, true)
        }
        
        let finalPrice = totalPrice / Double(quantity)
        Logger.debug("物品 \(material.typeName): 完全满足需求，平均价格 \(finalPrice)")
        return (finalPrice, false)
    }
    
    @ViewBuilder
    private func materialRow(_ material: BlueprintCalcUtil.MaterialRequirement) -> some View {
        NavigationLink {
            MarketItemDetailView(
                databaseManager: databaseManager,
                itemID: material.typeId,
                selectedRegionID: selectedRegionID
            )
        } label: {
            HStack(spacing: 12) {
                IconManager.shared.loadImage(for: material.typeIcon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(material.typeName)
                        .lineLimit(1)
                    if isLoadingOrders {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(NSLocalizedString("Main_Database_Loading", comment: "加载中..."))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        let priceInfo = getListPrice(for: material)
                        if let price = priceInfo.price {
                            HStack(spacing: 4) {
                                Text(
                                    NSLocalizedString("Main_Market_Total_Price", comment: "总价: ")
                                    + FormatUtil.format(price * Double(material.finalQuantity), false)
                                    + " ISK"
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                                
                                if priceInfo.insufficientStock {
                                    Text(NSLocalizedString("Main_Market_Insufficient_Stock", comment: "库存不足"))
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        } else {
                            Text(NSLocalizedString("Main_Market_No_Orders", comment: "无订单"))
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                Spacer()
                Text(formatQuantity(material.finalQuantity))
                    .foregroundColor(.secondary)
            }
        }
        .contextMenu {
            // 获取该材料的源蓝图
            if let blueprintIds = materialBlueprintMapping[material.typeId], !blueprintIds.isEmpty {
                ForEach(blueprintIds, id: \.self) { blueprintId in
                    if let blueprintInfo = blueprintInfos[blueprintId] {
                        Button {
                            // 计算需要的流程数
                            let requiredRuns = calculateRequiredRuns(
                                blueprintId: blueprintId,
                                materialTypeId: material.typeId,
                                materialQuantityNeeded: material.finalQuantity
                            )
                            
                            // 创建子蓝图计算器的初始化参数
                            newBlueprintInitParams = BlueprintCalculatorInitParams(
                                blueprintId: blueprintId,
                                runs: requiredRuns,
                                materialEfficiency: 10, // 默认材料效率
                                timeEfficiency: 20, // 默认时间效率
                                selectedStructure: originalStructure,
                                selectedSystemId: originalSystemId,
                                facilityTax: originalFacilityTax,
                                selectedCharacterSkills: originalCharacterSkills,
                                selectedCharacterName: originalCharacterName,
                                selectedCharacterId: originalCharacterId
                            )
                            showNewBlueprintCalculator = true
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: blueprintInfo.iconFileName)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                    .cornerRadius(6)
                                Text(String(format: "%@ \"%@\"", NSLocalizedString("Blueprint_Calculator_View_Blueprint", comment: "查看"), blueprintInfo.name))
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func formatQuantity(_ quantity: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: quantity)) ?? "\(quantity)"
    }
    
    // MARK: - 产品市场相关方法
    
    private func updateProductRegionName() {
        if StructureMarketManager.isStructureId(productSelectedRegionID) {
            // 是建筑ID，查找建筑名称
            if let structureId = StructureMarketManager.getStructureId(from: productSelectedRegionID),
               let structure = getStructureById(structureId) {
                productSelectedRegionName = structure.structureName
            } else {
                productSelectedRegionName = "Unknown Structure"
            }
        } else {
            // 是星域ID，查找星域名称
            productSelectedRegionName = regions.first(where: { $0.id == productSelectedRegionID })?.name ?? ""
        }
    }
    
    private func loadProductMarketOrders(forceRefresh: Bool = false) async {
        guard let product = calculationResult.product else { return }
        
        // 防止重复加载
        if isLoadingProductOrders && !forceRefresh {
            return
        }
        
        await MainActor.run {
            isLoadingProductOrders = true
        }
        
        defer {
            Task { @MainActor in
                isLoadingProductOrders = false
            }
        }
        
        // 使用通用的订单加载方法
        let orders = await loadOrdersForItems(
            typeIds: [product.typeId],
            regionID: productSelectedRegionID,
            forceRefresh: forceRefresh,
            progressCallback: { progress in
                Task { @MainActor in
                    productOrdersProgress = progress
                }
            }
        )
        
        await MainActor.run {
            productMarketOrders = orders[product.typeId] ?? []
        }
    }
    
    private func getProductPrice() -> (price: Double?, insufficientStock: Bool) {
        guard calculationResult.product != nil else { return (nil, true) }
        guard !productMarketOrders.isEmpty else { return (nil, true) }
        
        let filteredOrders = productMarketOrders.filter { $0.isBuyOrder == (productOrderType == .buy) }
            .sorted { productOrderType == .buy ? $0.price > $1.price : $0.price < $1.price }
        
        if filteredOrders.isEmpty {
            return (nil, true)
        }
        
        // 只按最高卖价和最低买价进行计算，不考虑订单数
        return (filteredOrders.first?.price, false)
    }
    
    private func getProductVolume() -> Double {
        guard let product = calculationResult.product else { return 0.0 }
        
        // 使用缓存的体积信息
        if let volume = itemVolumes[product.typeId] {
            return volume * Double(product.totalQuantity)
        }
        
        return 0.0
    }
    
    /// 计算生产指定数量材料所需的蓝图流程数
    /// - Parameters:
    ///   - blueprintId: 蓝图ID
    ///   - materialTypeId: 材料类型ID
    ///   - materialQuantityNeeded: 需要的材料数量
    /// - Returns: 需要的流程数（向上取整）
    private func calculateRequiredRuns(blueprintId: Int, materialTypeId: Int, materialQuantityNeeded: Int) -> Int {
        let query = """
            SELECT quantity
            FROM blueprint_manufacturing_output
            WHERE blueprintTypeID = ? AND typeID = ?
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [blueprintId, materialTypeId]),
           let row = rows.first,
           let outputQuantity = row["quantity"] as? Int,
           outputQuantity > 0 {
            
            // 计算需要的流程数：需求数量 / 每流程产出数量，向上取整
            let requiredRuns = Int(ceil(Double(materialQuantityNeeded) / Double(outputQuantity)))
            
            Logger.info("蓝图ID \(blueprintId) 每流程产出 \(outputQuantity) 个 \(materialTypeId)，需要 \(materialQuantityNeeded) 个，计算得出需要 \(requiredRuns) 个流程")
            
            return max(1, requiredRuns) // 至少1个流程
        } else {
            Logger.warning("无法获取蓝图ID \(blueprintId) 的产出数量，使用默认1个流程")
            return 1
        }
    }
    
    /// 计算利润信息
    /// - Returns: 包含利润和利润率的元组
    private func calculateProfit() -> (profit: Double?, profitMargin: Double?) {
        // 获取产品价格
        let productPriceInfo = getProductPrice()
        guard let productPrice = productPriceInfo.price,
              let product = calculationResult.product else {
            return (nil, nil)
        }
        
        // 计算产品总价值
        let productTotalValue = productPrice * Double(product.totalQuantity)
        
        // 获取材料总成本
        let materialCostInfo = calculateTotalPrice()
        let materialTotalCost = materialCostInfo.total
        
        // 获取手续费
        let facilityCost = calculationResult.facilityCost
        
        // 计算利润 = 产品价值 - 材料成本 - 手续费
        let profit = productTotalValue - materialTotalCost - facilityCost
        
        // 计算利润率 = 利润 / (材料成本 + 手续费)
        let totalCost = materialTotalCost + facilityCost
        let profitMargin = totalCost > 0 ? profit / totalCost : nil
        
        return (profit, profitMargin)
    }
    
    /// 根据利润和利润率获取显示颜色
    /// - Parameters:
    ///   - profit: 利润金额
    ///   - profitMargin: 利润率
    /// - Returns: 对应的颜色
    private func getProfitColor(profit: Double, profitMargin: Double) -> Color {
        if profit < 0 {
            return .red  // 亏损显示红色
        } else if profitMargin < 0.01 {  // 利润率低于1%
            return .orange  // 显示橘黄色
        } else {
            return .green  // 正常盈利显示绿色
        }
    }
    
    /// 检查是否有材料的英文名称与中文名称不同
    /// - Returns: 是否有不同的英文名称
    private func hasDifferentEnglishNames() -> Bool {
        return calculationResult.materials.contains { material in
            material.typeEnName != material.typeName
        }
    }
    
    /// 复制材料列表到剪贴板
    /// - Parameter useEnglishNames: 是否使用英文名称
    private func copyMaterialsToClipboard(useEnglishNames: Bool) {
        let materialsText = calculationResult.materials.map { material in
            let materialName = useEnglishNames ? material.typeEnName : material.typeName
            return "\(materialName)      \(material.finalQuantity)"
        }.joined(separator: "\n")
        
        UIPasteboard.general.string = materialsText
        showingCopyAlert = true
    }
} 
