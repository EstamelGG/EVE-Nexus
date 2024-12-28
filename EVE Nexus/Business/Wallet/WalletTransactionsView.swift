import SwiftUI

// 交易记录条目模型
struct WalletTransactionEntry: Codable, Identifiable {
    let client_id: Int
    let date: String
    let is_buy: Bool
    let is_personal: Bool
    let journal_ref_id: Int64
    let location_id: Int64
    let quantity: Int
    let transaction_id: Int64
    let type_id: Int
    let unit_price: Double
    
    var id: Int64 { transaction_id }
}

// 按日期分组的交易记录
struct WalletTransactionGroup: Identifiable {
    let id = UUID()
    let date: Date
    var entries: [WalletTransactionEntry]
}

// 交易记录物品信息模型
struct TransactionItemInfo {
    let name: String
    let iconFileName: String
}

@MainActor
final class WalletTransactionsViewModel: ObservableObject {
    @Published private(set) var transactionGroups: [WalletTransactionGroup] = []
    @Published var isLoading = true
    @Published var isBackgroundLoading = false
    @Published var errorMessage: String?
    
    private let characterId: Int
    let databaseManager: DatabaseManager
    private var itemInfoCache: [Int: TransactionItemInfo] = [:]
    private var locationViewCache: [Int64: LocationInfoView] = [:]  // 缓存渲染后的 LocationInfoView
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    
    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }
    
    func getItemInfo(for typeId: Int) -> TransactionItemInfo {
        // 先检查缓存
        if let cachedInfo = itemInfoCache[typeId] {
            return cachedInfo
        }
        
        // 如果缓存中没有，从数据库查询
        let result = databaseManager.executeQuery("select name, icon_filename from types where type_id = ?", parameters: [typeId])
        if case .success(let rows) = result {
            for row in rows {
                if let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String {
                    let itemInfo = TransactionItemInfo(name: name, iconFileName: iconFileName)
                    // 更新缓存
                    itemInfoCache[typeId] = itemInfo
                    return itemInfo
                }
            }
        }
        
        // 如果查询失败，返回默认值
        return TransactionItemInfo(name: "Unknown Item", iconFileName: DatabaseConfig.defaultItemIcon)
    }
    
    private func preloadLocationInfo(for entries: [WalletTransactionEntry]) {
        // 收集所有唯一的位置ID
        let uniqueLocationIds = Set(entries.map { $0.location_id })
        
        // 批量获取位置信息并创建 LocationInfoView
        for locationId in uniqueLocationIds {
            if locationViewCache[locationId] == nil {  // 如果缓存中没有才创建
                if let info = databaseManager.getStationInfo(stationID: locationId) {
                    let locationView = LocationInfoView(
                        stationName: info.stationName,
                        solarSystemName: info.solarSystemName,
                        security: info.security,
                        font: .caption,
                        textColor: .secondary
                    )
                    locationViewCache[locationId] = locationView
                }
            }
        }
    }
    
    func getLocationView(for locationId: Int64) -> LocationInfoView? {
        return locationViewCache[locationId]
    }
    
    func loadTransactionData(forceRefresh: Bool = false) async {
        let shouldShowFullscreenLoading = transactionGroups.isEmpty && !forceRefresh
        
        if shouldShowFullscreenLoading {
            isLoading = true
        } else {
            isBackgroundLoading = true
        }
        errorMessage = nil
        
        do {
            guard let jsonString = try await CharacterWalletAPI.shared.getWalletTransactions(characterId: characterId, forceRefresh: forceRefresh) else {
                throw NetworkError.invalidResponse
            }
            
            guard let jsonData = jsonString.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([WalletTransactionEntry].self, from: jsonData) else {
                throw NetworkError.invalidResponse
            }
            
            // 预加载所有位置信息
            preloadLocationInfo(for: entries)
            
            var groupedEntries: [Date: [WalletTransactionEntry]] = [:]
            for entry in entries {
                guard let date = dateFormatter.date(from: entry.date) else {
                    print("Failed to parse date: \(entry.date)")
                    continue
                }
                
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                guard let dayDate = calendar.date(from: components) else {
                    print("Failed to create date from components for: \(entry.date)")
                    continue
                }
                
                groupedEntries[dayDate, default: []].append(entry)
            }
            
            let groups = groupedEntries.map { (date, entries) -> WalletTransactionGroup in
                WalletTransactionGroup(date: date, entries: entries.sorted { $0.transaction_id > $1.transaction_id })
            }.sorted { $0.date > $1.date }
            
            self.transactionGroups = groups
            if shouldShowFullscreenLoading {
                isLoading = false
            } else {
                isBackgroundLoading = false
            }
            
        } catch {
            self.errorMessage = error.localizedDescription
            if shouldShowFullscreenLoading {
                isLoading = false
            } else {
                isBackgroundLoading = false
            }
        }
    }
}

struct WalletTransactionsView: View {
    @StateObject private var viewModel: WalletTransactionsViewModel
    
    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    init(characterId: Int, databaseManager: DatabaseManager) {
        _viewModel = StateObject(wrappedValue: WalletTransactionsViewModel(characterId: characterId, databaseManager: databaseManager))
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if viewModel.transactionGroups.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
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
                ForEach(viewModel.transactionGroups) { group in
                    Section(header: Text(displayDateFormatter.string(from: group.date))
                        .fontWeight(.bold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    ) {
                        ForEach(group.entries) { entry in
                            WalletTransactionEntryRow(entry: entry, viewModel: viewModel)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            // 立即触发刷新并返回，不等待加载完成
            Task {
                await viewModel.loadTransactionData(forceRefresh: true)
            }
            // 立即完成下拉刷新动作
            return
        }
        .task {
            if viewModel.transactionGroups.isEmpty {
                await viewModel.loadTransactionData()
            }
        }
        .navigationTitle(NSLocalizedString("Main_Market_Transactions", comment: ""))
        .toolbar {
            if viewModel.isBackgroundLoading {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
    }
}

struct WalletTransactionEntryRow: View {
    let entry: WalletTransactionEntry
    let viewModel: WalletTransactionsViewModel
    @State private var itemInfo: TransactionItemInfo?
    @State private var itemIcon: Image?
    
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
        NavigationLink(destination: MarketItemDetailView(databaseManager: viewModel.databaseManager, itemID: entry.type_id)) {
            VStack(alignment: .leading, spacing: 4) {
                // 物品信息行
                HStack(spacing: 12) {
                    // 物品图标
                    if let icon = itemIcon {
                        icon
                            .resizable()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 36, height: 36)
                    }
                    
                    VStack(alignment: .leading) {
                        Text(itemInfo?.name ?? NSLocalizedString("Main_Market_Transactions_Loading", comment: ""))
                            .font(.body)
                        Text("\(FormatUtil.format(entry.unit_price * Double(entry.quantity))) ISK")
                            .foregroundColor(entry.is_buy ? .red : .green)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                
                // 交易地点
                if let locationView = viewModel.getLocationView(for: entry.location_id) {
                    locationView
                        .lineLimit(1)
                }
                
                // 交易详细信息
                VStack(alignment: .leading, spacing: 4) {
                    // 交易时间
                    HStack {
                        if let date = dateFormatter.date(from: entry.date) {
                            Text("\(displayDateFormatter.string(from: date)) \(timeFormatter.string(from: date))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        // 交易类型和数量
                        Text("\(entry.is_buy ? NSLocalizedString("Main_Market_Transactions_Buy", comment: "") : NSLocalizedString("Main_Market_Transactions_Sell", comment: "")) - \(entry.quantity) × \(FormatUtil.format(entry.unit_price)) ISK")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .task {
            // 加载物品信息
            itemInfo = viewModel.getItemInfo(for: entry.type_id)
            // 加载图标
            if let itemInfo = itemInfo {
                itemIcon = IconManager.shared.loadImage(for: itemInfo.iconFileName)
            }
        }
    }
}
