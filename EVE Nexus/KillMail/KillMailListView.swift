import SwiftUI

struct KillMailListView: View {
    let characterId: Int
    @StateObject private var viewModel: KillMailListViewModel
    
    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: KillMailListViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            // 快速访问列表
            Section {
                NavigationLink {
                    KillMailYearListView(characterId: characterId)
                } label: {
                    Label("按月查看", systemImage: "calendar")
                }
                
                NavigationLink {
                    KillMailLastWeekView(characterId: characterId)
                } label: {
                    Label("最近7天", systemImage: "clock")
                }
                
                NavigationLink {
                    Text("查看全部") // TODO: 实现查看全部视图
                } label: {
                    Label("查看全部", systemImage: "list.bullet")
                }
            } header: {
                Text("快速访问")
            }
            
            // 最近击杀预览
            Section {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if viewModel.recentKillMails.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                            Text(NSLocalizedString("Orders_No_Data", comment: ""))
                                .foregroundColor(.gray)
                        }
                        .padding()
                        Spacer()
                    }
                } else {
                    ForEach(viewModel.recentKillMails, id: \.killmail_id) { killmail in
                        KillMailCell(killmail: killmail)
                    }
                }
            } header: {
                Text("最近击杀")
            } footer: {
                if !viewModel.recentKillMails.isEmpty {
                    Text("显示最近5条击杀记录")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.fetchRecentKillMails(forceRefresh: true)
        }
        .onAppear {
            if viewModel.recentKillMails.isEmpty {
                Task {
                    await viewModel.fetchRecentKillMails()
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Killboard", comment: ""))
    }
}

// MARK: - ViewModel
@MainActor
final class KillMailListViewModel: ObservableObject {
    @Published private(set) var recentKillMails: [KillMailInfo] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    private let characterId: Int
    private var loadingTask: Task<Void, Never>?
    private var lastFetchTime: Date?
    private let cacheTimeout: TimeInterval = 300 // 5分钟缓存
    
    init(characterId: Int) {
        self.characterId = characterId
    }
    
    deinit {
        loadingTask?.cancel()
    }
    
    func fetchRecentKillMails(forceRefresh: Bool = false) async {
        // 如果已经在加载中，等待当前任务完成
        if let existingTask = loadingTask {
            await existingTask.value
            return
        }
        
        // 如果不是强制刷新，且缓存未过期，且已有数据，则直接返回
        if !forceRefresh,
           let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheTimeout,
           !recentKillMails.isEmpty {
            Logger.debug("使用缓存的击杀记录数据，跳过加载")
            return
        }
        
        // 创建新的加载任务
        let task = Task {
            isLoading = true
            errorMessage = nil
            
            do {
                Logger.info("开始获取最近击杀记录")
                // 使用新的方法只获取最近5条记录
                self.recentKillMails = try await ZKillMailsAPI.shared.fetchRecentKillMails(characterId: characterId)
                self.lastFetchTime = Date()
                
            } catch {
                Logger.error("获取击杀记录失败: \(error)")
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                }
            }
            
            if !Task.isCancelled {
                self.isLoading = false
            }
            
            // 清除任务引用
            self.loadingTask = nil
        }
        
        // 保存任务引用
        loadingTask = task
        
        // 等待任务完成
        await task.value
    }
}

// MARK: - Cell View
struct KillMailCell: View {
    let killmail: KillMailInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(killmail.killmail_id)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let totalValue = killmail.totalValue {
                    Spacer()
                    Text(formatISK(totalValue))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                if killmail.npc == true {
                    Text("NPC")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(4)
                }
                
                if killmail.solo == true {
                    Text("SOLO")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
                
                if killmail.awox == true {
                    Text("AWOX")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatISK(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        
        if value >= 1_000_000_000 {
            return "\(formatter.string(from: NSNumber(value: value / 1_000_000_000)) ?? "0")B ISK"
        } else if value >= 1_000_000 {
            return "\(formatter.string(from: NSNumber(value: value / 1_000_000)) ?? "0")M ISK"
        } else if value >= 1_000 {
            return "\(formatter.string(from: NSNumber(value: value / 1_000)) ?? "0")K ISK"
        } else {
            return "\(formatter.string(from: NSNumber(value: value)) ?? "0") ISK"
        }
    }
} 