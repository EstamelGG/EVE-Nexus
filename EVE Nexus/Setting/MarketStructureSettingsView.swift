import SwiftUI

// MARK: - 数据模型

struct MarketStructure: Identifiable, Codable {
    var id = UUID()
    let structureId: Int
    let structureName: String
    let characterId: Int
    let characterName: String
    let systemId: Int  // 改为存储系统ID
    let regionId: Int  // 改为存储星域ID
    let security: Double
    let addedDate: Date
    let iconFilename: String?
    
    init(structureId: Int, structureName: String, characterId: Int, characterName: String, 
         systemId: Int, regionId: Int, security: Double, iconFilename: String? = nil) {
        self.structureId = structureId
        self.structureName = structureName
        self.characterId = characterId
        self.characterName = characterName
        self.systemId = systemId
        self.regionId = regionId
        self.security = security
        self.addedDate = Date()
        self.iconFilename = iconFilename
    }
    
    // 通过数据库查询获取系统名称
    var systemName: String {
        let query = """
            SELECT solarSystemName
            FROM solarsystems
            WHERE solarSystemID = ?
        """
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [systemId]),
           let row = rows.first,
           let name = row["solarSystemName"] as? String {
            return name
        }
        
        return "Unknown System"
    }
    
    // 通过数据库查询获取星域名称
    var regionName: String {
        let query = """
            SELECT regionName
            FROM regions
            WHERE regionID = ?
        """
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [regionId]),
           let row = rows.first,
           let name = row["regionName"] as? String {
            return name
        }
        
        return "Unknown Region"
    }
}

// MARK: - 市场建筑管理器

class MarketStructureManager: ObservableObject {
    static let shared = MarketStructureManager()
    
    @Published var structures: [MarketStructure] = []
    
    private let fileManager = FileManager.default
    private let documentsDirectory: URL
    private let structureDirectory: URL
    private let configFilePath: URL
    
    private init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        structureDirectory = documentsDirectory.appendingPathComponent("Structure_Market")
        configFilePath = structureDirectory.appendingPathComponent("selected_structures.json")
        
        createDirectoryIfNeeded()
        loadStructures()
    }
    
    private func createDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: structureDirectory.path) {
            do {
                try fileManager.createDirectory(at: structureDirectory, withIntermediateDirectories: true)
                Logger.info("创建市场建筑目录: \(structureDirectory.path)")
            } catch {
                Logger.error("创建市场建筑目录失败: \(error)")
            }
        }
    }
    
    func loadStructures() {
        guard fileManager.fileExists(atPath: configFilePath.path) else {
            structures = []
            return
        }
        
        do {
            let data = try Data(contentsOf: configFilePath)
            structures = try JSONDecoder().decode([MarketStructure].self, from: data)
            Logger.info("加载了 \(structures.count) 个市场建筑")
        } catch {
            Logger.error("加载市场建筑失败: \(error)")
            structures = []
        }
    }
    
    func saveStructures() {
        do {
            let data = try JSONEncoder().encode(structures)
            try data.write(to: configFilePath)
            Logger.info("保存了 \(structures.count) 个市场建筑")
        } catch {
            Logger.error("保存市场建筑失败: \(error)")
        }
    }
    
    func addStructure(_ structure: MarketStructure) {
        // 检查是否已存在相同的建筑
        if !structures.contains(where: { $0.structureId == structure.structureId }) {
            structures.append(structure)
            saveStructures()
        }
    }
    
    func removeStructure(_ structure: MarketStructure) {
        structures.removeAll { $0.id == structure.id }
        saveStructures()
    }
}

// MARK: - 主视图

struct MarketStructureSettingsView: View {
    @StateObject private var manager = MarketStructureManager.shared
    @State private var showingAddStructureSheet = false
    
    var body: some View {
        List {
            // 添加建筑 Section
            Section {
                Button(action: {
                    showingAddStructureSheet = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        Text(NSLocalizedString("Main_Setting_Market_Structure_Add", comment: ""))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
            
            // 已添加的建筑 Section
            if !manager.structures.isEmpty {
                Section(header: Text(String(format: NSLocalizedString("Main_Setting_Market_Structure_Added_Count", comment: ""), manager.structures.count))) {
                    ForEach(manager.structures) { structure in
                        StructureRowView(structure: structure)
                    }
                    .onDelete(perform: deleteStructures)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_Setting_Market_Structure_Settings_Title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingAddStructureSheet) {
            AddMarketStructureSheet()
        }
    }
    
    private func deleteStructures(offsets: IndexSet) {
        for index in offsets {
            manager.removeStructure(manager.structures[index])
        }
    }
}

// MARK: - 建筑行视图

struct StructureRowView: View {
    let structure: MarketStructure
    
    @State private var isLoadingOrders = false
    @State private var structureOrdersProgress: StructureOrdersProgress? = nil
    @State private var cacheStatus: StructureMarketManager.CacheStatus = .noData
    @State private var showingReloadAlert = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标
            if let iconFilename = structure.iconFilename {
                IconManager.shared.loadImage(for: iconFilename)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(8)
            } else {
                // 默认建筑图标
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "building.2")
                            .foregroundColor(.secondary)
                    )
            }
            
            // 建筑信息
            VStack(alignment: .leading, spacing: 2) {
                // 建筑名称
                Text(structure.structureName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // 位置信息
                HStack(spacing: 4) {
                    Text(formatSystemSecurity(structure.security))
                        .foregroundColor(getSecurityColor(structure.security))
                        .font(.caption)
                    
                    Text("\(structure.systemName) / \(structure.regionName)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                
                // 角色信息
                HStack {
                    Image(systemName: "person.circle")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text(structure.characterName)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Spacer()
                }
            }
            
            Spacer()
            
            // 缓存状态和加载进度指示器
            VStack(spacing: 4) {
                if isLoadingOrders {
                    if let progress = structureOrdersProgress {
                        switch progress {
                        case .loading(let currentPage, let totalPages):
                            VStack(spacing: 2) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("\(currentPage)/\(totalPages)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        case .completed:
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    } else {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                } else {
                    // 显示缓存状态
                    switch cacheStatus {
                    case .valid:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    case .expired:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                    case .noData:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.title2)
                    }
                }
            }
        }
        .contentShape(Rectangle()) // 确保整行可点击
        .onTapGesture {
            if !isLoadingOrders {
                showingReloadAlert = true
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = structure.structureName
            } label: {
                Label(NSLocalizedString("Misc_Copy_Structure", comment: ""), systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button {
                Task {
                    await loadStructureOrders()
                }
            } label: {
                if isLoadingOrders {
                    Label(NSLocalizedString("Structure_Orders_Loading", comment: "正在加载订单..."), systemImage: "arrow.clockwise")
                } else {
                    Label(NSLocalizedString("Structure_Orders_Load", comment: "获取市场订单"), systemImage: "chart.bar.xaxis")
                }
            }
            .disabled(isLoadingOrders)
        }
        .padding(.vertical, 4)
        .onAppear {
            cacheStatus = StructureMarketManager.getCacheStatus(structureId: Int64(structure.structureId))
        }
        .alert(NSLocalizedString("Structure_Orders_Reload_Title", comment: "重新加载订单"), isPresented: $showingReloadAlert) {
            Button(NSLocalizedString("Structure_Orders_Reload_Cancel", comment: "取消"), role: .cancel) { }
            Button(NSLocalizedString("Structure_Orders_Reload_Confirm", comment: "确认")) {
                Task {
                    await loadStructureOrders()
                }
            }
        } message: {
            Text(NSLocalizedString("Structure_Orders_Reload_Message", comment: "是否重新加载该建筑的市场订单数据？"))
        }
    }
    
    // 加载建筑市场订单
    private func loadStructureOrders() async {
        isLoadingOrders = true
        structureOrdersProgress = nil
        
        do {
            let orders = try await StructureMarketManager.shared.getStructureOrders(
                structureId: Int64(structure.structureId),
                characterId: structure.characterId,
                forceRefresh: true,
                progressCallback: { progress in
                    Task { @MainActor in
                        structureOrdersProgress = progress
                    }
                }
            )
            
            let statistics = await StructureMarketManager.shared.getOrdersStatistics(orders: orders)
            
            // 显示成功消息
            await MainActor.run {
                Logger.info("建筑 \(structure.structureName) 的市场订单已加载: 买单 \(statistics.buyOrders) 个, 卖单 \(statistics.sellOrders) 个, 总交易量 \(statistics.totalVolume)")
            }
            
        } catch {
            Logger.error("加载建筑市场订单失败: \(error)")
        }
        
        // 更新缓存状态
        cacheStatus = StructureMarketManager.getCacheStatus(structureId: Int64(structure.structureId))
        
        isLoadingOrders = false
        structureOrdersProgress = nil
    }
}

// MARK: - 日期格式化扩展

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
} 
