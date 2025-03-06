import SwiftUI

struct ContractAppraisalView: View {
    let contract: ContractInfo
    let items: [ContractItemInfo]
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingJanice = false
    @State private var isLoadingESI = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var janiceResult: JaniceResult?
    @State private var esiResult: ESIAppraisalResult?
    
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
            
            // Janice估价结果部分
            if let result = janiceResult {
                Section {
                    // 买入价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Buy_Price", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.formatISK(result.immediatePrices.totalBuyPrice)) ISK")
                            .foregroundColor(.red)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // 中间价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Middle_Price", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.formatISK(result.immediatePrices.totalSplitPrice)) ISK")
                            .foregroundColor(.orange)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // 卖出价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Sell_Price", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.formatISK(result.immediatePrices.totalSellPrice)) ISK")
                            .foregroundColor(.green)
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
                    Text(result.name ?? String(format: NSLocalizedString("Contract_Appraisal_Result", comment: ""), result.pricerMarket.name))
                }
            }
            
            // ESI估价结果部分
            if let result = esiResult {
                Section {
                    // 买入价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Buy_Price", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.formatISK(result.totalBuyPrice)) ISK")
                            .foregroundColor(.red)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // 中间价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Middle_Price", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.formatISK(result.totalMiddlePrice)) ISK")
                            .foregroundColor(.orange)
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    // 卖出价格行
                    HStack {
                        Text(NSLocalizedString("Contract_Appraisal_Sell_Price", comment: ""))
                        Spacer()
                        Text("\(FormatUtil.formatISK(result.totalSellPrice)) ISK")
                            .foregroundColor(.green)
                            .font(.system(.body, design: .monospaced))
                    }
                } header: {
                    Text(NSLocalizedString("Contract_Appraisal_ESI_Result", comment: "吉他市场估价"))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Contract_Appraisal_Title", comment: ""))
        .alert(NSLocalizedString("Contract_Appraisal_Error", comment: ""), isPresented: $showError) {
            Button(NSLocalizedString("Contract_Appraisal_OK", comment: ""), role: .cancel) {}
        } message: {
            Text(errorMessage ?? NSLocalizedString("Contract_Appraisal_Unknown_Error", comment: ""))
        }
    }
    
    private func performJaniceAppraisal() async {
        isLoadingJanice = true
        defer { isLoadingJanice = false }
        
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
                throw NSError(domain: "JaniceMarketAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: String(format: NSLocalizedString("Contract_Appraisal_Parse_Failed", comment: ""), "\(result)")])
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func performESIAppraisal() async {
        isLoadingESI = true
        defer { isLoadingESI = false }
        
        // 默认使用吉他(Jita)市场
        let regionID = 10000002 // The Forge (Jita所在星域)
        let systemID = 30000142 // Jita系统ID
        
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
            var hasInsufficientStock = false
            
            for (typeID, quantity) in itemsDict {
                guard let orders = marketOrders[typeID] else { continue }
                
                // 过滤买单和卖单
                let buyOrders = orders.filter { $0.isBuyOrder && $0.systemId == systemID }
                    .sorted(by: { $0.price > $1.price }) // 买单从高到低排序
                
                let sellOrders = orders.filter { !$0.isBuyOrder && $0.systemId == systemID }
                    .sorted(by: { $0.price < $1.price }) // 卖单从低到高排序
                
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
                
                // 检查库存是否充足
                if remainingBuyQuantity > 0 || remainingSellQuantity > 0 {
                    hasInsufficientStock = true
                }
                
                // 计算平均买价和卖价
                let avgBuyPrice = availableBuyQuantity > 0 ? totalBuyItemPrice / Double(availableBuyQuantity) : 0
                let avgSellPrice = availableSellQuantity > 0 ? totalSellItemPrice / Double(availableSellQuantity) : 0
                
                // 累加总价
                totalBuyPrice += avgBuyPrice * Double(quantity)
                totalSellPrice += avgSellPrice * Double(quantity)
            }
            
            // 计算中间价格
            let totalMiddlePrice = (totalBuyPrice + totalSellPrice) / 2
            
            // 创建ESI估价结果
            let result = ESIAppraisalResult(
                totalBuyPrice: totalBuyPrice,
                totalSellPrice: totalSellPrice,
                totalMiddlePrice: totalMiddlePrice,
                hasInsufficientStock: hasInsufficientStock
            )
            
            await MainActor.run {
                self.esiResult = result
            }
            
        }
    }
}

// ESI估价结果模型
struct ESIAppraisalResult {
    let totalBuyPrice: Double
    let totalSellPrice: Double
    let totalMiddlePrice: Double
    let hasInsufficientStock: Bool
} 
