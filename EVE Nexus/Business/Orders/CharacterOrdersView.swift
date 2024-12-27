import SwiftUI

struct CharacterOrdersView: View {
    let characterId: Int64
    @State private var orders: [CharacterMarketOrder] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var locationNames: [Int64: String] = [:]
    @State private var itemNames: [Int64: String] = [:]
    @State private var databaseManager = DatabaseManager()
    
    var body: some View {
        List {
            ForEach(orders) { order in
                VStack(alignment: .leading, spacing: 8) {
                    // 订单标题行
                    HStack {
                        Text(itemNames[order.typeId] ?? "Unknown Item")
                            .font(.headline)
                        Spacer()
                        Text(FormatUtil.format(order.price) + " ISK")
                            .font(.subheadline)
                            .foregroundColor(order.isBuyOrder ?? false ? .red : .green)
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
                            Image(systemName: "location")
                                .foregroundColor(.gray)
                            Text(locationNames[order.locationId] ?? "Unknown Location")
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
        .task {
            await loadOrders()
        }
    }
    
    private func loadOrders(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
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
                
                // 加载位置名称
                await loadLocationNames()
                
                // 加载物品名称
                await loadItemNames()
                
            } else {
                orders = []
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    private func loadLocationNames() async {
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
                await MainActor.run {
                    locationNames[locationId] = name
                }
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
                
                await MainActor.run {
                    locationNames[locationId] = structureInfo.name
                }
            } catch {
                Logger.error("获取建筑物信息失败 - ID: \(locationId), 错误: \(error)")
                await MainActor.run {
                    locationNames[locationId] = NSLocalizedString("Assets_Unknown_Location", comment: "")
                }
            }
        }
    }
    
    private func loadItemNames() async {
        let items = Set(orders.map { $0.typeId })
        for itemId in items {
            let query = "SELECT name FROM types WHERE type_id = ?"
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [String(itemId)]),
               let row = rows.first,
               let name = row["name"] as? String {
                await MainActor.run {
                    itemNames[itemId] = name
                }
            }
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
