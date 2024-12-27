import SwiftUI

// 订单物品信息模型
struct OrderItemInfo {
    let name: String
    let iconFileName: String
}

struct CharacterOrdersView: View {
    let characterId: Int64
    @State private var orders: [CharacterMarketOrder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var locationNames: [Int64: String] = [:]
    @State private var itemInfoCache: [Int64: OrderItemInfo] = [:]
    @StateObject private var databaseManager = DatabaseManager()
    @State private var showBuyOrders = false
    @State private var isDataReady = false
    
    private var filteredOrders: [CharacterMarketOrder] {
        orders.filter { $0.isBuyOrder ?? false == showBuyOrders }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 买卖单切换按钮
            Picker("Order Type", selection: $showBuyOrders) {
                Text(NSLocalizedString("Orders_Sell", comment: "")).tag(false)
                Text(NSLocalizedString("Orders_Buy", comment: "")).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
            
            List {
                if isLoading || !isDataReady {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if filteredOrders.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 30))
                                    .foregroundColor(.gray)
                                Text(showBuyOrders ? 
                                    NSLocalizedString("Orders_No_Buy_Orders", comment: "") :
                                    NSLocalizedString("Orders_No_Sell_Orders", comment: ""))
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            Spacer()
                        }
                    }
                } else {
                    Section {
                        ForEach(filteredOrders) { order in
                            OrderRow(order: order, itemInfo: itemInfoCache[order.typeId], locationName: locationNames[order.locationId])
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
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
    
    // 将订单行提取为单独的视图组件
    private struct OrderRow: View {
        let order: CharacterMarketOrder
        let itemInfo: OrderItemInfo?
        let locationName: String?
        
        var body: some View {
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
                        Text(itemInfo?.name ?? "Unknown Item")
                            .font(.headline)
                            .lineLimit(1)
                        Text(FormatUtil.format(order.price) + " ISK")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(order.isBuyOrder ?? false ? .red : .green)
                    }
                }
                
                // 订单详细信息
                VStack(alignment: .leading, spacing: 4) {
                    // 数量信息
                    HStack {
                        Text("\(order.volumeRemain)/\(order.volumeTotal)")
                            .font(.subheadline)
                        Text(NSLocalizedString("Orders_Remaining", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    
                    // 位置信息
                    HStack {
                        Text(locationName ?? "Unknown Location")
                            .font(.subheadline)
                    }
                    
                    // 订单类型和范围
                    HStack {
                        Text(order.isBuyOrder ?? false ? NSLocalizedString("Orders_Buy", comment: "") : NSLocalizedString("Orders_Sell", comment: ""))
                            .font(.caption)
                            .padding(4)
                            .background(order.isBuyOrder ?? false ? Color.blue.opacity(0.2) : Color.green.opacity(0.2))
                            .cornerRadius(4)
                        
                        Text(order.range.capitalized)
                            .font(.caption)
                            .padding(4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                        
                        if order.isCorporation {
                            Text(NSLocalizedString("Orders_Corp", comment: ""))
                                .font(.caption)
                                .padding(4)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    // 时间信息
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(.gray)
                        Text(formatDate(order.issued))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.vertical, 4)
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
                SELECT stationName
                FROM stations
                WHERE stationID = ?
            """
            
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [String(locationId)]),
               let row = rows.first,
               let name = row["stationName"] as? String {
                locationNames[locationId] = name
                continue
            }
            
            // 如果数据库中找不到，说明可能是玩家建筑物，通过API获取
            do {
                let urlString = "https://esi.evetech.net/latest/universe/structures/\(locationId)/?datasource=tranquility"
                guard let url = URL(string: urlString) else { continue }
                
                let data = try await NetworkManager.shared.fetchDataWithToken(
                    from: url,
                    characterId: Int(characterId),
                    headers: [
                        "Accept": "application/json",
                        "Content-Type": "application/json"
                    ]
                )
                
                struct StructureInfo: Codable {
                    let name: String
                    let solar_system_id: Int64
                }
                
                let structureInfo = try JSONDecoder().decode(StructureInfo.self, from: data)
                locationNames[locationId] = structureInfo.name
            } catch {
                Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
                locationNames[locationId] = NSLocalizedString("Assets_Unknown_Location", comment: "")
            }
        }
    }
}
