import Foundation
import SwiftUI

// 定义资产类型枚举
enum WealthType: String, CaseIterable {
    case assets = "Assets"
    case implants = "Implants"
    case orders = "Orders"
    case wallet = "Wallet"
    
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
struct WealthItem: Identifiable {
    let id = UUID()
    let type: WealthType
    let value: Double
    let details: String
    
    var formattedValue: String {
        return FormatUtil.format(value)
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
        self.totalValue = Double(quantity) * value
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
            WHERE type_id IN (\(typeIds.map { String($0) }.joined(separator: ",")))
        """
        
        switch databaseManager.executeQuery(query, parameters: []) {
        case .success(let rows):
            return rows
        case .error(let error):
            Logger.error("获取物品信息失败: \(error)")
            return []
        }
    }
    
    // 加载所有财富数据
    func loadWealthData(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 1. 首先获取市场价格数据
            let prices = try await MarketPricesAPI.shared.fetchMarketPrices(forceRefresh: forceRefresh)
            marketPrices = Dictionary(uniqueKeysWithValues: prices.compactMap { price in
                guard let averagePrice = price.average_price else { return nil }
                return (price.type_id, averagePrice)
            })
            
            // 2. 获取资产数据并计算价值
            let (assetsValue, assetsCount) = try await calculateAssetsValue(forceRefresh: forceRefresh)
            
            // 3. 获取植入体数据并计算价值
            let (implantsValue, implantsCount) = try await calculateImplantsValue(forceRefresh: forceRefresh)
            
            // 4. 获取订单数据并计算价值
            let (ordersValue, ordersCount) = try await calculateOrdersValue(forceRefresh: forceRefresh)
            
            // 5. 获取钱包余额
            let walletBalance = try await CharacterWalletAPI.shared.getWalletBalance(
                characterId: characterId,
                forceRefresh: forceRefresh
            )
            
            // 6. 更新UI数据
            let items = [
                WealthItem(
                    type: .assets,
                    value: assetsValue,
                    details: String(format: NSLocalizedString("Wealth_Assets_Count", comment: ""), assetsCount)
                ),
                WealthItem(
                    type: .implants,
                    value: implantsValue,
                    details: String(format: NSLocalizedString("Wealth_Implants_Count", comment: ""), implantsCount)
                ),
                WealthItem(
                    type: .orders,
                    value: ordersValue,
                    details: String(format: NSLocalizedString("Wealth_Orders_Count", comment: ""), ordersCount)
                ),
                WealthItem(
                    type: .wallet,
                    value: walletBalance,
                    details: NSLocalizedString("Wealth_Wallet_Balance", comment: "")
                )
            ]
            
            self.wealthItems = items
            self.totalWealth = items.reduce(0) { $0 + $1.value }
            
        } catch {
            Logger.error("加载财富数据失败: \(error)")
            self.error = error
        }
    }
    
    // 计算资产价值
    private func calculateAssetsValue(forceRefresh: Bool) async throws -> (value: Double, count: Int) {
        var totalValue = 0.0
        var totalCount = 0
        
        // 获取资产树JSON
        if let jsonString = try await CharacterAssetsJsonAPI.shared.generateAssetTreeJson(
            characterId: characterId,
            forceRefresh: forceRefresh
        ), let jsonData = jsonString.data(using: .utf8) {
            // 解析JSON
            let locations = try JSONDecoder().decode([AssetTreeNode].self, from: jsonData)
            
            // 递归计算所有资产价值
            func calculateNodeValue(_ node: AssetTreeNode) {
                if let price = marketPrices[node.type_id] {
                    totalValue += price * Double(node.quantity)
                    totalCount += 1
                }
                
                if let items = node.items {
                    for item in items {
                        calculateNodeValue(item)
                    }
                }
            }
            
            // 遍历所有位置
            for location in locations {
                calculateNodeValue(location)
            }
        }
        
        return (totalValue, totalCount)
    }
    
    // 计算植入体价值
    private func calculateImplantsValue(forceRefresh: Bool) async throws -> (value: Double, count: Int) {
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
    private func calculateOrdersValue(forceRefresh: Bool) async throws -> (value: Double, count: Int) {
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
                let locations = try JSONDecoder().decode([AssetTreeNode].self, from: jsonData)
                
                // 创建一个字典来统计每种物品的数量和总价值
                var itemStats: [Int: (quantity: Int, value: Double)] = [:]
                
                func processNode(_ node: AssetTreeNode) {
                    if let price = marketPrices[node.type_id] {
                        let currentStats = itemStats[node.type_id] ?? (0, 0)
                        itemStats[node.type_id] = (
                            currentStats.quantity + node.quantity,
                            price
                        )
                    }
                    
                    if let items = node.items {
                        for item in items {
                            processNode(item)
                        }
                    }
                }
                
                // 处理所有位置
                for location in locations {
                    processNode(location)
                }
                
                // 转换为ValuedItem，排序，并只取前20个
                self.valuedAssets = itemStats.map { typeId, stats in
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
            self.valuedImplants = implantIds.compactMap { implantId in
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
                self.valuedOrders = orders.map { order in
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
} 
