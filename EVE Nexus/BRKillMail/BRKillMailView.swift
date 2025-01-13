import SwiftUI

struct BRKillMailView: View {
    let characterId: Int
    @State private var selectedFilter: KillMailFilter = .all
    @State private var killMails: [KbKillMailInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
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
                        BRKillMailCell(killmail: killmail)
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
            } catch {
                errorMessage = "API请求失败: \(error.localizedDescription)"
                Logger.error(errorMessage!)
                throw error
            }
            
            // 确保在主线程上更新 UI
            await MainActor.run {
                Logger.debug("开始更新UI数据")
                killMails = response.data
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
}

struct BRKillMailCell: View {
    let killmail: KbKillMailInfo
    @State private var shipIcon: UIImage?
    @State private var victimAllianceIcon: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧飞船图标
            if let icon = shipIcon {
                Image(uiImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 64, height: 64)
            }
            
            // 右侧信息
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：舰船名称和价值
                HStack {
                    Text(killmail.vict.ship.name)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(killmail.formattedValue)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                // 第二行：受害者信息
                HStack(spacing: 4) {
                    if let icon = victimAllianceIcon {
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
        .task {
            await loadIcons()
        }
    }
    
    private func loadIcons() async {
        // 加载飞船图标
        if let iconURL = URL(string: "https://images.evetech.net/types/\(killmail.vict.ship.id)/icon?size=64") {
            do {
                let data = try await NetworkManager.shared.fetchData(from: iconURL)
                await MainActor.run {
                    shipIcon = UIImage(data: data)
                }
            } catch {
                Logger.error("加载飞船图标失败: \(error)")
            }
        }
        
        // 加载受害者联盟图标
        if let allianceId = killmail.vict.ally?.id {
            if let iconURL = URL(string: "https://images.evetech.net/alliances/\(allianceId)/logo?size=32") {
                do {
                    let data = try await NetworkManager.shared.fetchData(from: iconURL)
                    await MainActor.run {
                        victimAllianceIcon = UIImage(data: data)
                    }
                } catch {
                    Logger.error("加载联盟图标失败: \(error)")
                }
            }
        }
    }
} 