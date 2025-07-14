import SwiftUI

struct ContractAppraisalView: View {
    let contract: ContractInfo
    let items: [ContractItemInfo]
    @State private var isLoadingJanice = false
    @State private var isLoadingESI = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var janiceResult: JaniceResult?
    @State private var esiResult: ESIAppraisalResult?
    @State private var showFullAmount: Bool = true
    @State private var discountPercentage: Double = 100
    @State private var safeDiscountPercentage: Double = 99999
    @State private var showDiscountAlert = false
    @State private var hasBlueprint = false
    @State private var hasInsufficientOrders = false
    @State private var discountText: String = "100" // 新增：用于管理输入文本

    // 在初始化时从UserDefaults加载设置
    init(contract: ContractInfo, items: [ContractItemInfo]) {
        self.contract = contract
        self.items = items
        let defaults = UserDefaults.standard
        // 读取设置，如果不存在则默认为true
        _showFullAmount = State(
            initialValue: defaults.object(forKey: "contractAppraisalShowFullAmount") as? Bool
                ?? true)
    }

    var body: some View {
        List {
            // 估价选项部分
            Section {
                // Janice估价选项
                Button(action: {
                    Task {
                        await performJaniceAppraisal()
                    }
                }) {
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Via_Janice", comment: ""))
                        Spacer()
                        if isLoadingJanice {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isLoadingJanice || isLoadingESI)

                // ESI估价选项
                Button(action: {
                    Task {
                        await performESIAppraisal()
                    }
                }) {
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Via_ESI", comment: ""))
                        Spacer()
                        if isLoadingESI {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isLoadingJanice || isLoadingESI)
            }

            // 显示设置部分
            Section {
                // 显示完整金额开关
                Toggle(
                    isOn: Binding(
                        get: { showFullAmount },
                        set: {
                            showFullAmount = $0
                            // 当值改变时保存到UserDefaults
                            UserDefaults.standard.set(
                                showFullAmount, forKey: "contractAppraisalShowFullAmount")
                        }
                    )
                ) {
                    Text(NSLocalizedString("Contract_Appraisal_Show_Full_Amount", comment: ""))
                }

                // 设置合同价格折扣
                Button(action: {
                    discountText = String(Int(discountPercentage))
                    showDiscountAlert = true
                }) {
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Set_Discount", comment: ""))
                        Spacer()
                        Text("\(min(Int(safeDiscountPercentage), Int(discountPercentage)))%")
                            .foregroundColor(.secondary)
                    }
                }
                .alert(
                    NSLocalizedString("Contract_Appraisal_Discount_Title", comment: ""),
                    isPresented: $showDiscountAlert
                ) {
                    TextField(
                        NSLocalizedString("Contract_Appraisal_Discount_Placeholder", comment: ""),
                        text: Binding<String>(
                            get: { discountText },
                            set: { newValue in
                                // 只允许数字字符
                                let filtered = newValue.filter { $0.isNumber }
                                // 限制最大5位数
                                if filtered.count <= 5 {
                                    discountText = filtered
                                }
                            }
                        )
                    )
                    .keyboardType(.numberPad)
                    Button(
                        NSLocalizedString("Contract_Appraisal_Discount_Cancel", comment: ""),
                        role: .cancel
                    ) {}
                    Button(NSLocalizedString("Contract_Appraisal_Discount_Confirm", comment: "")) {
                        // 将文本转换为数值
                        if let value = Double(discountText), value > 0 {
                            discountPercentage = value
                        }
                    }
                } message: {
                    Text(NSLocalizedString("Contract_Appraisal_Discount_Message", comment: ""))
                }
            } header: {
                Text(NSLocalizedString("Contract_Appraisal_Display_Settings", comment: ""))
            }

            // Janice估价结果部分
            if let result = janiceResult {
                let buy_price = formatPrice(result.immediatePrices.totalBuyPrice * min(safeDiscountPercentage, discountPercentage) / 100)
                let split_price = formatPrice(result.immediatePrices.totalSplitPrice * min(safeDiscountPercentage, discountPercentage) / 100)
                let sell_price = formatPrice(result.immediatePrices.totalSellPrice * min(safeDiscountPercentage, discountPercentage) / 100)
                Section {
                    // 买入价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Buy_Price", comment: ""))
                        Spacer()
                        Text(buy_price)
                            .foregroundColor(.red)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = buy_price
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                                }
                            }
                            .font(.system(.body, design: .monospaced))
                    }

                    // 中间价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Middle_Price", comment: ""))
                        Spacer()
                        Text(split_price)
                        .foregroundColor(.orange)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = split_price
                            } label: {
                                Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                    }

                    // 卖出价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Sell_Price", comment: ""))
                        Spacer()
                        Text(sell_price)
                        .foregroundColor(.green)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = sell_price
                            } label: {
                                Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                    }

                    // 查看详情按钮
                    Button(action: {
                        if let url = URL(string: "https://janice.e-351.com/a/\(result.code)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Text(NSLocalizedString("Contract_Appraisal_View_Details", comment: ""))
                            Image(systemName: "arrow.up.right.square")
                        }
                        .frame(maxWidth: .infinity)
                    }
                } header: {
                    Text(
                        result.name
                            ?? String(
                                format: NSLocalizedString("Contract_Appraisal_Result", comment: ""),
                                result.pricerMarket.name
                            ))
                } footer: {
                    if hasBlueprint {
                        Text(NSLocalizedString("Contract_Appraisal_Blueprint_Warning", comment: ""))
                            .foregroundColor(.red)
                    }
                }
            }

            // ESI估价结果部分
            if let result = esiResult {
                let buy_price_esi = formatPrice(result.totalBuyPrice * min(safeDiscountPercentage, discountPercentage) / 100)
                let middle_price_esi = formatPrice(result.totalMiddlePrice * min(safeDiscountPercentage, discountPercentage) / 100)
                let sell_price_esi = formatPrice(result.totalSellPrice * min(safeDiscountPercentage, discountPercentage) / 100)
                Section {
                    // 买入价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Buy_Price", comment: ""))
                        Spacer()
                        Text(buy_price_esi)
                            .foregroundColor(.red)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = buy_price_esi
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                                }
                            }
                            .font(.system(.body, design: .monospaced))
                    }

                    // 中间价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Middle_Price", comment: ""))
                        Spacer()
                        Text(middle_price_esi)
                            .foregroundColor(.orange)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = middle_price_esi
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                                }
                            }
                            .font(.system(.body, design: .monospaced))
                    }

                    // 卖出价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Sell_Price", comment: ""))
                        Spacer()
                        Text(sell_price_esi)
                            .foregroundColor(.green)
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = sell_price_esi
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                                }
                            }
                            .font(.system(.body, design: .monospaced))
                    }
                } header: {
                    Text(NSLocalizedString("Contract_Appraisal_ESI_Result", comment: ""))
                } footer: {
                    VStack(alignment: .leading) {
                        if hasBlueprint {
                            Text(
                                NSLocalizedString(
                                    "Contract_Appraisal_Blueprint_Warning", comment: "")
                            )
                            .foregroundColor(.red)
                        }
                        if hasInsufficientOrders {
                            Text(
                                NSLocalizedString(
                                    "Contract_Appraisal_Insufficient_Orders_Warning", comment: "")
                            )
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Contract_Appraisal_Title", comment: ""))
        .alert(NSLocalizedString("Contract_Appraisal_Error", comment: ""), isPresented: $showError)
        {
            Button(NSLocalizedString("Contract_Appraisal_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(errorMessage ?? NSLocalizedString("Contract_Appraisal_Unknown_Error", comment: ""))
        }
    }

    // 根据显示设置格式化价格
    private func formatPrice(_ price: Double) -> String {
        if showFullAmount {
            return "\(FormatUtil.format(price)) ISK"
        } else {
            return "\(FormatUtil.formatISK(price))"
        }
    }

    private func checkForBlueprints() -> Bool {
        let typeIds = items.map { String($0.type_id) }.joined(separator: ",")
        let query = """
                SELECT COUNT(*) as count
                FROM types
                WHERE type_id IN (\(typeIds))
                AND categoryID = 9
            """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(query),
            let row = rows.first,
            let count = row["count"] as? Int
        {
            if count > 0 {
                Logger.warning("Contract Appraisal: 合同包含蓝图，估价可能不准确")
            }
            return count > 0
        }
        return false
    }

    private func performJaniceAppraisal() async {
        isLoadingJanice = true
        defer { isLoadingJanice = false }

        // 检查是否包含蓝图
        hasBlueprint = checkForBlueprints()

        // 构建物品字典，合并相同type_id的数量
        var itemsDict: [String: Int] = [:]
        for item in items {
            let typeIdStr = String(item.type_id)
            itemsDict[typeIdStr] = (itemsDict[typeIdStr] ?? 0) + item.quantity
        }

        do {
            let result = try await JaniceMarketAPI.shared.createAppraisal(items: itemsDict)
            if let janiceResponse = try? JSONDecoder().decode(JaniceResponse.self, from: result) {
                await MainActor.run {
                    self.janiceResult = janiceResponse.result
                }
            } else {
                throw NSError(
                    domain: "JaniceMarketAPI", code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(
                            format: NSLocalizedString(
                                "Contract_Appraisal_Parse_Failed", comment: ""
                            ), "\(result)"
                        )
                    ]
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func performESIAppraisal() async {
        isLoadingESI = true
        defer { isLoadingESI = false }

        // 检查是否包含蓝图
        hasBlueprint = checkForBlueprints()

        // 默认使用吉他(Jita)市场
        let regionID = 10_000_002  // The Forge (Jita所在星域)
        let systemID = 30_000_142  // Jita星系ID

        // 合并相同type_id的物品数量
        var itemsDict: [Int: Int64] = [:]
        for item in items {
            itemsDict[item.type_id] = (itemsDict[item.type_id] ?? 0) + Int64(item.quantity)
        }

        do {
            // 创建任务组并发获取市场订单
            var marketOrders: [Int: [MarketOrder]] = [:]
            let concurrency = max(1, min(10, itemsDict.count))

            await withTaskGroup(of: (Int, [MarketOrder])?.self) { group in
                var pendingItems = Array(itemsDict.keys)

                // 初始添加并发数量的任务
                for _ in 0..<min(concurrency, pendingItems.count) {
                    if let typeID = pendingItems.popLast() {
                        group.addTask {
                            do {
                                let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                    typeID: typeID,
                                    regionID: regionID,
                                    forceRefresh: true
                                )
                                return (typeID, orders)
                            } catch {
                                Logger.error("加载市场订单失败: \(error)")
                                return nil
                            }
                        }
                    }
                }

                // 处理结果并添加新任务
                while let result = await group.next() {
                    if let (typeID, orders) = result {
                        marketOrders[typeID] = orders
                    }

                    // 如果还有待处理的物品，添加新任务
                    if let typeID = pendingItems.popLast() {
                        group.addTask {
                            do {
                                let orders = try await MarketOrdersAPI.shared.fetchMarketOrders(
                                    typeID: typeID,
                                    regionID: regionID,
                                    forceRefresh: true
                                )
                                return (typeID, orders)
                            } catch {
                                Logger.error("加载市场订单失败: \(error)")
                                return nil
                            }
                        }
                    }
                }
            }

            // 计算每个物品的价格
            var totalBuyPrice: Double = 0
            var totalSellPrice: Double = 0
            var itemsWithoutOrders = 0
            Logger.info("ESI Appraisal: marketOrders = \(marketOrders)")
            for (typeID, quantity) in itemsDict {
                guard let orders = marketOrders[typeID], !orders.isEmpty else {
                    itemsWithoutOrders += 1
                    continue
                }

                // 过滤买单和卖单
                let buyOrders = orders.filter { $0.isBuyOrder && $0.systemId == systemID }
                    .sorted(by: { $0.price > $1.price })  // 买单从高到低排序

                let sellOrders = orders.filter { !$0.isBuyOrder && $0.systemId == systemID }
                    .sorted(by: { $0.price < $1.price })  // 卖单从低到高排序

                // 计算买价
                var remainingBuyQuantity = quantity
                var totalBuyItemPrice: Double = 0
                var availableBuyQuantity: Int64 = 0

                for order in buyOrders {
                    if remainingBuyQuantity <= 0 { break }

                    let orderQuantity = min(remainingBuyQuantity, Int64(order.volumeRemain))
                    totalBuyItemPrice += Double(orderQuantity) * order.price
                    remainingBuyQuantity -= orderQuantity
                    availableBuyQuantity += orderQuantity
                }

                // 计算卖价
                var remainingSellQuantity = quantity
                var totalSellItemPrice: Double = 0
                var availableSellQuantity: Int64 = 0

                for order in sellOrders {
                    if remainingSellQuantity <= 0 { break }

                    let orderQuantity = min(remainingSellQuantity, Int64(order.volumeRemain))
                    totalSellItemPrice += Double(orderQuantity) * order.price
                    remainingSellQuantity -= orderQuantity
                    availableSellQuantity += orderQuantity
                }

                // 累加总价
                totalBuyPrice += totalBuyItemPrice
                totalSellPrice += totalSellItemPrice
            }

            // 计算中间价格
            let totalMiddlePrice = (totalBuyPrice + totalSellPrice) / 2

            // 创建ESI估价结果
            let result = ESIAppraisalResult(
                totalBuyPrice: totalBuyPrice,
                totalSellPrice: totalSellPrice,
                totalMiddlePrice: totalMiddlePrice
            )

            await MainActor.run {
                self.esiResult = result
                self.hasInsufficientOrders = itemsWithoutOrders > 0
            }
        }
    }
}

// ESI估价结果模型
struct ESIAppraisalResult {
    let totalBuyPrice: Double
    let totalSellPrice: Double
    let totalMiddlePrice: Double
}
