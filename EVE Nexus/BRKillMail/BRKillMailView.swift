import SwiftUI

struct BRKillMailView: View {
    let characterId: Int
    @State private var selectedFilter: KillMailFilter = .all
    @State private var killMails: [[String: Any]] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var shipInfoMap: [Int: (name: String, iconFileName: String)] = [:]
    @State private var allianceIconMap: [Int: UIImage] = [:]
    @State private var corporationIconMap: [Int: UIImage] = [:]
    
    let databaseManager = DatabaseManager.shared
    let kbAPI = KbEvetoolAPI.shared
    
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
    
    private struct OrganizationIdentifier: Hashable {
        let type: String
        let id: Int
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
                    ForEach(killMails.indices, id: \.self) { index in
                        let killmail = killMails[index]
                        if let shipId = kbAPI.getShipInfo(killmail, path: "vict", "ship").id {
                            let victInfo = killmail["vict"] as? [String: Any]
                            let allyInfo = victInfo?["ally"] as? [String: Any]
                            let corpInfo = victInfo?["corp"] as? [String: Any]
                            
                            let allyId = allyInfo?["id"] as? Int
                            let corpId = corpInfo?["id"] as? Int
                            
                            BRKillMailCell(
                                killmail: killmail,
                                kbAPI: kbAPI,
                                shipInfo: shipInfoMap[shipId] ?? (name: "Unknown Item", iconFileName: DatabaseConfig.defaultItemIcon),
                                allianceIcon: allyId.flatMap { allianceIconMap[$0] },
                                corporationIcon: corpId.flatMap { corporationIconMap[$0] }
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            Task {
                await loadKillMails()
            }
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
            
            let response = try await kbAPI.fetchCharacterKillMails(characterId: characterId)
            guard let records = response["data"] as? [[String: Any]] else {
                throw NSError(domain: "BRKillMailView", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的响应数据格式"])
            }
            
            Logger.debug("API请求成功，获取到 \(records.count) 条记录")
            
            // 获取所有飞船ID
            let shipIds = records.compactMap { record -> Int? in
                kbAPI.getShipInfo(record, path: "vict", "ship").id
            }
            
            // 批量获取飞船信息
            let shipInfo = getShipInfo(for: shipIds)
            
            // 确定每个战斗记录需要显示的组织ID
            var organizationIds = Set<OrganizationIdentifier>()
            for record in records {
                let victInfo = record["vict"] as? [String: Any]
                let allyInfo = victInfo?["ally"] as? [String: Any]
                let corpInfo = victInfo?["corp"] as? [String: Any]
                
                if let allyId = allyInfo?["id"] as? Int, allyId > 0 {
                    // 如果有有效的联盟ID，使用联盟图标
                    organizationIds.insert(OrganizationIdentifier(type: "alliance", id: allyId))
                } else if let corpId = corpInfo?["id"] as? Int, corpId > 0 {
                    // 如果联盟ID无效或为0，使用军团图标
                    organizationIds.insert(OrganizationIdentifier(type: "corporation", id: corpId))
                }
            }
            
            // 分别获取联盟和军团图标
            var allianceIcons: [Int: UIImage] = [:]
            var corporationIcons: [Int: UIImage] = [:]
            
            await withTaskGroup(of: (String, Int, UIImage?).self) { group in
                for org in organizationIds {
                    group.addTask {
                        let baseURL = org.type == "alliance" 
                            ? "https://images.evetech.net/alliances/\(org.id)/logo"
                            : "https://images.evetech.net/corporations/\(org.id)/logo"
                        
                        Logger.debug("准备获取\(org.type)图标 - ID: \(org.id)")
                        
                        if let iconURL = URL(string: "\(baseURL)?size=32") {
                            Logger.debug("开始请求图标: \(iconURL.absoluteString)")
                            do {
                                let data = try await NetworkManager.shared.fetchData(from: iconURL)
                                Logger.debug("获取到图标数据，大小: \(data.count) 字节")
                                
                                if let image = UIImage(data: data) {
                                    Logger.debug("成功创建图标图像")
                                    return (org.type, org.id, image)
                                } else {
                                    Logger.error("无法从数据创建图像 - \(org.type) ID: \(org.id)")
                                }
                            } catch {
                                Logger.error("加载\(org.type)图标失败 - ID: \(org.id), 错误: \(error)")
                            }
                        } else {
                            Logger.error("无效的图标URL - \(baseURL)?size=32")
                        }
                        return (org.type, org.id, nil)
                    }
                }
                
                for await (type, id, image) in group {
                    if let image = image {
                        Logger.debug("保存\(type)图标 - ID: \(id)")
                        if type == "alliance" {
                            allianceIcons[id] = image
                        } else {
                            corporationIcons[id] = image
                        }
                    }
                }
            }
            
            // 确保在主线程上更新 UI
            await MainActor.run {
                Logger.debug("开始更新UI数据")
                killMails = records
                shipInfoMap = shipInfo
                allianceIconMap = allianceIcons
                corporationIconMap = corporationIcons
                Logger.debug("图标数量 - 联盟: \(allianceIcons.count), 军团: \(corporationIcons.count)")
                isLoading = false
                Logger.debug("UI数据更新完成，记录数: \(killMails.count)")
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
        
        let systemText = Text(" \(sysInfo.name ?? "Unknown") / \(sysInfo.region ?? "Unknown")")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        
        return securityText + systemText
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：图标和信息
            HStack(spacing: 12) {
                // 左侧飞船图标
                IconManager.shared.loadImage(for: shipInfo.iconFileName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // 右侧信息
                VStack(alignment: .leading, spacing: 4) {
                    // 飞船名称
                    Text(shipInfo.name)
                        .font(.system(size: 16, weight: .medium))
                    
                    // 角色名称
                    if let charName = kbAPI.getCharacterInfo(killmail, path: "vict", "char").name {
                        Text(charName)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
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
        .padding(.vertical, 4)
    }
} 