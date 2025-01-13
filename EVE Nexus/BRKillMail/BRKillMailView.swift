import SwiftUI

enum KillMailFilter: String {
    case all = "all"
    case kill = "kill"
    case loss = "loss"
    
    var title: String {
        switch self {
        case .all: return "所有记录"
        case .kill: return "击杀记录"
        case .loss: return "损失记录"
        }
    }
}

class KillMailViewModel: ObservableObject {
    @Published private(set) var killMails: [[String: Any]] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shipInfoMap: [Int: (name: String, iconFileName: String)] = [:]
    @Published private(set) var allianceIconMap: [Int: UIImage] = [:]
    @Published private(set) var corporationIconMap: [Int: UIImage] = [:]
    @Published private(set) var characterStats: CharBattleIsk?
    
    private var cachedData: [KillMailFilter: CachedKillMailData] = [:]
    private let characterId: Int
    private let databaseManager = DatabaseManager.shared
    let kbAPI = KbEvetoolAPI.shared
    
    struct CachedKillMailData {
        let mails: [[String: Any]]
        let shipInfo: [Int: (name: String, iconFileName: String)]
        let allianceIcons: [Int: UIImage]
        let corporationIcons: [Int: UIImage]
    }
    
    init(characterId: Int) {
        self.characterId = characterId
    }
    
    func loadDataIfNeeded(for filter: KillMailFilter) async {
        if let cached = cachedData[filter] {
            await MainActor.run {
                killMails = cached.mails
                shipInfoMap = cached.shipInfo
                allianceIconMap = cached.allianceIcons
                corporationIconMap = cached.corporationIcons
            }
            return
        }
        
        await loadData(for: filter)
    }
    
    private func loadData(for filter: KillMailFilter) async {
        guard characterId > 0 else {
            errorMessage = "无效的角色ID: \(characterId)"
            return
        }
        
        await MainActor.run { isLoading = true }
        
        do {
            let response: [String: Any]
            switch filter {
            case .all:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId)
            case .kill:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId, isKills: true)
            case .loss:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId, isLosses: true)
            }
            
            guard let mails = response["data"] as? [[String: Any]] else {
                throw NSError(domain: "BRKillMailView", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的响应数据格式"])
            }
            
            let shipIds = mails.compactMap { kbAPI.getShipInfo($0, path: "vict", "ship").id }
            let shipInfo = getShipInfo(for: shipIds)
            let (allianceIcons, corporationIcons) = await loadOrganizationIcons(for: mails)
            
            let cachedData = CachedKillMailData(
                mails: mails,
                shipInfo: shipInfo,
                allianceIcons: allianceIcons,
                corporationIcons: corporationIcons
            )
            
            await MainActor.run {
                self.cachedData[filter] = cachedData
                self.killMails = mails
                self.shipInfoMap = shipInfo
                self.allianceIconMap = allianceIcons
                self.corporationIconMap = corporationIcons
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func refreshData(for filter: KillMailFilter) async {
        cachedData.removeValue(forKey: filter)
        await loadData(for: filter)
    }
    
    private func loadOrganizationIcons(for mails: [[String: Any]]) async -> ([Int: UIImage], [Int: UIImage]) {
        var allianceIcons: [Int: UIImage] = [:]
        var corporationIcons: [Int: UIImage] = [:]
        
        for mail in mails {
            if let victInfo = mail["vict"] as? [String: Any] {
                // 优先检查联盟ID
                if let allyInfo = victInfo["ally"] as? [String: Any],
                   let allyId = allyInfo["id"] as? Int,
                   allyId > 0 {
                    // 只有当联盟ID有效且图标未加载时才加载联盟图标
                    if allianceIcons[allyId] == nil,
                       let icon = await loadOrganizationIcon(type: "alliance", id: allyId) {
                        allianceIcons[allyId] = icon
                    }
                } else if let corpInfo = victInfo["corp"] as? [String: Any],
                          let corpId = corpInfo["id"] as? Int,
                          corpId > 0 {
                    // 只有在没有有效联盟ID的情况下才加载军团图标
                    if corporationIcons[corpId] == nil,
                       let icon = await loadOrganizationIcon(type: "corporation", id: corpId) {
                        corporationIcons[corpId] = icon
                    }
                }
            }
        }
        
        return (allianceIcons, corporationIcons)
    }
    
    private func loadOrganizationIcon(type: String, id: Int) async -> UIImage? {
        let baseURL = "https://images.evetech.net/\(type)s/\(id)/logo"
        guard let iconURL = URL(string: "\(baseURL)?size=64") else { return nil }
        
        do {
            let data = try await NetworkManager.shared.fetchData(from: iconURL)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }
    
    private func getShipInfo(for typeIds: [Int]) -> [Int: (name: String, iconFileName: String)] {
        guard !typeIds.isEmpty else { return [:] }
        
        let placeholders = String(repeating: "?,", count: typeIds.count).dropLast()
        let query = """
            SELECT type_id, name, icon_filename 
            FROM types 
            WHERE type_id IN (\(placeholders))
        """
        
        let result = databaseManager.executeQuery(query, parameters: typeIds)
        var infoMap: [Int: (name: String, iconFileName: String)] = [:]
        
        if case .success(let rows) = result {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String {
                    infoMap[typeId] = (name: name, iconFileName: iconFileName)
                }
            }
        }
        
        return infoMap
    }
    
    func loadStats() async {
        do {
            let stats = try await ZKillMailsAPI.shared.fetchCharacterStats(characterId: characterId)
            await MainActor.run {
                self.characterStats = stats
            }
        } catch {
            Logger.error("获取战斗统计信息失败: \(error)")
        }
    }
}

struct BRKillMailView: View {
    let characterId: Int
    @StateObject private var viewModel: KillMailViewModel
    @State private var selectedFilter: KillMailFilter = .all
    
    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: KillMailViewModel(characterId: characterId))
    }
    
    private func formatISK(_ value: Double) -> String {
        if value >= 1_000_000_000_000 {
            return String(format: "%.1fT ISK", value / 1_000_000_000_000)
        } else if value >= 1_000_000_000 {
            return String(format: "%.1fB ISK", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM ISK", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK ISK", value / 1_000)
        } else {
            return String(format: "%.0f ISK", value)
        }
    }
    
    var body: some View {
        List {
            // 战斗统计信息
            Section {
                if let stats = viewModel.characterStats {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                        Text("摧毁价值")
                        Spacer()
                        Text(formatISK(stats.iskDestroyed))
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.red)
                        Text("损失价值")
                        Spacer()
                        Text(formatISK(stats.iskLost))
                            .foregroundColor(.red)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            
            // 搜索入口
            Section {
                NavigationLink(destination: Text("搜索页面")) {
                    Text("搜索战斗记录")
                }
            }
            
            // 战斗记录列表
            Section(header: Text("我参与的战斗")) {
                Picker("筛选", selection: $selectedFilter) {
                    Text("全部").tag(KillMailFilter.all)
                    Text("击杀").tag(KillMailFilter.kill)
                    Text("损失").tag(KillMailFilter.loss)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 8)
                .onChange(of: selectedFilter) { oldValue, newValue in
                    Task {
                        await viewModel.loadDataIfNeeded(for: newValue)
                    }
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if viewModel.killMails.isEmpty {
                    Text("暂无战斗记录")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.killMails.indices, id: \.self) { index in
                        let killmail = viewModel.killMails[index]
                        if let shipId = viewModel.kbAPI.getShipInfo(killmail, path: "vict", "ship").id {
                            let victInfo = killmail["vict"] as? [String: Any]
                            let allyInfo = victInfo?["ally"] as? [String: Any]
                            let corpInfo = victInfo?["corp"] as? [String: Any]
                            
                            let allyId = allyInfo?["id"] as? Int
                            let corpId = corpInfo?["id"] as? Int
                            
                            BRKillMailCell(
                                killmail: killmail,
                                kbAPI: viewModel.kbAPI,
                                shipInfo: viewModel.shipInfoMap[shipId] ?? (name: "Unknown Item", iconFileName: DatabaseConfig.defaultItemIcon),
                                allianceIcon: allyId.flatMap { viewModel.allianceIconMap[$0] },
                                corporationIcon: corpId.flatMap { viewModel.corporationIconMap[$0] }
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refreshData(for: selectedFilter)
            await viewModel.loadStats()
        }
        .onAppear {
            Task {
                await viewModel.loadDataIfNeeded(for: selectedFilter)
                await viewModel.loadStats()
            }
        }
    }
}

struct BRKillMailCell: View {
    let killmail: [String: Any]
    let kbAPI: KbEvetoolAPI
    let shipInfo: (name: String, iconFileName: String)
    let allianceIcon: UIImage?
    let corporationIcon: UIImage?
    
    private var organizationIcon: UIImage? {
        let victInfo = killmail["vict"] as? [String: Any]
        let allyInfo = victInfo?["ally"] as? [String: Any]
        let corpInfo = victInfo?["corp"] as? [String: Any]
        
        // 先尝试获取联盟图标
        if let allyId = allyInfo?["id"] as? Int, allyId > 0, let icon = allianceIcon {
            Logger.debug("使用联盟图标 - ID: \(allyId)")
            return icon
        }
        
        // 如果没有联盟图标，尝试获取军团图标
        if let corpId = corpInfo?["id"] as? Int, corpId > 0, let icon = corporationIcon {
            Logger.debug("使用军团图标 - ID: \(corpId)")
            return icon
        }
        
        Logger.debug("未找到组织图标")
        return nil
    }
    
    private var locationText: Text {
        let sysInfo = kbAPI.getSystemInfo(killmail)
        let securityText = Text(formatSystemSecurity(Double(sysInfo.security ?? "0.0") ?? 0.0))
            .foregroundColor(getSecurityColor(Double(sysInfo.security ?? "0.0") ?? 0.0))
            .font(.system(size: 12, weight: .medium))
        
        let systemName = Text(" \(sysInfo.name ?? "Unknown")")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.secondary)
        
        let regionText = Text(" / \(sysInfo.region ?? "Unknown")")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        
        return securityText + systemName + regionText
    }
    
    private var displayName: String {
        let victInfo = killmail["vict"] as? [String: Any]
        let charInfo = victInfo?["char"]  // 先获取原始值，不做类型转换
        let allyInfo = victInfo?["ally"] as? [String: Any]
        let corpInfo = victInfo?["corp"] as? [String: Any]
        
        // 如果char是字典类型，说明有完整的角色信息
        if let charDict = charInfo as? [String: Any],
           let name = charDict["name"] as? String {
            return name
        }
        
        // 如果char是数字类型且为0，或者不存在，尝试使用联盟名
        if let allyName = allyInfo?["name"] as? String,
           let allyId = allyInfo?["id"] as? Int,
           allyId > 0 {
            return allyName
        }
        
        // 如果联盟也没有，使用军团名
        if let corpName = corpInfo?["name"] as? String {
            return corpName
        }
        
        return "Unknown"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：图标和信息
            HStack(spacing: 12) {
                // 左侧飞船图标
                IconManager.shared.loadImage(for: shipInfo.iconFileName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // 右侧信息
                VStack(alignment: .leading, spacing: 4) {
                    // 飞船名称
                    Text(shipInfo.name)
                        .font(.system(size: 16, weight: .medium))
                    
                    // 显示名称（角色/联盟/军团）
                    Text(displayName)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    // 位置信息
                    locationText
                }
                
                Spacer()
                
                // 右侧组织图标
                if let icon = organizationIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                }
            }
            
            // 第二行：时间和价值
            HStack {
                if let time = kbAPI.getFormattedTime(killmail) {
                    Text(time)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let value = kbAPI.getFormattedValue(killmail) {
                    Text(value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }
} 
