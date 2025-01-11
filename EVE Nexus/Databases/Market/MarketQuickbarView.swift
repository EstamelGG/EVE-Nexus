import SwiftUI
import Foundation

// 市场关注列表项目
struct MarketQuickbar: Identifiable, Codable {
    let id: UUID
    var name: String
    var items: [Int]  // 存储物品的 typeID
    var lastUpdated: Date
    
    init(id: UUID = UUID(), name: String, items: [Int] = []) {
        self.id = id
        self.name = name
        self.items = items
        self.lastUpdated = Date()
    }
}

// 管理市场关注列表的文件存储
class MarketQuickbarManager {
    static let shared = MarketQuickbarManager()
    
    private init() {
        createQuickbarDirectory()
    }
    
    private var quickbarDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("MarketQuickbars", isDirectory: true)
    }
    
    private func createQuickbarDirectory() {
        do {
            try FileManager.default.createDirectory(at: quickbarDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.error("创建市场关注列表目录失败: \(error)")
        }
    }
    
    func saveQuickbar(_ quickbar: MarketQuickbar) {
        let fileName = "market_quickbar_\(quickbar.id).json"
        let fileURL = quickbarDirectory.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
            let data = try encoder.encode(quickbar)
            try data.write(to: fileURL)
            Logger.debug("保存市场关注列表成功: \(fileName)")
        } catch {
            Logger.error("保存市场关注列表失败: \(error)")
        }
    }
    
    func loadQuickbars() -> [MarketQuickbar] {
        let fileManager = FileManager.default
        
        do {
            Logger.debug("开始加载市场关注列表")
            let files = try fileManager.contentsOfDirectory(at: quickbarDirectory, includingPropertiesForKeys: nil)
            Logger.debug("找到文件数量: \(files.count)")
            
            let quickbars = files.filter { url in
                url.lastPathComponent.hasPrefix("market_quickbar_") && url.pathExtension == "json"
            }.compactMap { url -> MarketQuickbar? in
                do {
                    Logger.debug("尝试解析文件: \(url.lastPathComponent)")
                    let data = try Data(contentsOf: url)
                    
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)
                    let quickbar = try decoder.decode(MarketQuickbar.self, from: data)
                    return quickbar
                } catch {
                    Logger.error("读取市场关注列表失败: \(error)")
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
            }
            .sorted { $0.lastUpdated > $1.lastUpdated }
            
            Logger.debug("成功加载市场关注列表数量: \(quickbars.count)")
            return quickbars
            
        } catch {
            Logger.error("读取市场关注列表目录失败: \(error)")
            return []
        }
    }
    
    func deleteQuickbar(_ quickbar: MarketQuickbar) {
        let fileName = "market_quickbar_\(quickbar.id).json"
        let fileURL = quickbarDirectory.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            Logger.debug("删除市场关注列表成功: \(fileName)")
        } catch {
            Logger.error("删除市场关注列表失败: \(error)")
        }
    }
}

// 市场关注列表主视图
struct MarketQuickbarView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var quickbars: [MarketQuickbar] = []
    @State private var isShowingAddAlert = false
    @State private var newQuickbarName = ""
    @State private var searchText = ""
    
    private var filteredQuickbars: [MarketQuickbar] {
        if searchText.isEmpty {
            return quickbars
        } else {
            return quickbars.filter { quickbar in
                quickbar.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        List {
            if filteredQuickbars.isEmpty {
                if searchText.isEmpty {
                    Text(NSLocalizedString("Main_Market_Watch_List_Empty", comment: ""))
                        .foregroundColor(.secondary)
                } else {
                    Text(String(format: NSLocalizedString("Main_EVE_Mail_No_Results", comment: "")))
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(filteredQuickbars) { quickbar in
                    NavigationLink {
                        MarketQuickbarDetailView(
                            databaseManager: databaseManager,
                            quickbar: quickbar
                        )
                    } label: {
                        quickbarRowView(quickbar)
                    }
                }
                .onDelete(perform: deleteQuickbar)
            }
        }
        .navigationTitle(NSLocalizedString("Main_Market_Watch_List", comment: ""))
        .searchable(text: $searchText,
                   placement: .navigationBarDrawer(displayMode: .always),
                   prompt: NSLocalizedString("Main_Database_Search", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newQuickbarName = ""
                    isShowingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(NSLocalizedString("Main_Market_Watch_List_Add", comment: ""), isPresented: $isShowingAddAlert) {
            TextField(NSLocalizedString("Main_Market_Watch_List_Name", comment: ""), text: $newQuickbarName)
            
            Button(NSLocalizedString("Main_EVE_Mail_Done", comment: "")) {
                if !newQuickbarName.isEmpty {
                    let newQuickbar = MarketQuickbar(
                        name: newQuickbarName,
                        items: []
                    )
                    quickbars.append(newQuickbar)
                    MarketQuickbarManager.shared.saveQuickbar(newQuickbar)
                    newQuickbarName = ""
                }
            }
            .disabled(newQuickbarName.isEmpty)
            
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                newQuickbarName = ""
            }
        } message: {
            Text(NSLocalizedString("Main_Market_Watch_List_Name", comment: ""))
        }
        .task {
            quickbars = MarketQuickbarManager.shared.loadQuickbars()
        }
    }
    
    private func quickbarRowView(_ quickbar: MarketQuickbar) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quickbar.name)
                .font(.headline)
                .lineLimit(1)
            
            Text(formatDate(quickbar.lastUpdated))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(String(format: NSLocalizedString("Main_Market_Watch_List_Items", comment: ""), quickbar.items.count))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day], from: date, to: now)
        
        if let days = components.day {
            if days > 30 {
                let formatter = DateFormatter()
                formatter.dateFormat = NSLocalizedString("Date_Format_Month_Day", comment: "")
                return formatter.string(from: date)
            } else if days > 0 {
                return String(format: NSLocalizedString("Time_Days_Ago", comment: ""), days)
            }
        }
        
        if let hours = components.hour, hours > 0 {
            return String(format: NSLocalizedString("Time_Hours_Ago", comment: ""), hours)
        } else if let minutes = components.minute, minutes > 0 {
            return String(format: NSLocalizedString("Time_Minutes_Ago", comment: ""), minutes)
        } else {
            return NSLocalizedString("Time_Just_Now", comment: "")
        }
    }
    
    private func deleteQuickbar(at offsets: IndexSet) {
        let quickbarsToDelete = offsets.map { filteredQuickbars[$0] }
        quickbarsToDelete.forEach { quickbar in
            MarketQuickbarManager.shared.deleteQuickbar(quickbar)
            if let index = quickbars.firstIndex(where: { $0.id == quickbar.id }) {
                quickbars.remove(at: index)
            }
        }
    }
}

struct MarketQuickbarDetailView: View {
    let databaseManager: DatabaseManager
    @State var quickbar: MarketQuickbar
    
    var body: some View {
        List {
            if quickbar.items.isEmpty {
                Text(NSLocalizedString("Main_Market_Watch_List_Empty", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                ForEach(quickbar.items, id: \.self) { typeID in
                    Text("\(typeID)")  // 临时显示 typeID，后续会改为显示物品名称和图标
                }
                .onDelete { indexSet in
                    quickbar.items.remove(atOffsets: indexSet)
                    MarketQuickbarManager.shared.saveQuickbar(quickbar)
                }
            }
        }
        .navigationTitle(quickbar.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // TODO: 添加物品的功能
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
} 