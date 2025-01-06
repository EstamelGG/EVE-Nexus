import SwiftUI

// 挖矿记录条目模型
struct MiningLedgerEntry: Codable {
    let date: String
    let quantity: Int
    let solar_system_id: Int
    let type_id: Int
}

// 按月份分组的挖矿记录
struct MiningMonthGroup: Identifiable {
    let id = UUID()
    let yearMonth: Date
    var entries: [MiningItemSummary]
}

// 每种矿石的汇总信息
struct MiningItemSummary: Identifiable {
    let id: Int  // type_id
    let name: String
    let iconFileName: String
    var totalQuantity: Int
}

@MainActor
final class MiningLedgerViewModel: ObservableObject {
    @Published private(set) var monthGroups: [MiningMonthGroup] = []
    @Published var isLoading = true
    @Published var isBackgroundLoading = false
    @Published var errorMessage: String?
    
    private let characterId: Int
    let databaseManager: DatabaseManager
    private var itemInfoCache: [Int: (name: String, iconFileName: String)] = [:]
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
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
    
    func getItemInfo(for typeId: Int) -> (name: String, iconFileName: String) {
        // 先检查缓存
        if let cachedInfo = itemInfoCache[typeId] {
            return cachedInfo
        }
        
        // 如果缓存中没有，从数据库查询
        let result = databaseManager.executeQuery(
            "SELECT name, icon_filename FROM types WHERE type_id = ?",
            parameters: [typeId]
        )
        
        if case .success(let rows) = result,
           let row = rows.first,
           let name = row["name"] as? String,
           let iconFileName = row["icon_filename"] as? String {
            let info = (name: name, iconFileName: iconFileName)
            itemInfoCache[typeId] = info
            return info
        }
        
        return (name: "Unknown Item", iconFileName: DatabaseConfig.defaultItemIcon)
    }
    
    func loadMiningData(forceRefresh: Bool = false) async {
        let shouldShowFullscreenLoading = monthGroups.isEmpty && !forceRefresh
        
        if shouldShowFullscreenLoading {
            isLoading = true
        }
        isBackgroundLoading = true
        errorMessage = nil
        
        do {
            let entries = try await CharacterMiningAPI.shared.getMiningLedger(
                characterId: characterId,
                forceRefresh: forceRefresh
            )
            
            Logger.debug("获取到挖矿记录：\(entries.count)条")
            
            // 按月份和矿石类型分组
            var groupedByMonth: [Date: [Int: Int]] = [:]  // [月份: [type_id: 总数量]]
            
            for entry in entries {
                guard let date = dateFormatter.date(from: entry.date) else {
                    Logger.error("日期格式错误：\(entry.date)")
                    continue
                }
                
                let components = calendar.dateComponents([.year, .month], from: date)
                guard let monthDate = calendar.date(from: components) else {
                    Logger.error("无法创建月份日期")
                    continue
                }
                
                if groupedByMonth[monthDate] == nil {
                    groupedByMonth[monthDate] = [:]
                }
                
                groupedByMonth[monthDate]?[entry.type_id, default: 0] += entry.quantity
            }
            
            Logger.debug("分组后的月份数：\(groupedByMonth.count)")
            
            // 转换为视图模型
            let groups = groupedByMonth.map { (date, itemQuantities) -> MiningMonthGroup in
                let summaries = itemQuantities.map { (typeId, quantity) -> MiningItemSummary in
                    let info = getItemInfo(for: typeId)
                    return MiningItemSummary(
                        id: typeId,
                        name: info.name,
                        iconFileName: info.iconFileName,
                        totalQuantity: quantity
                    )
                }.sorted { $0.totalQuantity > $1.totalQuantity }
                
                return MiningMonthGroup(yearMonth: date, entries: summaries)
            }.sorted { $0.yearMonth > $1.yearMonth }
            
            Logger.debug("最终生成的月份组数：\(groups.count)")
            
            await MainActor.run {
                self.monthGroups = groups
                Logger.debug("UI更新完成，monthGroups数量：\(self.monthGroups.count)")
                if shouldShowFullscreenLoading {
                    isLoading = false
                }
                isBackgroundLoading = false
            }
            
        } catch {
            Logger.error("加载挖矿记录失败：\(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                if shouldShowFullscreenLoading {
                    isLoading = false
                }
                isBackgroundLoading = false
            }
        }
    }
}

struct MiningLedgerView: View {
    @StateObject private var viewModel: MiningLedgerViewModel
    
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    init(characterId: Int, databaseManager: DatabaseManager) {
        _viewModel = StateObject(wrappedValue: MiningLedgerViewModel(characterId: characterId, databaseManager: databaseManager))
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView(NSLocalizedString("Mining_Loading", comment: ""))
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            } else if !viewModel.isLoading && viewModel.monthGroups.isEmpty {
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
                ForEach(viewModel.monthGroups) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            MiningItemRow(entry: entry, databaseManager: viewModel.databaseManager)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        }
                    } header: {
                        Text(String(format: NSLocalizedString("Mining_Monthly_Summary", comment: ""), monthFormatter.string(from: group.yearMonth)))
                            .font(.headline)
                            .foregroundColor(.primary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            // 立即启动后台刷新
            Task {
                await viewModel.loadMiningData(forceRefresh: true)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Mining_Ledger", comment: ""))
        .toolbar {
            if viewModel.isBackgroundLoading {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .task {
            await viewModel.loadMiningData()
        }
    }
}

struct MiningItemRow: View {
    let entry: MiningItemSummary
    let databaseManager: DatabaseManager
    @State private var itemIcon: Image?
    
    var body: some View {
        NavigationLink {
            MarketItemDetailView(databaseManager: databaseManager, itemID: entry.id)
        } label: {
            HStack(spacing: 12) {
                // 矿石图标
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
                    Text(entry.name)
                        .font(.body)
                    Text("× \(FormatUtil.format(Double(entry.totalQuantity)))")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .task {
            // 加载图标
            itemIcon = IconManager.shared.loadImage(for: entry.iconFileName)
        }
    }
} 
