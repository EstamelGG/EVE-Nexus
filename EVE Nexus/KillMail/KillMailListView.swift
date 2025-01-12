import SwiftUI

struct KillMailListView: View {
    @StateObject private var viewModel: KillMailListViewModel
    @StateObject private var detailViewModel = KillMailDetailViewModel()
    
    init(characterId: Int) {
        _viewModel = StateObject(wrappedValue: KillMailListViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            // 最近击杀记录
            if !viewModel.recentKillMails.isEmpty {
                ForEach(viewModel.recentKillMails, id: \.killmail_id) { killMail in
                    if let detail = detailViewModel.getDetail(for: killMail.killmail_id) {
                        KillMailDetailCell(detail: detail)
                    } else {
                        ProgressView()
                            .onAppear {
                                // 如果还没有获取详情，则获取
                                if detailViewModel.getDetail(for: killMail.killmail_id) == nil {
                                    detailViewModel.fetchDetails(for: [killMail])
                                }
                            }
                    }
                }
            } else if viewModel.isLoading {
                Text("正在获取击杀记录...")
                    .foregroundColor(.secondary)
            } else {
                Text("没有找到击杀记录")
                    .foregroundColor(.secondary)
            }
        }
        .refreshable {
            await viewModel.fetchKillMails()
        }
        .onAppear {
            if viewModel.recentKillMails.isEmpty {
                Task {
                    await viewModel.fetchKillMails()
                }
            }
        }
        .onChange(of: viewModel.recentKillMails) { newValue in
            if !newValue.isEmpty {
                detailViewModel.fetchDetails(for: Array(newValue.prefix(5)))
            }
        }
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