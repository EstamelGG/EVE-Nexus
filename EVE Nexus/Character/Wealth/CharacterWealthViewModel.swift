import Foundation
import SwiftUI

// 定义资产类型枚举
enum WealthType: String, CaseIterable {
    case wallet = "Wallet"  // 钱包余额
    case assets = "Assets"  // 资产
    case implants = "Implants"  // 植入体
    case orders = "Orders"  // 市场订单

    var sortOrder: Int {
        switch self {
        case .wallet: return 0
        case .assets: return 1
        case .implants: return 2
        case .orders: return 3
        }
    }

    var icon: String {
        switch self {
        case .assets:
            return "assets"
        case .implants:
            return "augmentations"
        case .orders:
            return "marketdeliveries"
        case .wallet:
            return "wallet"
        }
    }
}

// 定义资产项结构
struct WealthItem: Identifiable, Equatable {
    let id: UUID
    let type: WealthType
    let value: Double
    let details: String

    init(type: WealthType, value: Double, details: String) {
        id = UUID()
        self.type = type
        self.value = value
        self.details = details
    }

    var formattedValue: String {
        return FormatUtil.format(value)
    }

    static func == (lhs: WealthItem, rhs: WealthItem) -> Bool {
        // 只比较实际内容，忽略id
        return lhs.type == rhs.type && lhs.value == rhs.value && lhs.details == rhs.details
    }
}

// 定义高价值物品结构
struct ValuedItem {
    let typeId: Int
    let quantity: Int
    let value: Double
    let totalValue: Double

    init(typeId: Int, quantity: Int, value: Double) {
        self.typeId = typeId
        self.quantity = quantity
        self.value = value
        totalValue = Double(quantity) * value
    }
}

@MainActor
class CharacterWealthViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var wealthItems: [WealthItem] = []
    @Published var totalWealth: Double = 0

    // 高价值物品列表
    @Published var valuedAssets: [ValuedItem] = []
    @Published var valuedImplants: [ValuedItem] = []
    @Published var valuedOrders: [ValuedItem] = []
    @Published var isLoadingDetails = false

    private let characterId: Int
    private var marketPrices: [Int: Double] = [:]
    private let databaseManager = DatabaseManager()

    init(characterId: Int) {
        self.characterId = characterId
    }

    // 获取多个物品的信息
    func getItemsInfo(typeIds: [Int]) -> [[String: Any]] {
        if typeIds.isEmpty { return [] }

        let query = """
                SELECT type_id, name, icon_filename 
                FROM types 
                WHERE type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ",")))
            """

        switch databaseManager.executeQuery(query, parameters: []) {
        case let .success(rows):
            return rows
        case let .error(error):
            Logger.error("获取物品信息失败: \(error)")
            return []
        }
    }

    // 加载所有财富数据
    func loadWealthData(forceRefresh: Bool = false, onTypeLoaded: @escaping (WealthType) -> Void)
        async
    {
        isLoading = true
        wealthItems.removeAll()
        defer { isLoading = false }

        do {
            // 1. 首先获取市场价格数据
            let prices = try await MarketPricesAPI.shared.fetchMarketPrices(
                forceRefresh: forceRefresh)
            marketPrices = Dictionary(
                uniqueKeysWithValues: prices.compactMap { price in
                    guard let averagePrice = price.average_price else { return nil }
                    return (price.type_id, averagePrice)
                })

            // 2. 获取钱包余额（最快，所以先加载）
            let walletBalance = try await CharacterWalletAPI.shared.getWalletBalance(
                characterId: characterId,
                forceRefresh: forceRefresh
            )
            addWealthItem(
                type: .wallet, value: walletBalance,
                details: NSLocalizedString("Wealth_Wallet_Balance", comment: "")
            )
            onTypeLoaded(.wallet)

            // 3. 使用 TaskGroup 并行加载其他数据
            try await withThrowingTaskGroup(of: (WealthType, Double, Int).self) { group in
                // 添加资产计算任务
                group.addTask {
                    let result = try await self.calculateAssetsValue(forceRefresh: forceRefresh)
                    return (.assets, result.value, result.count)
                }

                // 添加植入体计算任务
                group.addTask {
                    let result = try await self.calculateImplantsValue(forceRefresh: forceRefresh)
                    return (.implants, result.value, result.count)
                }

                // 添加订单计算任务
                group.addTask {
                    let result = try await self.calculateOrdersValue(forceRefresh: forceRefresh)
                    return (.orders, result.value, result.count)
                }

                // 处理每个完成的任务
                for try await (type, value, count) in group {
                    let details = String(
                        format: NSLocalizedString("Wealth_\(type.rawValue)_Count", comment: ""),
                        count
                    )
                    addWealthItem(type: type, value: value, details: details)
                    onTypeLoaded(type)
                }
            }

            // 4. 更新总资产
            updateTotalWealth()

        } catch {
            Logger.error("加载财富数据失败: \(error)")
            self.error = error
        }
    }

    private func addWealthItem(type: WealthType, value: Double, details: String) {
        let item = WealthItem(type: type, value: value, details: details)
        wealthItems.append(item)
        // 每次添加后按照固定顺序排序
        wealthItems.sort { $0.type.sortOrder < $1.type.sortOrder }
    }

    private func updateTotalWealth() {
        totalWealth = wealthItems.reduce(0) { $0 + $1.value }
    }

    // 计算资产价值
    private func calculateAssetsValue(forceRefresh: Bool) async throws -> (
        value: Double, count: Int
    ) {
        var totalValue = 0.0
        var totalCount = 0

        // 获取资产树JSON
        if let jsonString = try await CharacterAssetsJsonAPI.shared.generateAssetTreeJson(
            characterId: characterId,
            forceRefresh: forceRefresh
        ), let jsonData = jsonString.data(using: .utf8) {
            // 解析JSON
            let wrapper = try JSONDecoder().decode(AssetTreeWrapper.self, from: jsonData)
            let locations = wrapper.assetsTree

            // 递归计算所有资产价值
            func calculateNodeValue(_ node: AssetTreeNode, isTopLevel: Bool = false) {
                // 如果不是顶层节点，则计算价值
                if !isTopLevel, let price = marketPrices[node.type_id] {
                    totalValue += price * Double(node.quantity)
                    totalCount += 1
                }

                // 递归处理子节点
                if let items = node.items {
                    for item in items {
                        calculateNodeValue(item)
                    }
                }
            }

            // 遍历所有位置，标记为顶层节点
            for location in locations {
                calculateNodeValue(location, isTopLevel: true)
            }
        }

        return (totalValue, totalCount)
    }

    // 计算植入体价值
    private func calculateImplantsValue(forceRefresh: Bool) async throws -> (
        value: Double, count: Int
    ) {
        var totalValue = 0.0
        var implantIds = Set<Int>()

        // 1. 获取当前植入体并添加到集合中
        let currentImplants = try await CharacterImplantsAPI.shared.fetchCharacterImplants(
            characterId: characterId,
            forceRefresh: forceRefresh
        )
        implantIds.formUnion(currentImplants)

        // 2. 获取克隆体植入体
        let cloneInfo = try await CharacterClonesAPI.shared.fetchCharacterClones(
            characterId: characterId,
            forceRefresh: forceRefresh
        )

        // 添加所有克隆体的植入体
        for clone in cloneInfo.jump_clones {
            implantIds.formUnion(clone.implants)
        }

        // 计算总价值
        for implantId in implantIds {
            if let price = marketPrices[implantId] {
                totalValue += price
            }
        }

        return (totalValue, implantIds.count)
    }

    // 计算订单价值
    private func calculateOrdersValue(forceRefresh: Bool) async throws -> (
        value: Double, count: Int
    ) {
        var totalValue = 0.0
        var orderCount = 0

        if let jsonString = try await CharacterMarketAPI.shared.getMarketOrders(
            characterId: Int64(characterId),
            forceRefresh: forceRefresh
        ), let jsonData = jsonString.data(using: .utf8) {
            let orders = try JSONDecoder().decode([CharacterMarketOrder].self, from: jsonData)

            for order in orders {
                let orderValue = Double(order.volumeRemain) * order.price
                if order.isBuyOrder ?? false {
                    // 买单：订单上预付的金额也算作资产
                    totalValue += orderValue
                } else {
                    // 卖单：预期获得的金额算作正资产
                    totalValue += orderValue
                }
            }
            orderCount = orders.count
        }

        return (totalValue, orderCount)
    }

    // 加载资产详情
    func loadAssetDetails() async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            if let jsonString = try await CharacterAssetsJsonAPI.shared.generateAssetTreeJson(
                characterId: characterId,
                forceRefresh: false
            ), let jsonData = jsonString.data(using: .utf8) {
                let wrapper = try JSONDecoder().decode(AssetTreeWrapper.self, from: jsonData)
                let locations = wrapper.assetsTree

                // 创建一个字典来统计每种物品的数量和总价值
                var itemStats: [Int: (quantity: Int, value: Double)] = [:]

                func processNode(_ node: AssetTreeNode, isTopLevel: Bool = false) {
                    // 如果不是顶层节点，则计算价值
                    if !isTopLevel, let price = marketPrices[node.type_id] {
                        let currentStats = itemStats[node.type_id] ?? (0, 0)
                        itemStats[node.type_id] = (
                            currentStats.quantity + node.quantity,
                            price
                        )
                    }

                    // 递归处理子节点
                    if let items = node.items {
                        for item in items {
                            processNode(item)
                        }
                    }
                }

                // 处理所有位置，标记为顶层节点
                for location in locations {
                    processNode(location, isTopLevel: true)
                }

                // 转换为ValuedItem，排序，并只取前20个
                valuedAssets = itemStats.map { typeId, stats in
                    ValuedItem(typeId: typeId, quantity: stats.quantity, value: stats.value)
                }
                .sorted { $0.totalValue > $1.totalValue }
                .prefix(20)
                .map { $0 }
            }
        } catch {
            Logger.error("加载资产详情失败: \(error)")
            self.error = error
        }
    }

    // 加载植入体详情
    func loadImplantDetails() async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            var implantIds = Set<Int>()

            // 获取当前植入体
            let currentImplants = try await CharacterImplantsAPI.shared.fetchCharacterImplants(
                characterId: characterId,
                forceRefresh: false
            )
            implantIds.formUnion(currentImplants)

            // 获取克隆体植入体
            let cloneInfo = try await CharacterClonesAPI.shared.fetchCharacterClones(
                characterId: characterId,
                forceRefresh: false
            )

            for clone in cloneInfo.jump_clones {
                implantIds.formUnion(clone.implants)
            }

            // 转换为ValuedItem，排序，并只取前20个
            valuedImplants = implantIds.compactMap { implantId in
                guard let price = marketPrices[implantId] else { return nil }
                return ValuedItem(typeId: implantId, quantity: 1, value: price)
            }
            .sorted { $0.totalValue > $1.totalValue }
            .prefix(20)
            .map { $0 }

        } catch {
            Logger.error("加载植入体详情失败: \(error)")
            self.error = error
        }
    }

    // 加载订单详情
    func loadOrderDetails() async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            if let jsonString = try await CharacterMarketAPI.shared.getMarketOrders(
                characterId: Int64(characterId),
                forceRefresh: false
            ), let jsonData = jsonString.data(using: .utf8) {
                let orders = try JSONDecoder().decode([CharacterMarketOrder].self, from: jsonData)

                // 转换为ValuedItem，排序，并只取前20个
                valuedOrders = orders.map { order in
                    ValuedItem(
                        typeId: Int(order.typeId),
                        quantity: order.volumeRemain,
                        value: order.price
                    )
                }
                .sorted { $0.totalValue > $1.totalValue }
                .prefix(20)
                .map { $0 }
            }
        } catch {
            Logger.error("加载订单详情失败: \(error)")
            self.error = error
        }
    }

    // 获取无市场价格的物品
    func getItemsWithoutPrice() async -> [WealthDetailView.NoMarketPriceItem] {
        var itemsWithoutPrice: [WealthDetailView.NoMarketPriceItem] = []

        do {
            // 获取资产树JSON
            if let jsonString = try await CharacterAssetsJsonAPI.shared.generateAssetTreeJson(
                characterId: characterId,
                forceRefresh: false
            ), let jsonData = jsonString.data(using: .utf8) {
                let wrapper = try JSONDecoder().decode(AssetTreeWrapper.self, from: jsonData)
                let locations = wrapper.assetsTree

                // 创建一个字典来统计每种物品的数量
                var itemStats: [Int: Int] = [:]

                func processNode(_ node: AssetTreeNode, isTopLevel: Bool = false) {
                    // 如果不是顶层节点，且在市场价格中找不到，则添加到统计
                    if !isTopLevel && marketPrices[node.type_id] == nil {
                        itemStats[node.type_id, default: 0] += node.quantity
                    }

                    // 递归处理子节点
                    if let items = node.items {
                        for item in items {
                            processNode(item)
                        }
                    }
                }

                // 处理所有位置
                for location in locations {
                    processNode(location, isTopLevel: true)
                }

                // 获取物品信息
                let typeIds = Array(itemStats.keys)
                let itemInfos = getItemsInfo(typeIds: typeIds)

                // 转换为 NoMarketPriceItem
                for (typeId, quantity) in itemStats {
                    if let info = itemInfos.first(where: { ($0["type_id"] as? Int) == typeId }) {
                        let item = WealthDetailView.NoMarketPriceItem(
                            id: typeId,
                            typeId: typeId,
                            quantity: quantity,
                            name: info["name"] as? String ?? "Unknown Item",
                            iconFileName: info["icon_filename"] as? String ?? ""
                        )
                        itemsWithoutPrice.append(item)
                    }
                }
            }
        } catch {
            Logger.error("获取无市场价格物品失败: \(error)")
        }

        // 按数量排序并只取前20个
        return
            itemsWithoutPrice
            .sorted { $0.quantity > $1.quantity }
            .prefix(20)
            .map { $0 }
    }
}
