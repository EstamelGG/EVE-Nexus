import SwiftUI

struct KillMailLastWeekView: View {
    let characterId: Int
    @StateObject private var viewModel: KillMailLastWeekViewModel
    @StateObject private var detailViewModel = KillMailDetailViewModel()
    
    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: KillMailLastWeekViewModel(characterId: characterId))
    }
    
    var body: some View {
        KillMailListContainer(
            viewModel: viewModel,
            detailViewModel: detailViewModel,
            characterId: characterId
        )
        .navigationTitle("最近7天")
        .task {
            await viewModel.fetchKillMails()
        }
        .onChange(of: viewModel.killMails, initial: false) { oldValue, newValue in
            if !newValue.isEmpty {
                detailViewModel.requestDetails(for: Array(newValue.prefix(20)))
            }
        }
    }
}

// MARK: - 列表容器
private struct KillMailListContainer: View {
    @ObservedObject var viewModel: KillMailLastWeekViewModel
    @ObservedObject var detailViewModel: KillMailDetailViewModel
    let characterId: Int
    
    var body: some View {
        List {
            if viewModel.isLoading && viewModel.killMails.isEmpty {
                LoadingSection()
            } else if let error = viewModel.errorMessage {
                ErrorSection(message: error)
            } else if viewModel.killMails.isEmpty {
                EmptySection()
            } else {
                KillMailSection(
                    viewModel: viewModel,
                    detailViewModel: detailViewModel,
                    characterId: characterId
                )
            }
        }
        .refreshable {
            await viewModel.fetchKillMails()
        }
    }
}

// MARK: - 加载中部分
private struct LoadingSection: View {
    var body: some View {
        Section {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }
}

// MARK: - 错误部分
private struct ErrorSection: View {
    let message: String
    
    var body: some View {
        Section {
            Text(message)
                .foregroundColor(.red)
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }
}

// MARK: - 空数据部分
private struct EmptySection: View {
    var body: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    Text("没有找到击杀记录")
                        .foregroundColor(.gray)
                }
                .padding()
                Spacer()
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }
}

// MARK: - 击杀记录部分
private struct KillMailSection: View {
    @ObservedObject var viewModel: KillMailLastWeekViewModel
    @ObservedObject var detailViewModel: KillMailDetailViewModel
    let characterId: Int
    
    var body: some View {
        Section {
            ForEach(viewModel.killMails, id: \.killmail_id) { killmail in
                KillMailRow(
                    killmail: killmail,
                    viewModel: viewModel,
                    detailViewModel: detailViewModel,
                    characterId: characterId
                )
            }
            
            if viewModel.isLoadingMore {
                LoadingMoreRow()
            }
        }
    }
}

// MARK: - 击杀记录行
private struct KillMailRow: View {
    let killmail: KillMailInfo
    @ObservedObject var viewModel: KillMailLastWeekViewModel
    @ObservedObject var detailViewModel: KillMailDetailViewModel
    let characterId: Int
    
    var body: some View {
        if let detail = detailViewModel.getDetail(for: killmail.killmail_id) {
            KillMailDetailCell(detail: detail, killMailInfo: killmail, characterId: characterId)
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                .onAppear {
                    if killmail.killmail_id == viewModel.killMails.last?.killmail_id {
                        Task {
                            await viewModel.loadMoreKillMails()
                        }
                    }
                }
        } else {
            ProgressView()
                .onAppear {
                    // 当cell出现在视图中时，请求加载详情
                    detailViewModel.requestDetails(for: [killmail])
                    
                    if killmail.killmail_id == viewModel.killMails.last?.killmail_id {
                        Task {
                            await viewModel.loadMoreKillMails()
                        }
                    }
                }
                .onDisappear {
                    // 当cell消失时，如果还在加载中，可以考虑取消加载
                    if detailViewModel.isLoading(for: killmail.killmail_id) {
                        detailViewModel.cancelAllTasks()
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }
}

// MARK: - 加载更多行
private struct LoadingMoreRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding()
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
}

@MainActor
class KillMailLastWeekViewModel: ObservableObject {
    @Published private(set) var killMails: [KillMailInfo] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published private(set) var hasSearched = false
    @Published private(set) var loadingMessage: String?
    
    private let characterId: Int
    private var currentPage = 1
    private var hasMorePages = true
    private var existingKillMailIds: Set<Int> = []
    
    init(characterId: Int) {
        self.characterId = characterId
    }
    
    func fetchKillMails() async {
        isLoading = true
        currentPage = 1
        hasMorePages = true
        killMails.removeAll()
        existingKillMailIds.removeAll()
        errorMessage = nil
        hasSearched = true
        loadingMessage = "正在获取第1页数据"
        
        do {
            let newKillMails = try await ZKillMailsAPI.shared.fetchLastWeekKillMails(
                characterId: characterId,
                page: currentPage,
                saveToDatabase: false
            )
            
            // 更新已存在的ID集合
            existingKillMailIds = Set(newKillMails.map { $0.killmail_id })
            killMails = newKillMails
            
            // 如果第一页数据少于预期（通常是50条），说明没有更多页了
            hasMorePages = newKillMails.count >= 50
            
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("获取击杀记录失败: \(error)")
        }
        
        loadingMessage = nil
        isLoading = false
    }
    
    func loadMoreKillMails() async {
        guard !isLoadingMore,
              hasMorePages else {
            return
        }
        
        isLoadingMore = true
        currentPage += 1
        loadingMessage = "正在获取第\(currentPage)页数据"
        
        do {
            let newKillMails = try await ZKillMailsAPI.shared.fetchLastWeekKillMails(
                characterId: characterId,
                page: currentPage,
                saveToDatabase: false
            )
            
            // 过滤掉已经存在的记录
            let uniqueNewKillMails = newKillMails.filter { !existingKillMailIds.contains($0.killmail_id) }
            
            if uniqueNewKillMails.isEmpty || uniqueNewKillMails.count < 50 {
                hasMorePages = false
            } else {
                // 更新已存在的ID集合
                existingKillMailIds.formUnion(uniqueNewKillMails.map { $0.killmail_id })
                killMails.append(contentsOf: uniqueNewKillMails)
            }
            
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("加载更多击杀记录失败: \(error)")
        }
        
        loadingMessage = nil
        isLoadingMore = false
    }
} 
