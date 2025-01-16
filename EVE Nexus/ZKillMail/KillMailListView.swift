import SwiftUI

struct KillMailListView: View {
    @StateObject private var viewModel: KillMailListViewModel
    @StateObject private var detailViewModel = KillMailDetailViewModel()
    
    init(characterId: Int) {
        _viewModel = StateObject(wrappedValue: KillMailListViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            NavigationSection(characterId: viewModel.characterId)
            RecentKillMailsSection(viewModel: viewModel, detailViewModel: detailViewModel)
        }
        .task {
            await viewModel.fetchRecentKillMails()
        }
    }
}

// MARK: - 导航部分
private struct NavigationSection: View {
    let characterId: Int
    
    var body: some View {
        Section {
            NavigationLink {
                KillMailYearListView(characterId: characterId)
            } label: {
                Label("选择月份", systemImage: "calendar")
            }
            
            NavigationLink {
                KillMailLastWeekView(characterId: characterId)
            } label: {
                Label("近一周", systemImage: "clock.arrow.circlepath")
            }
            
            NavigationLink {
                KillMailAllView(characterId: characterId)
            } label: {
                Label("显示全部", systemImage: "list.bullet")
            }
        } header: {
            Text("击杀记录")
        }
    }
}

// MARK: - 最近击杀记录部分
private struct RecentKillMailsSection: View {
    @ObservedObject var viewModel: KillMailListViewModel
    @ObservedObject var detailViewModel: KillMailDetailViewModel
    
    var body: some View {
        Section {
            if !viewModel.recentKillMails.isEmpty {
                ForEach(viewModel.recentKillMails, id: \.killmail_id) { killmail in
                    KillMailRow(
                        killmail: killmail,
                        detailViewModel: detailViewModel,
                        characterId: viewModel.characterId
                    )
                }
            } else if viewModel.isLoading {
                LoadingRow()
            } else {
                EmptyRow()
            }
        } header: {
            Text("最近击杀记录")
        }
    }
}

// MARK: - 击杀记录行
private struct KillMailRow: View {
    let killmail: KillMailInfo
    @ObservedObject var detailViewModel: KillMailDetailViewModel
    let characterId: Int
    
    var body: some View {
        if let detail = detailViewModel.getDetail(for: killmail.killmail_id) {
            KillMailDetailCell(detail: detail, killMailInfo: killmail, characterId: characterId)
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        } else {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(height: 80)
            .onAppear {
                // 当cell出现在视图中时，请求加载详情
                detailViewModel.requestDetails(for: [killmail])
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }
}

// MARK: - 加载中行
private struct LoadingRow: View {
    var body: some View {
        Text("正在获取击杀记录...")
            .foregroundColor(.secondary)
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

// MARK: - 空数据行
private struct EmptyRow: View {
    var body: some View {
        Text("没有找到击杀记录")
            .foregroundColor(.secondary)
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

// MARK: - ViewModel
@MainActor
final class KillMailListViewModel: ObservableObject {
    @Published private(set) var recentKillMails: [KillMailInfo] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    let characterId: Int
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
