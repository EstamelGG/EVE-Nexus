import SwiftUI

struct KillMailAllView: View {
    let characterId: Int
    @StateObject private var viewModel: KillMailAllViewModel
    
    init(characterId: Int) {
        self.characterId = characterId
        _viewModel = StateObject(wrappedValue: KillMailAllViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            if viewModel.hasSearched {
                Section {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                ProgressView()
                                if let message = viewModel.loadingMessage {
                                    Text(message)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                    } else if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                    } else if viewModel.killMails.isEmpty {
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
                    } else {
                        ForEach(viewModel.killMails, id: \.killmail_id) { killmail in
                            KillMailCell(killmail: killmail)
                                .onAppear {
                                    // 当显示最后一条记录时，加载更多
                                    if killmail.killmail_id == viewModel.killMails.last?.killmail_id {
                                        Task {
                                            await viewModel.loadMoreKillMails()
                                        }
                                    }
                                }
                        }
                        
                        if viewModel.isLoadingMore {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    ProgressView()
                                    if let message = viewModel.loadingMessage {
                                        Text(message)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding()
                        }
                    }
                } header: {
                    Text("全部击杀记录")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("全部战斗")
        .task {
            await viewModel.fetchKillMails()
        }
        .refreshable {
            await viewModel.fetchKillMails()
        }
    }
}

@MainActor
class KillMailAllViewModel: ObservableObject {
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
            let newKillMails = try await ZKillMailsAPI.shared.fetchCharacterKillMails(
                characterId: characterId,
                forceRefresh: false,
                saveToDatabase: false  // 不保存到数据库
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
            let newKillMails = try await ZKillMailsAPI.shared.fetchCharacterKillMails(
                characterId: characterId,
                forceRefresh: false,
                saveToDatabase: false  // 不保存到数据库
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