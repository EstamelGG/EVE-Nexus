import SwiftUI

struct BRKillMailView: View {
    let characterId: Int
    @State private var selectedFilter: KillMailFilter = .all
    @State private var killMails: [KbKillMailInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var shipInfoMap: [Int: (name: String, iconFileName: String)] = [:]
    @State private var organizationIconMap: [Int: UIImage] = [:]
    
    let databaseManager = DatabaseManager.shared
    
    enum KillMailFilter {
        case all, kill, loss
        
        var title: String {
            switch self {
            case .all: return "所有记录"
            case .kill: return "击杀记录"
            case .loss: return "损失记录"
            }
        }
    }
    
    var body: some View {
        List {
            // 第一个Section：搜索入口
            Section {
                NavigationLink(destination: Text("搜索页面")) {
                    Text("搜索战斗记录")
                }
            }
            
            // 第二个Section：战斗记录列表
            Section(header: Text("我参与的战斗")) {
                // 筛选器
                Picker("筛选", selection: $selectedFilter) {
                    Text("全部").tag(KillMailFilter.all)
                    Text("击杀").tag(KillMailFilter.kill)
                    Text("损失").tag(KillMailFilter.loss)
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 8)
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if killMails.isEmpty {
                    Text("暂无战斗记录")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(killMails) { killmail in
                        BRKillMailCell(
                            killmail: killmail, 
                            shipInfo: shipInfoMap[killmail.vict.ship.id] ?? (name: "Unknown Item", iconFileName: DatabaseConfig.defaultItemIcon),
                            allianceIcon: killmail.vict.ally?.id != nil ? organizationIconMap[killmail.vict.ally!.id] : nil,
                            corporationIcon: organizationIconMap[killmail.vict.char.id]
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await loadKillMails()
        }
        .task {
            await loadKillMails()
        }
        .onChange(of: selectedFilter) { newValue in
            Logger.debug("筛选器变更: \(newValue)")
        }
    }
    
    private func loadKillMails() async {
        Logger.debug("开始加载战斗记录")
        isLoading = true
        errorMessage = nil
        
        do {
            Logger.debug("开始加载战斗记录，角色ID: \(characterId)")
            
            // 检查角色ID
            guard characterId > 0 else {
                errorMessage = "无效的角色ID: \(characterId)"
                Logger.error(errorMessage!)
                return
            }
            
            // 添加网络请求前的日志
            Logger.debug("准备发送API请求...")
            
            let response: KbKillMailResponse
            do {
                response = try await KbEvetoolAPI.shared.fetchCharacterKillMails(characterId: characterId)
                Logger.debug("API请求成功，获取到 \(response.data.count) 条记录")
                
                // 获取所有飞船ID
                let shipIds = response.data.map { $0.vict.ship.id }
                // 批量获取飞船信息
                let shipInfo = getShipInfo(for: shipIds)
                
                // 获取所有组织ID并去重
                var organizationIds = Set<Int>()
                for killmail in response.data {
                    if let allyId = killmail.vict.ally?.id, allyId > 0 {
                        organizationIds.insert(allyId)
                    }
                    if killmail.vict.char.id > 0 {
                        organizationIds.insert(killmail.vict.char.id)
                    }
                }
                
                // 批量加载组织图标
                let organizationIcons = await loadOrganizationIcons(for: Array(organizationIds))
                
                // 确保在主线程上更新 UI
                await MainActor.run {
                    Logger.debug("开始更新UI数据")
                    killMails = response.data
                    shipInfoMap = shipInfo
                    organizationIconMap = organizationIcons
                    isLoading = false
                    Logger.debug("UI数据更新完成，记录数: \(killMails.count)")
                }
            } catch {
                errorMessage = "API请求失败: \(error.localizedDescription)"
                Logger.error(errorMessage!)
                throw error
            }
        } catch {
            await MainActor.run {
                isLoading = false
                killMails = []
                errorMessage = error.localizedDescription
            }
            Logger.error("加载失败: \(error)")
        }
    }
    
    private func getShipInfo(for typeIds: [Int]) -> [Int: (name: String, iconFileName: String)] {
        guard !typeIds.isEmpty else { return [:] }
        
        // 构建IN查询的参数字符串
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
    
    private func loadOrganizationIcons(for ids: [Int]) async -> [Int: UIImage] {
        var iconMap: [Int: UIImage] = [:]
        
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for id in ids {
                group.addTask {
                    // 尝试加载联盟图标
                    if let iconURL = URL(string: "https://images.evetech.net/alliances/\(id)/logo?size=32") {
                        do {
                            let data = try await NetworkManager.shared.fetchData(from: iconURL)
                            if let image = UIImage(data: data) {
                                return (id, image)
                            }
                        } catch {
                            // 如果联盟图标加载失败，尝试加载军团图标
                            if let corpURL = URL(string: "https://images.evetech.net/corporations/\(id)/logo?size=32") {
                                do {
                                    let data = try await NetworkManager.shared.fetchData(from: corpURL)
                                    if let image = UIImage(data: data) {
                                        return (id, image)
                                    }
                                } catch {
                                    Logger.error("加载组织图标失败 - ID: \(id), 错误: \(error)")
                                }
                            }
                        }
                    }
                    return (id, nil)
                }
            }
            
            for await (id, image) in group {
                if let image = image {
                    iconMap[id] = image
                }
            }
        }
        
        return iconMap
    }
}

struct BRKillMailCell: View {
    let killmail: KbKillMailInfo
    let shipInfo: (name: String, iconFileName: String)
    let allianceIcon: UIImage?
    let corporationIcon: UIImage?
    
    private var organizationIcon: UIImage? {
        if let allyId = killmail.vict.ally?.id, allyId > 0, let icon = allianceIcon {
            return icon
        }
        return corporationIcon
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧飞船图标
            IconManager.shared.loadImage(for: shipInfo.iconFileName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // 右侧信息
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：舰船名称和价值
                HStack {
                    Text(shipInfo.name)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(killmail.formattedValue)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                // 第二行：受害者信息
                HStack(spacing: 4) {
                    if let icon = organizationIcon {
                        Image(uiImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(killmail.vict.char.name)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                // 第三行：地点和时间
                HStack {
                    // 安全等级和星系信息
                    HStack(spacing: 4) {
                        Text(formatSystemSecurity(Double(killmail.sys.ss) ?? 0.0))
                            .foregroundColor(getSecurityColor(Double(killmail.sys.ss) ?? 0.0))
                            .font(.system(size: 12, weight: .medium))
                        Text(killmail.sys.name)
                            .font(.system(size: 12, weight: .medium))
                        Text("/")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(killmail.sys.region)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // 时间
                    Text(killmail.formattedTime)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                // 第四行：NPC/Solo标记（如果有的话）
                if killmail.zkb.npc || killmail.zkb.solo {
                    HStack(spacing: 8) {
                        if killmail.zkb.npc {
                            Text("NPC")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                        if killmail.zkb.solo {
                            Text("Solo")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
} 