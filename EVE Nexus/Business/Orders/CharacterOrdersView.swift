import SwiftUI

// 订单物品信息模型
struct OrderItemInfo {
    let name: String
    let iconFileName: String
}

// 位置信息模型
struct OrderLocationInfo {
    let stationName: String
    let solarSystemName: String
    let security: Double
}

struct CharacterOrdersView: View {
    let characterId: Int64
    @State private var orders: [CharacterMarketOrder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var locationNames: [Int64: String] = [:]
    @State private var itemInfoCache: [Int64: OrderItemInfo] = [:]
    @State private var locationInfoCache: [Int64: OrderLocationInfo] = [:]
    @StateObject private var databaseManager = DatabaseManager()
    @State private var showBuyOrders = false
    @State private var isDataReady = false
    
    private var filteredOrders: [CharacterMarketOrder] {
        orders.filter { $0.isBuyOrder ?? false == showBuyOrders }
    }
    
    // 初始化订单显示类型
    private func initializeOrderType() {
        let sellOrdersCount = orders.filter { !($0.isBuyOrder ?? false) }.count
        let buyOrdersCount = orders.filter { $0.isBuyOrder ?? false }.count
        
        if sellOrdersCount > 0 {
            // 如果有出售订单，优先显示出售订单
            showBuyOrders = false
        } else if buyOrdersCount > 0 {
            // 如果只有收购订单，显示收购订单
            showBuyOrders = true
        }
        // 如果都没有订单，默认显示出售订单（showBuyOrders = false）
    }

    var body: some View {
        VStack(spacing: 0) {
            // 买卖单切换按钮
            TabView(selection: $showBuyOrders) {
                OrderListView(
                    orders: orders.filter { !($0.isBuyOrder ?? false) },
                    itemInfoCache: itemInfoCache,
                    locationInfoCache: locationInfoCache,
                    isLoading: isLoading,
                    isDataReady: isDataReady
                )
                .tag(false)
                
                OrderListView(
                    orders: orders.filter { $0.isBuyOrder ?? false },
                    itemInfoCache: itemInfoCache,
                    locationInfoCache: locationInfoCache,
                    isLoading: isLoading,
                    isDataReady: isDataReady
                )
                .tag(true)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Picker("Order Type", selection: $showBuyOrders) {
                        Text("\(NSLocalizedString("Orders_Sell", comment: "")) (\(orders.filter { !($0.isBuyOrder ?? false) }.count))").tag(false)
                        Text("\(NSLocalizedString("Orders_Buy", comment: "")) (\(orders.filter { $0.isBuyOrder ?? false }.count))").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .refreshable {
            await loadOrders(forceRefresh: true)
        }
        .alert(NSLocalizedString("Error", comment: ""), isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .navigationTitle(NSLocalizedString("Main_Market_Orders", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadOrders()
        }
    }
    
    // 订单列表视图
    private struct OrderListView: View {
        let orders: [CharacterMarketOrder]
        let itemInfoCache: [Int64: OrderItemInfo]
        let locationInfoCache: [Int64: OrderLocationInfo]
        let isLoading: Bool
        let isDataReady: Bool
        
        var body: some View {
            List {
                if isLoading || !isDataReady {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                } else if orders.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                                Text(NSLocalizedString("Orders_No_Data", comment: ""))
                                .foregroundColor(.gray)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                    .listSectionSpacing(.compact)
                } else {
                    Section {
                        ForEach(orders) { order in
                            OrderRow(
                                order: order,
                                itemInfo: itemInfoCache[order.typeId],
                                locationInfo: locationInfoCache[order.locationId]
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }
                    }
                    .listSectionSpacing(.compact)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.visible)
        }
    }
    
    // 将订单行提取为单独的视图组件
    private struct OrderRow: View {
        let order: CharacterMarketOrder
        let itemInfo: OrderItemInfo?
        let locationInfo: OrderLocationInfo?
        @StateObject private var databaseManager = DatabaseManager()
        
        private func formatSecurity(_ security: Double) -> String {
            String(format: "%.1f", security)
        }
        
        private func calculateRemainingTime() -> String {
            guard let issuedDate = dateFormatter.date(from: order.issued) else {
                return ""
            }
            
            let expirationDate = issuedDate.addingTimeInterval(TimeInterval(order.duration * 24 * 3600))
            let remainingTime = expirationDate.timeIntervalSinceNow
            
            if remainingTime <= 0 {
                return NSLocalizedString("Orders_Expired", comment: "")
            }
            
            let days = Int(remainingTime) / (24 * 3600)
            let hours = (Int(remainingTime) % (24 * 3600)) / 3600
            let minutes = (Int(remainingTime) % 3600) / 60
            
            if days > 0 {
                if hours > 0 {
                    return String(format: NSLocalizedString("Orders_Remaining_Days_Hours", comment: ""), days, hours)
                } else {
                    return String(format: NSLocalizedString("Orders_Remaining_Days", comment: ""), days)
                }
            } else if hours > 0 {
                if minutes > 0 {
                    return String(format: NSLocalizedString("Orders_Remaining_Hours_Minutes", comment: ""), hours, minutes)
                } else {
                    return String(format: NSLocalizedString("Orders_Remaining_Hours", comment: ""), hours)
                }
            } else {
                return String(format: NSLocalizedString("Orders_Remaining_Minutes", comment: ""), minutes)
            }
        }
        
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")!
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }()
        private let displayDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")!
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }()
        
        private let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            formatter.timeZone = TimeZone(identifier: "UTC")!
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }()
        
        var body: some View {
            NavigationLink(destination: MarketItemDetailView(databaseManager: databaseManager, itemID: Int(order.typeId))) {
                VStack(alignment: .leading, spacing: 8) {
                    // 订单标题行
                    HStack(spacing: 12) {
                        // 物品图标
                        if let itemInfo = itemInfo {
                            IconManager.shared.loadImage(for: itemInfo.iconFileName)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 36, height: 36)
                        }
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text(itemInfo?.name ?? "Unknown Item")
                                    .font(.headline)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(order.volumeRemain)/\(order.volumeTotal)")
                            }
                            Text(FormatUtil.format(order.price) + " ISK")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(order.isBuyOrder ?? false ? .red : .green)
                        }
                    }
                    
                    // 订单详细信息
                    VStack(alignment: .leading, spacing: 4) {
                        // 位置信息
                        if let locationInfo = locationInfo {
                            LocationInfoView(
                                stationName: locationInfo.stationName,
                                solarSystemName: locationInfo.solarSystemName,
                                security: locationInfo.security
                            )
                        } else {
                            LocationInfoView(
                                stationName: nil,
                                solarSystemName: nil,
                                security: nil
                            )
                        }
                        
                        // 时间信息
                        HStack {
                            if let date = dateFormatter.date(from: order.issued) {
                                Text("\(displayDateFormatter.string(from: date)) \(timeFormatter.string(from: date)) (UTC+0)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(calculateRemainingTime())
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        
        private func formatDate(_ dateString: String) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            
            guard let date = formatter.date(from: dateString) else {
                return dateString
            }
            
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
    }
    
    private func loadOrders(forceRefresh: Bool = false) async {
        isLoading = true
        isDataReady = false
        locationNames.removeAll()
        itemInfoCache.removeAll()
        locationInfoCache.removeAll()
        
        do {
            // 获取订单数据
            if let jsonString = try await CharacterMarketAPI.shared.getMarketOrders(
                characterId: characterId,
                forceRefresh: forceRefresh
            ) {
                // 解析JSON数据
                let jsonData = jsonString.data(using: .utf8)!
                let decoder = JSONDecoder()
                orders = try decoder.decode([CharacterMarketOrder].self, from: jsonData)
                
                // 同步加载所有信息
                await loadAllInformation()
                
                // 初始化订单显示类型
                initializeOrderType()
                
                // 所有数据加载完成
                isDataReady = true
            } else {
                orders = []
                isDataReady = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            orders = []
            isDataReady = true
        }
        
        isLoading = false
    }
    
    private func loadAllInformation() async {
        // 1. 加载所有物品信息
        let items = Set(orders.map { $0.typeId })
        for itemId in items {
            let query = """
                SELECT name, icon_filename
                FROM types
                WHERE type_id = ?
            """
            
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [String(itemId)]),
               let row = rows.first,
               let name = row["name"] as? String,
               let iconFileName = row["icon_filename"] as? String {
                itemInfoCache[itemId] = OrderItemInfo(name: name, iconFileName: iconFileName)
            }
        }
        
        // 2. 加载所有位置信息
        let locations = Set(orders.map { $0.locationId })
        for locationId in locations {
            // 先尝试从数据库获取空间站信息
            let query = """
                SELECT s.stationName, ss.solarSystemName, u.system_security as security
                FROM stations s
                JOIN solarSystems ss ON s.solarSystemID = ss.solarSystemID
                JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                WHERE s.stationID = ?
            """
            
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [String(locationId)]),
               let row = rows.first,
               let stationName = row["stationName"] as? String,
               let solarSystemName = row["solarSystemName"] as? String,
               let security = row["security"] as? Double {
                locationInfoCache[locationId] = OrderLocationInfo(
                    stationName: stationName,
                    solarSystemName: solarSystemName,
                    security: security
                )
                continue
            }
            
            // 如果数据库中找不到，说明可能是玩家建筑物，通过API获取
            do {
                let structureInfo = try await UniverseStructureAPI.shared.fetchStructureInfo(
                    structureId: locationId,
                    characterId: Int(characterId)
                )
                
                // 获取星系信息
                let systemQuery = """
                    SELECT ss.solarSystemName, u.system_security as security
                    FROM solarSystems ss
                    JOIN universe u ON u.solarsystem_id = ss.solarSystemID
                    WHERE ss.solarSystemID = ?
                """
                
                if case .success(let rows) = databaseManager.executeQuery(systemQuery, parameters: [String(structureInfo.solar_system_id)]),
                   let row = rows.first,
                   let solarSystemName = row["solarSystemName"] as? String,
                   let security = row["security"] as? Double {
                    locationInfoCache[locationId] = OrderLocationInfo(
                        stationName: structureInfo.name,
                        solarSystemName: solarSystemName,
                        security: security
                    )
                }
            } catch {
                Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
            }
        }
    }
}
