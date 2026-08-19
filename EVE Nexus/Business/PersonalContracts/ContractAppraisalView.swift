import SwiftUI

struct ContractAppraisalView: View {
    let contract: ContractInfo
    let items: [ContractItemInfo]
    @State private var isLoadingESI = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var includedResult: ESIAppraisalResult?
    @State private var requiredResult: ESIAppraisalResult?
    @State private var showFullAmount: Bool = true
    @State private var discountPercentage: Double = 100
    @State private var safeDiscountPercentage: Double = 99999
    @State private var showDiscountAlert = false
    @State private var hasBlueprint = false
    @State private var hasInsufficientOrders = false
    @State private var discountText: String = "100"
    @State private var itemDetailsCache: [Int: (name: String, iconFileName: String)] = [:]

    /// 在初始化时从UserDefaults加载设置
    init(contract: ContractInfo, items: [ContractItemInfo]) {
        self.contract = contract
        self.items = items
        let defaults = UserDefaults.standard
        // 读取设置，如果不存在则默认为true
        _showFullAmount = State(
            initialValue: defaults.object(forKey: "contractAppraisalShowFullAmount") as? Bool
                ?? true
        )
    }

    // MARK: - 物品分组

    /// 提供的物品（is_included == true）
    private var includedItems: [ContractItemInfo] {
        items.filter(\.is_included).sorted { $0.record_id < $1.record_id }
    }

    /// 索取的物品（is_included == false）
    private var requiredItems: [ContractItemInfo] {
        items.filter { !$0.is_included }.sorted { $0.record_id < $1.record_id }
    }

    var body: some View {
        List {
            // 估价选项部分
            Section {
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
                .disabled(isLoadingESI)
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
                                showFullAmount, forKey: "contractAppraisalShowFullAmount"
                            )
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
                    Text(
                        String(
                            format: NSLocalizedString("Contract_Appraisal_Discount_Message", comment: ""),
                            FormatUtil.formatPercentFrom100(10, fractionDigits: 0),
                            FormatUtil.formatPercentFrom100(90, fractionDigits: 0)
                        )
                    )
                }
            } header: {
                Text(NSLocalizedString("Contract_Appraisal_Display_Settings", comment: ""))
            }

            // 提供的物品估价结果
            if let result = includedResult {
                Section {
                    appraisalResultRows(result)
                } header: {
                    Text(NSLocalizedString("Contract_Appraisal_Included_Result", comment: ""))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if hasBlueprint {
                            Text(
                                NSLocalizedString(
                                    "Contract_Appraisal_Blueprint_Warning", comment: ""
                                )
                            )
                            .foregroundColor(.red)
                        }
                        if hasInsufficientOrders {
                            Text(
                                NSLocalizedString(
                                    "Contract_Appraisal_Insufficient_Orders_Warning", comment: ""
                                )
                            )
                            .foregroundColor(.red)
                        }
                    }
                }
            }

            // 索取的物品估价结果
            if let result = requiredResult {
                Section {
                    appraisalResultRows(result)
                } header: {
                    Text(NSLocalizedString("Contract_Appraisal_Required_Result", comment: ""))
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if hasBlueprint {
                            Text(
                                NSLocalizedString(
                                    "Contract_Appraisal_Blueprint_Warning", comment: ""
                                )
                            )
                            .foregroundColor(.red)
                        }
                        if hasInsufficientOrders {
                            Text(
                                NSLocalizedString(
                                    "Contract_Appraisal_Insufficient_Orders_Warning", comment: ""
                                )
                            )
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Contract_Appraisal_Title", comment: ""))
        .onAppear {
            loadItemDetails()
        }
        .alert(NSLocalizedString("Contract_Appraisal_Error", comment: ""), isPresented: $showError) {
            Button(NSLocalizedString("Contract_Appraisal_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(errorMessage ?? NSLocalizedString("Contract_Appraisal_Unknown_Error", comment: ""))
        }
    }

    // MARK: - 估价结果行视图

    @ViewBuilder
    private func appraisalResultRows(_ result: ESIAppraisalResult) -> some View {
        let discount = min(safeDiscountPercentage, discountPercentage) / 100
        priceRow(
            title: NSLocalizedString("Contract_Appraisal_Buy_Price", comment: ""),
            price: formatPrice(result.totalBuyPrice * discount),
            color: .red
        )
        priceRow(
            title: NSLocalizedString("Contract_Appraisal_Middle_Price", comment: ""),
            price: formatPrice(result.totalMiddlePrice * discount),
            color: .orange
        )
        priceRow(
            title: NSLocalizedString("Contract_Appraisal_Sell_Price", comment: ""),
            price: formatPrice(result.totalSellPrice * discount),
            color: .green
        )
    }

    /// 单行价格展示：标题 + 可复制价格
    private func priceRow(title: String, price: String, color: Color) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(price)
                .foregroundColor(color)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = price
                    } label: {
                        Label(
                            NSLocalizedString("Misc_Copy", comment: ""),
                            systemImage: "doc.on.doc"
                        )
                    }
                }
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - 辅助方法

    /// 根据显示设置格式化价格
    private func formatPrice(_ price: Double) -> String {
        if showFullAmount {
            return "\(FormatUtil.format(price)) ISK"
        } else {
            return "\(FormatUtil.formatISK(price))"
        }
    }

    /// 加载物品详情（名称、图标）
    private func loadItemDetails() {
        let typeIds = Set(items.map { $0.type_id })
        guard !typeIds.isEmpty else { return }

        // 内存索引取物品名称和图标
        for typeId in typeIds {
            guard let info = SDEMemoryStore.type(for: typeId) else { continue }
            itemDetailsCache[typeId] = (
                name: info.name,
                iconFileName: info.iconFilename
            )
        }
    }

    private func checkForBlueprints() -> Bool {
        // 内存索引判断是否含蓝图（categoryID = 9）
        let containsBlueprint = items.contains { item in
            SDEMemoryStore.type(for: item.type_id)?.categoryID == 9
        }
        if containsBlueprint {
            Logger.warning("Contract Appraisal: 合同包含蓝图，估价可能不准确")
        }
        return containsBlueprint
    }

    // MARK: - ESI 估价

    private func performESIAppraisal() async {
        isLoadingESI = true
        defer { isLoadingESI = false }

        // 检查是否包含蓝图
        hasBlueprint = checkForBlueprints()

        // 默认使用吉他(Jita)市场
        let regionID = MarketManager.theForgeRegionID // The Forge (Jita所在星域)
        let systemID = 30_000_142 // Jita星系ID

        // 收集所有 type_id（包含提供的和索取的），一次性加载市场订单
        let allTypeIds = Set(items.map { $0.type_id })

        let marketOrders = await MarketOrdersUtil.loadRegionOrders(
            typeIds: Array(allTypeIds),
            regionID: regionID,
            forceRefresh: true
        )

        Logger.info("ESI Appraisal: marketOrders = \(marketOrders)")

        // 预计算每个 type_id 的单价（最高买单价 / 最低卖单价）
        let priceTable = buildPriceTable(from: marketOrders, systemID: systemID)

        // 分别计算提供物品和索取物品的估价
        let included = calculateTotals(for: includedItems, using: priceTable)
        let required = requiredItems.isEmpty
            ? nil
            : calculateTotals(for: requiredItems, using: priceTable)

        await MainActor.run {
            self.includedResult = included.result
            self.requiredResult = required?.result
            // 如果任一组存在无订单物品，则标记
            self.hasInsufficientOrders = included.hasInsufficientOrders
                || (required?.hasInsufficientOrders ?? false)
        }
    }

    /// 从市场订单构建单价表：type_id → (最高买单价, 最低卖单价, 是否有订单)
    private func buildPriceTable(
        from marketOrders: [Int: [MarketOrder]],
        systemID: Int
    ) -> [Int: (unitBuy: Double, unitSell: Double, hasOrders: Bool)] {
        var table: [Int: (unitBuy: Double, unitSell: Double, hasOrders: Bool)] = [:]

        for (typeID, orders) in marketOrders {
            guard !orders.isEmpty else {
                table[typeID] = (unitBuy: 0, unitSell: 0, hasOrders: false)
                continue
            }

            // 吉他星系内的最高买单价和最低卖单价
            let unitBuy = orders
                .filter { $0.isBuyOrder && $0.systemId == systemID }
                .map(\.price)
                .max() ?? 0

            let unitSell = orders
                .filter { !$0.isBuyOrder && $0.systemId == systemID }
                .map(\.price)
                .min() ?? 0

            table[typeID] = (unitBuy: unitBuy, unitSell: unitSell, hasOrders: true)
        }

        return table
    }

    /// 根据单价表计算指定物品列表的总估价
    /// - Returns: 估价结果 + 是否存在无市场订单的物品
    private func calculateTotals(
        for items: [ContractItemInfo],
        using priceTable: [Int: (unitBuy: Double, unitSell: Double, hasOrders: Bool)]
    ) -> (result: ESIAppraisalResult, hasInsufficientOrders: Bool) {
        // 合并相同 type_id 的物品数量
        var quantities: [Int: Int64] = [:]
        for item in items {
            quantities[item.type_id] = (quantities[item.type_id] ?? 0) + Int64(item.quantity)
        }

        var totalBuyPrice: Double = 0
        var totalSellPrice: Double = 0
        var itemsWithoutOrders = 0

        for (typeID, quantity) in quantities {
            guard let priceInfo = priceTable[typeID], priceInfo.hasOrders else {
                itemsWithoutOrders += 1
                continue
            }

            totalBuyPrice += Double(quantity) * priceInfo.unitBuy
            totalSellPrice += Double(quantity) * priceInfo.unitSell
        }

        let totalMiddlePrice = (totalBuyPrice + totalSellPrice) / 2

        let result = ESIAppraisalResult(
            totalBuyPrice: totalBuyPrice,
            totalSellPrice: totalSellPrice,
            totalMiddlePrice: totalMiddlePrice
        )

        return (result, itemsWithoutOrders > 0)
    }
}

/// ESI估价结果模型
struct ESIAppraisalResult {
    let totalBuyPrice: Double
    let totalSellPrice: Double
    let totalMiddlePrice: Double
}
