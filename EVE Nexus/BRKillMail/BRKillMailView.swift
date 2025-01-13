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
        VStack(alignment: .leading, spacing: 8) {
            // DEBUG: 添加ID显示
            Text("ID: \(killmail._id)")
                .font(.caption)
                .foregroundColor(.gray)
            
            // 第一大行
            HStack(spacing: 12) {
                // 左侧飞船图标
                if let icon = shipIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 48, height: 48)
                }
                
                // 右侧信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(killmail.vict.ship.name)
                        .font(.headline)
                    Text(killmail.vict.char.name)
                        .font(.subheadline)
                }
            }
            
            // 第二大行：地点信息
            HStack {
                Text("\(killmail.sys.ss) \(killmail.sys.name) / \(killmail.sys.region)")
                    .font(.caption)
            }
            
            // DEBUG: 添加时间和价值显示
            Text("时间: \(killmail.formattedTime)")
                .font(.caption)
            Text("价值: \(killmail.formattedValue)")
                .font(.caption)
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
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