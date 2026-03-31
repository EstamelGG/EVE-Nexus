import SwiftUI

struct ShipFittingPriceView: View {
    @ObservedObject var viewModel: FittingEditorViewModel
    @State private var isLoadingPrices = false
    @State private var priceCategories: [PriceCategory] = []
    @State private var totalPrice: Double = 0
    @State private var errorMessage: String?
    @State private var hasUnpricedItems = false
    @State private var showAddToWatchlistAlert = false
    @State private var addToWatchlistName = ""
    @State private var showAddToWatchlistSuccessAlert = false
    @State private var savedWatchlistName = ""

    var body: some View {
        // 总价Section
        Section {
            HStack {
                Image("isk")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Fitting_Total_Price", comment: ""))
                        .font(.headline)

                    if isLoadingPrices {
                        Text(NSLocalizedString("Fitting_Calculating", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let error = errorMessage {
                        Text(
                            String(
                                format: NSLocalizedString("Fitting_Price_Failed", comment: ""),
                                error
                            )
                        )
                        .font(.caption)
                        .foregroundColor(.red)
                    } else {
                        Text(totalPrice > 0 ? FormatUtil.formatISK(totalPrice) : "-")
                            .font(.caption)
                            .foregroundColor(hasUnpricedItems ? .red : .secondary)
                    }
                }

                Spacer()

                if isLoadingPrices {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if totalPrice > 0 {
                    Button(NSLocalizedString("Fitting_Refresh", comment: "")) {
                        Task {
                            await loadPriceData(forceRefresh: true)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }

            // 分类价格DisclosureGroups
            ForEach(priceCategories, id: \.name) { category in
                DisclosureGroup {
                    ForEach(category.items, id: \.typeId) { item in
                        PriceItemRowView(item: item)
                    }
                } label: {
                    HStack {
                        IconManager.shared.loadImage(for: category.icon)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(category.name)
                                .font(.body)
                                .foregroundColor(.primary)

                            Text(
                                String(
                                    format: NSLocalizedString("Misc_Items", comment: ""),
                                    category.items.map { $0.quantity }.reduce(0, +)
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(
                            category.totalPrice > 0
                                ? FormatUtil.formatISK(category.totalPrice) : "-"
                        )
                        .font(.caption)
                        .foregroundColor(category.hasUnpricedItems ? .red : .secondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }

            // 错误信息或空状态
            if priceCategories.isEmpty && !isLoadingPrices {
                if let error = errorMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NSLocalizedString("Fitting_Price_Failed", comment: ""))
                            .font(.caption)
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Fitting_No_Price_Data", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }

            // 添加到市场关注列表按钮行（始终显示，样式参考添加到技能计划）
            Button {
                let shipName = viewModel.simulationInput.ship.name
                let fittingName = viewModel.simulationInput.name.isEmpty
                    ? NSLocalizedString("Fitting_Unnamed_Fitting", comment: "")
                    : viewModel.simulationInput.name
                addToWatchlistName = "\(shipName)-\(fittingName)"
                showAddToWatchlistAlert = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(NSLocalizedString("Fitting_Add_To_Watchlist", comment: "添加到市场关注"))
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        } header: {
            Text(NSLocalizedString("Fitting_Price", comment: ""))
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .font(.system(size: 18))
        }
        .onAppear {
            if totalPrice == 0 && priceCategories.isEmpty {
                Task {
                    await loadPriceData()
                }
            }
        }
        .onReceive(viewModel.objectWillChange) { _ in
            // 当配装发生变化时，重新计算价格
            Task {
                await loadPriceData()
            }
        }
        .alert(NSLocalizedString("Fitting_Add_To_Watchlist", comment: ""), isPresented: $showAddToWatchlistAlert) {
            TextField(NSLocalizedString("Main_Market_Watch_List_Name", comment: ""), text: $addToWatchlistName)
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("Misc_Save", comment: "保存")) {
                addFittingToWatchlist(name: addToWatchlistName.trimmingCharacters(in: .whitespaces))
            }
        } message: {
            Text(NSLocalizedString("Fitting_Add_To_Watchlist_Name_Prompt", comment: ""))
        }
        .alert(NSLocalizedString("Fitting_Add_To_Watchlist_Success_Title", comment: ""), isPresented: $showAddToWatchlistSuccessAlert) {
            Button(NSLocalizedString("Misc_Done", comment: "")) {}
        } message: {
            Text(String(format: NSLocalizedString("Fitting_Add_To_Watchlist_Saved_Message", comment: ""), savedWatchlistName))
        }
    }

    /// 从配装收集物品 (typeId, quantity)，不依赖价格数据
    private func collectFittingItems() -> [(typeId: Int, quantity: Int)] {
        var map: [Int: Int] = [:]
        let input = viewModel.simulationInput

        map[input.ship.typeId, default: 0] += 1
        for module in input.modules {
            map[module.typeId, default: 0] += module.quantity
            if let charge = module.charge, let qty = charge.chargeQuantity, qty > 0 {
                map[charge.typeId, default: 0] += qty
            }
        }
        for drone in input.drones {
            map[drone.typeId, default: 0] += drone.quantity
        }
        if let fighters = input.fighters {
            for fighter in fighters {
                map[fighter.typeId, default: 0] += fighter.quantity
            }
        }
        for implant in input.implants {
            map[implant.typeId, default: 0] += 1
        }
        for cargoItem in input.cargo.items {
            map[cargoItem.typeId, default: 0] += cargoItem.quantity
        }

        return map.map { ($0.key, $0.value) }
    }

    private func addFittingToWatchlist(name: String) {
        guard !name.isEmpty else { return }
        let items = collectFittingItems()
        guard !items.isEmpty else { return }

        let newQuickbar = MarketQuickbar(name: name, items: [])
        var updated = newQuickbar
        for (typeId, quantity) in items {
            updated.items.append(QuickbarItem(typeID: typeId, quantity: Int64(quantity)))
        }
        MarketQuickbarManager.shared.saveQuickbar(updated)
        savedWatchlistName = name
        showAddToWatchlistSuccessAlert = true
    }

    // 加载价格数据
    private func loadPriceData(forceRefresh: Bool = false) async {
        await MainActor.run {
            isLoadingPrices = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isLoadingPrices = false
            }
        }

        let (categories, total, hasUnpriced) = await calculateFittingPrice(
            forceRefresh: forceRefresh)
        await MainActor.run {
            self.priceCategories = categories
            self.totalPrice = total
            self.hasUnpricedItems = hasUnpriced
        }
    }

    // 计算配装价格
    private func calculateFittingPrice(forceRefresh: Bool = false) async -> (
        [PriceCategory], Double, Bool
    ) {
        var allCategories: [PriceCategory] = []
        var totalPrice: Double = 0
        var hasUnpricedItems = false

        // 收集所有需要查询价格的物品ID
        var allTypeIds: Set<Int> = []

        // 飞船
        allTypeIds.insert(viewModel.simulationInput.ship.typeId)
        print(
            "价格计算: 添加飞船 \(viewModel.simulationInput.ship.name) (TypeID: \(viewModel.simulationInput.ship.typeId))"
        )

        // 装备和弹药
        print("价格计算: 开始收集装备和弹药，共 \(viewModel.simulationInput.modules.count) 个装备")
        for module in viewModel.simulationInput.modules {
            allTypeIds.insert(module.typeId)
            print("价格计算: 添加装备 \(module.name) (TypeID: \(module.typeId))")
            if let charge = module.charge {
                allTypeIds.insert(charge.typeId)
                print(
                    "价格计算: 添加弹药 \(charge.name) (TypeID: \(charge.typeId)) 数量: \(charge.chargeQuantity ?? 0)"
                )
            }
        }

        // 无人机
        print("价格计算: 开始收集无人机，共 \(viewModel.simulationInput.drones.count) 个无人机类型")
        for drone in viewModel.simulationInput.drones {
            allTypeIds.insert(drone.typeId)
            print("价格计算: 添加无人机 \(drone.name) (TypeID: \(drone.typeId)) 数量: \(drone.quantity)")
        }

        // 舰载机
        if let fighters = viewModel.simulationInput.fighters {
            print("价格计算: 开始收集舰载机，共 \(fighters.count) 个舰载机类型")
            for fighter in fighters {
                allTypeIds.insert(fighter.typeId)
                print(
                    "价格计算: 添加舰载机 \(fighter.name) (TypeID: \(fighter.typeId)) 数量: \(fighter.quantity)"
                )
            }
        } else {
            print("价格计算: 无舰载机")
        }

        // 植入体
        print("价格计算: 开始收集植入体，共 \(viewModel.simulationInput.implants.count) 个植入体")
        for implant in viewModel.simulationInput.implants {
            allTypeIds.insert(implant.typeId)
            print("价格计算: 添加植入体 \(implant.name) (TypeID: \(implant.typeId))")
        }

        // 货舱物品
        print("价格计算: 开始收集货舱物品，共 \(viewModel.simulationInput.cargo.items.count) 个物品类型")
        for cargoItem in viewModel.simulationInput.cargo.items {
            allTypeIds.insert(cargoItem.typeId)
            print(
                "价格计算: 添加货舱物品 \(cargoItem.name) (TypeID: \(cargoItem.typeId)) 数量: \(cargoItem.quantity)"
            )
        }

        print("价格计算: 总共收集了 \(allTypeIds.count) 个不同的物品类型ID")

        // 获取价格数据
        let prices = await MarketPriceUtil.getJitaOrderPricesFromESI(
            typeIds: Array(allTypeIds),
            orderType: .sell,
            forceRefresh: forceRefresh
        )
        print("价格计算: 获取到 \(prices.count) 个物品的价格数据")

        // 1. 舰船分类
        let shipPrice = prices[viewModel.simulationInput.ship.typeId] ?? 0
        let shipHasUnpriced = shipPrice == 0
        if shipHasUnpriced {
            hasUnpricedItems = true
        }
        let shipItems = [
            PriceItem(
                typeId: viewModel.simulationInput.ship.typeId,
                name: viewModel.simulationInput.ship.name,
                quantity: 1,
                unitPrice: shipPrice,
                totalPrice: shipPrice,
                iconFileName: viewModel.simulationInput.ship.iconFileName,
                category: NSLocalizedString("Fitting_Ship", comment: "")
            ),
        ]
        allCategories.append(
            PriceCategory(
                name: NSLocalizedString("Fitting_Ship", comment: ""),
                icon: "ship",
                totalPrice: shipPrice,
                items: shipItems,
                hasUnpricedItems: shipHasUnpriced
            ))
        totalPrice += shipPrice

        // 2. 装备和弹药分类
        var moduleItemsMap: [Int: PriceItem] = [:]
        var moduleAndChargePrice: Double = 0
        var moduleAndChargeHasUnpriced = false

        // 处理装备
        for module in viewModel.simulationInput.modules {
            let modulePrice = prices[module.typeId] ?? 0
            if modulePrice == 0 {
                hasUnpricedItems = true
                moduleAndChargeHasUnpriced = true
            }
            let totalModulePrice = modulePrice * Double(module.quantity)

            if let existingItem = moduleItemsMap[module.typeId] {
                // 合并相同装备
                moduleItemsMap[module.typeId] = PriceItem(
                    typeId: existingItem.typeId,
                    name: existingItem.name,
                    quantity: existingItem.quantity + module.quantity,
                    unitPrice: existingItem.unitPrice,
                    totalPrice: existingItem.totalPrice + totalModulePrice,
                    iconFileName: existingItem.iconFileName,
                    category: existingItem.category
                )
            } else {
                moduleItemsMap[module.typeId] = PriceItem(
                    typeId: module.typeId,
                    name: module.name,
                    quantity: module.quantity,
                    unitPrice: modulePrice,
                    totalPrice: totalModulePrice,
                    iconFileName: module.iconFileName,
                    category: NSLocalizedString("Fitting_Modules_And_Charges", comment: "")
                )
            }
            moduleAndChargePrice += totalModulePrice

            // 处理弹药
            if let charge = module.charge, let chargeQuantity = charge.chargeQuantity,
               chargeQuantity > 0
            {
                let chargePrice = prices[charge.typeId] ?? 0
                if chargePrice == 0 {
                    hasUnpricedItems = true
                    moduleAndChargeHasUnpriced = true
                }
                let totalChargePrice = chargePrice * Double(chargeQuantity)

                if let existingCharge = moduleItemsMap[charge.typeId] {
                    // 合并相同弹药
                    moduleItemsMap[charge.typeId] = PriceItem(
                        typeId: existingCharge.typeId,
                        name: existingCharge.name,
                        quantity: existingCharge.quantity + chargeQuantity,
                        unitPrice: existingCharge.unitPrice,
                        totalPrice: existingCharge.totalPrice + totalChargePrice,
                        iconFileName: existingCharge.iconFileName,
                        category: existingCharge.category
                    )
                } else {
                    moduleItemsMap[charge.typeId] = PriceItem(
                        typeId: charge.typeId,
                        name: charge.name,
                        quantity: chargeQuantity,
                        unitPrice: chargePrice,
                        totalPrice: totalChargePrice,
                        iconFileName: charge.iconFileName,
                        category: NSLocalizedString("Fitting_Modules_And_Charges", comment: "")
                    )
                }
                moduleAndChargePrice += totalChargePrice
            }
        }

        if !moduleItemsMap.isEmpty {
            let moduleItems = Array(moduleItemsMap.values).sorted { $0.totalPrice > $1.totalPrice }
            allCategories.append(
                PriceCategory(
                    name: NSLocalizedString("Fitting_Modules_And_Charges", comment: ""),
                    icon: "gunnery_turret",
                    totalPrice: moduleAndChargePrice,
                    items: moduleItems,
                    hasUnpricedItems: moduleAndChargeHasUnpriced
                ))
            totalPrice += moduleAndChargePrice
        }

        // 3. 无人机/舰载机分类
        var droneAndFighterItemsMap: [Int: PriceItem] = [:]
        var droneAndFighterPrice: Double = 0
        var droneAndFighterHasUnpriced = false

        // 处理无人机
        for drone in viewModel.simulationInput.drones {
            let dronePrice = prices[drone.typeId] ?? 0
            if dronePrice == 0 {
                hasUnpricedItems = true
                droneAndFighterHasUnpriced = true
            }
            let totalDronePrice = dronePrice * Double(drone.quantity)

            if let existingDrone = droneAndFighterItemsMap[drone.typeId] {
                // 合并相同无人机
                droneAndFighterItemsMap[drone.typeId] = PriceItem(
                    typeId: existingDrone.typeId,
                    name: existingDrone.name,
                    quantity: existingDrone.quantity + drone.quantity,
                    unitPrice: existingDrone.unitPrice,
                    totalPrice: existingDrone.totalPrice + totalDronePrice,
                    iconFileName: existingDrone.iconFileName,
                    category: existingDrone.category
                )
            } else {
                droneAndFighterItemsMap[drone.typeId] = PriceItem(
                    typeId: drone.typeId,
                    name: drone.name,
                    quantity: drone.quantity,
                    unitPrice: dronePrice,
                    totalPrice: totalDronePrice,
                    iconFileName: drone.iconFileName,
                    category: NSLocalizedString("Fitting_Drones_And_Fighters", comment: "")
                )
            }
            droneAndFighterPrice += totalDronePrice
        }

        // 处理舰载机
        if let fighters = viewModel.simulationInput.fighters {
            for fighter in fighters {
                let fighterPrice = prices[fighter.typeId] ?? 0
                if fighterPrice == 0 {
                    hasUnpricedItems = true
                    droneAndFighterHasUnpriced = true
                }
                let totalFighterPrice = fighterPrice * Double(fighter.quantity)

                if let existingFighter = droneAndFighterItemsMap[fighter.typeId] {
                    // 合并相同舰载机
                    droneAndFighterItemsMap[fighter.typeId] = PriceItem(
                        typeId: existingFighter.typeId,
                        name: existingFighter.name,
                        quantity: existingFighter.quantity + fighter.quantity,
                        unitPrice: existingFighter.unitPrice,
                        totalPrice: existingFighter.totalPrice + totalFighterPrice,
                        iconFileName: existingFighter.iconFileName,
                        category: existingFighter.category
                    )
                } else {
                    droneAndFighterItemsMap[fighter.typeId] = PriceItem(
                        typeId: fighter.typeId,
                        name: fighter.name,
                        quantity: fighter.quantity,
                        unitPrice: fighterPrice,
                        totalPrice: totalFighterPrice,
                        iconFileName: fighter.iconFileName,
                        category: NSLocalizedString("Fitting_Drones_And_Fighters", comment: "")
                    )
                }
                droneAndFighterPrice += totalFighterPrice
            }
        }

        if !droneAndFighterItemsMap.isEmpty {
            let droneAndFighterItems = Array(droneAndFighterItemsMap.values).sorted {
                $0.totalPrice > $1.totalPrice
            }
            allCategories.append(
                PriceCategory(
                    name: NSLocalizedString("Fitting_Drones_And_Fighters", comment: ""),
                    icon: "drone_band",
                    totalPrice: droneAndFighterPrice,
                    items: droneAndFighterItems,
                    hasUnpricedItems: droneAndFighterHasUnpriced
                ))
            totalPrice += droneAndFighterPrice
        }

        // 4. 货舱分类
        var cargoItemsMap: [Int: PriceItem] = [:]
        var cargoPrice: Double = 0
        var cargoHasUnpriced = false

        for cargoItem in viewModel.simulationInput.cargo.items {
            let itemPrice = prices[cargoItem.typeId] ?? 0
            if itemPrice == 0 {
                hasUnpricedItems = true
                cargoHasUnpriced = true
            }
            let totalItemPrice = itemPrice * Double(cargoItem.quantity)

            if let existingItem = cargoItemsMap[cargoItem.typeId] {
                // 合并相同货舱物品
                cargoItemsMap[cargoItem.typeId] = PriceItem(
                    typeId: existingItem.typeId,
                    name: existingItem.name,
                    quantity: existingItem.quantity + cargoItem.quantity,
                    unitPrice: existingItem.unitPrice,
                    totalPrice: existingItem.totalPrice + totalItemPrice,
                    iconFileName: existingItem.iconFileName,
                    category: existingItem.category
                )
            } else {
                cargoItemsMap[cargoItem.typeId] = PriceItem(
                    typeId: cargoItem.typeId,
                    name: cargoItem.name,
                    quantity: cargoItem.quantity,
                    unitPrice: itemPrice,
                    totalPrice: totalItemPrice,
                    iconFileName: cargoItem.iconFileName,
                    category: NSLocalizedString("Fitting_Cargo", comment: "")
                )
            }
            cargoPrice += totalItemPrice
        }

        if !cargoItemsMap.isEmpty {
            let cargoItems = Array(cargoItemsMap.values).sorted { $0.totalPrice > $1.totalPrice }
            allCategories.append(
                PriceCategory(
                    name: NSLocalizedString("Fitting_Cargo", comment: ""),
                    icon: "cargo_fit",
                    totalPrice: cargoPrice,
                    items: cargoItems,
                    hasUnpricedItems: cargoHasUnpriced
                ))
            totalPrice += cargoPrice
        }

        // 5. 植入体分类
        var implantItemsMap: [Int: PriceItem] = [:]
        var implantPrice: Double = 0
        var implantHasUnpriced = false

        for implant in viewModel.simulationInput.implants {
            let price = prices[implant.typeId] ?? 0
            if price == 0 {
                hasUnpricedItems = true
                implantHasUnpriced = true
            }

            if let existingImplant = implantItemsMap[implant.typeId] {
                // 合并相同植入体（虽然通常不会有重复）
                implantItemsMap[implant.typeId] = PriceItem(
                    typeId: existingImplant.typeId,
                    name: existingImplant.name,
                    quantity: existingImplant.quantity + 1,
                    unitPrice: existingImplant.unitPrice,
                    totalPrice: existingImplant.totalPrice + price,
                    iconFileName: existingImplant.iconFileName,
                    category: existingImplant.category
                )
            } else {
                implantItemsMap[implant.typeId] = PriceItem(
                    typeId: implant.typeId,
                    name: implant.name,
                    quantity: 1,
                    unitPrice: price,
                    totalPrice: price,
                    iconFileName: implant.iconFileName,
                    category: NSLocalizedString("Fitting_Implants", comment: "")
                )
            }
            implantPrice += price
        }

        if !implantItemsMap.isEmpty {
            let implantItems = Array(implantItemsMap.values).sorted {
                $0.totalPrice > $1.totalPrice
            }
            allCategories.append(
                PriceCategory(
                    name: NSLocalizedString("Fitting_Implants", comment: ""),
                    icon: "implants",
                    totalPrice: implantPrice,
                    items: implantItems,
                    hasUnpricedItems: implantHasUnpriced
                ))
            totalPrice += implantPrice
        }

        // 过滤掉空的分类，但保留价格为0的分类（如果有物品的话）
        let filteredCategories = allCategories.filter { !$0.items.isEmpty }

        return (filteredCategories, totalPrice, hasUnpricedItems)
    }
}

// 价格物品行视图
struct PriceItemRowView: View {
    let item: PriceItem

    var body: some View {
        HStack {
            // 物品图标
            if let iconFileName = item.iconFileName, !iconFileName.isEmpty {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if item.quantity > 1 {
                        Text(
                            "\(item.quantity) × \(item.unitPrice > 0 ? FormatUtil.formatISK(item.unitPrice) : "-")"
                        )
                        .font(.caption)
                        .foregroundColor(item.unitPrice > 0 ? .secondary : .red)
                    } else {
                        Text(item.unitPrice > 0 ? "\(FormatUtil.formatISK(item.unitPrice))" : "-")
                            .font(.caption)
                            .foregroundColor(item.unitPrice > 0 ? .secondary : .red)
                    }
                }
            }

            Spacer()
        }
    }
}

// 价格分类模型
struct PriceCategory {
    let name: String
    let icon: String
    let totalPrice: Double
    let items: [PriceItem]
    let hasUnpricedItems: Bool
}

// 价格物品模型
struct PriceItem {
    let typeId: Int
    let name: String
    let quantity: Int
    let unitPrice: Double
    let totalPrice: Double
    let iconFileName: String?
    let category: String
}
