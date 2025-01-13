import SwiftUI

struct BRKillMailView: View {
    let characterId: Int
    @State private var selectedFilter: KillMailFilter = .all
    @State private var killMails: [KbKillMailInfo] = []
    @State private var isLoading = false
    
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
            Section(header: HStack {
                Text("我参与的战斗")
                Spacer()
                Picker("筛选", selection: $selectedFilter) {
                    Text("所有记录").tag(KillMailFilter.all)
                    Text("击杀记录").tag(KillMailFilter.kill)
                    Text("损失记录").tag(KillMailFilter.loss)
                }
                .pickerStyle(.menu)
            }) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if killMails.isEmpty {
                    Text("暂无战斗记录")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(killMails, id: \._id) { killmail in
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
    }
    
    private func loadKillMails() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            killMails = try await KbEvetoolAPI.shared.fetchCharacterKillMails(characterId: characterId)
        } catch {
            Logger.error("加载战斗记录失败: \(error)")
        }
    }
}

struct BRKillMailCell: View {
    let killmail: KbKillMailInfo
    @State private var shipIcon: UIImage?
    @State private var victimAllianceIcon: UIImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一大行
            HStack(spacing: 12) {
                // 左侧飞船图标
                if let icon = shipIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 64, height: 64)
                }
                
                // 右侧信息
                VStack(alignment: .leading, spacing: 6) {
                    // 第一行：飞船名称
                    Text(killmail.vict.ship.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    // 第二行：受害者信息
                    HStack(spacing: 4) {
                        if let icon = victimAllianceIcon {
                            Image(uiImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                        Text(killmail.vict.char.name)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 第二大行：地点信息
            HStack(spacing: 2) {
                Text(killmail.sys.ss)
                    .foregroundColor(getSecurityColor(killmail.sys.ss))
                Text(killmail.sys.name)
                    .fontWeight(.medium)
                Text("/")
                    .foregroundColor(.secondary)
                Text(killmail.sys.region)
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 12))
        }
        .padding(.vertical, 4)
        .task {
            // 加载飞船图标
            if let iconURL = URL(string: "https://images.evetech.net/types/\(killmail.vict.ship.id)/icon?size=64") {
                do {
                    let data = try await NetworkManager.shared.fetchData(from: iconURL)
                    shipIcon = UIImage(data: data)
                } catch {
                    Logger.error("加载飞船图标失败: \(error)")
                }
            }
            
            // 加载受害者联盟图标
            if let allianceId = killmail.vict.ally?.id {
                if let iconURL = URL(string: "https://images.evetech.net/alliances/\(allianceId)/logo?size=32") {
                    do {
                        let data = try await NetworkManager.shared.fetchData(from: iconURL)
                        victimAllianceIcon = UIImage(data: data)
                    } catch {
                        Logger.error("加载联盟图标失败: \(error)")
                    }
                }
            }
        }
    }
    
    private func getSecurityColor(_ security: String) -> Color {
        if let value = Double(security) {
            if value >= 0.5 {
                return .green
            } else if value > 0.0 {
                return .orange
            }
        }
        return .red
    }
} 