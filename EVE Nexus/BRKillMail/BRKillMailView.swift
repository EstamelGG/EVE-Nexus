import SwiftUI

struct BRKillMailView: View {
    let characterId: Int
    @State private var selectedFilter: KillMailFilter = .all
    @State private var killMails: [[String: Any]] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var currentPage = 1
    @State private var totalPages = 1
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
                    
                    // 加载更多按钮
                    if currentPage < totalPages {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Button(action: {
                                    Task {
                                        await loadMoreKillMails()
                                    }
                                }) {
                                    Text("获取更多")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            isLoading = true
            await loadKillMails()
        }
        .onAppear {
            isLoading = true
            Task {
                await loadKillMails()
            }
        }
        .onChange(of: selectedFilter) { oldValue, newValue in
            Logger.debug("筛选器变更: 从 \(oldValue) 变更为 \(newValue)")
            // 立即清空列表和图标缓存
            killMails = []
            shipInfoMap = [:]
            allianceIconMap = [:]
            corporationIconMap = [:]
            isLoading = true
            Task {
                await loadKillMails()
            }
        }
    }
    
    private func loadKillMails() async {
        Logger.debug("开始加载战斗记录")
        isLoading = true
        errorMessage = nil
        currentPage = 1  // 重置页码
        
        do {
            Logger.debug("开始加载战斗记录，角色ID: \(characterId), 筛选类型: \(selectedFilter)")
            
            // 检查角色ID
            guard characterId > 0 else {
                errorMessage = "无效的角色ID: \(characterId)"
                Logger.error(errorMessage!)
                isLoading = false
                return
            }
            
            // 根据筛选类型设置请求参数
            let response: [String: Any]
            switch selectedFilter {
            case .all:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId)
            case .kill:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId, isKills: true)
            case .loss:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId, isLosses: true)
            }
            
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
                        
                        if let iconURL = URL(string: "\(baseURL)?size=64") {
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
                if let total = response["totalPages"] as? Int {
                    totalPages = total
                }
                Logger.debug("图标数量 - 联盟: \(allianceIcons.count), 军团: \(corporationIcons.count)")
                isLoading = false  // 加载完成后设置
                Logger.debug("UI数据更新完成，记录数: \(killMails.count), 总页数: \(totalPages)")
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
    
    private func loadMoreKillMails() async {
        guard !isLoadingMore && currentPage < totalPages else { return }
        
        isLoadingMore = true
        let nextPage = currentPage + 1
        
        do {
            Logger.debug("加载更多战斗记录 - 页码: \(nextPage), 筛选类型: \(selectedFilter)")
            
            // 根据筛选类型设置请求参数
            let response: [String: Any]
            switch selectedFilter {
            case .all:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId, page: nextPage)
            case .kill:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId, page: nextPage, isKills: true)
            case .loss:
                response = try await kbAPI.fetchCharacterKillMails(characterId: characterId, page: nextPage, isLosses: true)
            }
            
            guard let records = response["data"] as? [[String: Any]] else {
                throw NSError(domain: "BRKillMailView", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的响应数据格式"])
            }
            
            // 获取所有新的飞船ID
            let shipIds = records.compactMap { record -> Int? in
                kbAPI.getShipInfo(record, path: "vict", "ship").id
            }
            
            // 批量获取新的飞船信息
            let newShipInfo = getShipInfo(for: shipIds)
            
            // 获取新的组织图标
            var newOrganizationIds = Set<OrganizationIdentifier>()
            for record in records {
                let victInfo = record["vict"] as? [String: Any]
                let allyInfo = victInfo?["ally"] as? [String: Any]
                let corpInfo = victInfo?["corp"] as? [String: Any]
                
                if let allyId = allyInfo?["id"] as? Int, allyId > 0 {
                    newOrganizationIds.insert(OrganizationIdentifier(type: "alliance", id: allyId))
                } else if let corpId = corpInfo?["id"] as? Int, corpId > 0 {
                    newOrganizationIds.insert(OrganizationIdentifier(type: "corporation", id: corpId))
                }
            }
            
            // 获取新的图标
            var newAllianceIcons: [Int: UIImage] = [:]
            var newCorporationIcons: [Int: UIImage] = [:]
            
            await withTaskGroup(of: (String, Int, UIImage?).self) { group in
                for org in newOrganizationIds {
                    group.addTask {
                        let baseURL = org.type == "alliance" 
                            ? "https://images.evetech.net/alliances/\(org.id)/logo"
                            : "https://images.evetech.net/corporations/\(org.id)/logo"
                        
                        if let iconURL = URL(string: "\(baseURL)?size=64") {
                            do {
                                let data = try await NetworkManager.shared.fetchData(from: iconURL)
                                if let image = UIImage(data: data) {
                                    return (org.type, org.id, image)
                                }
                            } catch {
                                Logger.error("加载\(org.type)图标失败 - ID: \(org.id), 错误: \(error)")
                            }
                        }
                        return (org.type, org.id, nil)
                    }
                }
                
                for await (type, id, image) in group {
                    if let image = image {
                        if type == "alliance" {
                            newAllianceIcons[id] = image
                        } else {
                            newCorporationIcons[id] = image
                        }
                    }
                }
            }
            
            // 更新UI
            await MainActor.run {
                // 更新页码信息
                currentPage = nextPage
                if let total = response["totalPages"] as? Int {
                    totalPages = total
                }
                
                // 合并数据
                killMails.append(contentsOf: records)
                shipInfoMap.merge(newShipInfo) { current, _ in current }
                allianceIconMap.merge(newAllianceIcons) { current, _ in current }
                corporationIconMap.merge(newCorporationIcons) { current, _ in current }
                
                isLoadingMore = false
                Logger.debug("成功加载更多记录 - 当前页: \(currentPage)/\(totalPages)")
            }
        } catch {
            await MainActor.run {
                isLoadingMore = false
                errorMessage = error.localizedDescription
            }
            Logger.error("加载更多记录失败: \(error)")
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
        .padding(.vertical, 4)
    }
} 
