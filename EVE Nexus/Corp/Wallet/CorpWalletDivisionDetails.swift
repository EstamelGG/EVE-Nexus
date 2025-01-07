import SwiftUI

struct CorpWalletDivisionDetails: View {
    let characterId: Int
    let division: Int
    let divisionName: String
    @State private var selectedTab = 0
    @State private var hasLoadedData = false
    
    // 创建并持久化子视图的 ViewModel
    @StateObject private var journalViewModel: CorpWalletJournalViewModel
    @StateObject private var transactionsViewModel: CorpWalletTransactionsViewModel
    
    init(characterId: Int, division: Int, divisionName: String) {
        self.characterId = characterId
        self.division = division
        self.divisionName = divisionName
        
        // 初始化 StateObject
        _journalViewModel = StateObject(wrappedValue: CorpWalletJournalViewModel(characterId: characterId, division: division))
        _transactionsViewModel = StateObject(wrappedValue: CorpWalletTransactionsViewModel(characterId: characterId, division: division, databaseManager: DatabaseManager.shared))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 内容视图
            TabView(selection: $selectedTab) {
                // 使用持久化的 ViewModel
                CorpWalletJournalView(characterId: characterId,
                                    division: division,
                                    divisionName: divisionName,
                                    viewModel: journalViewModel,
                                    skipInitialLoad: true)
                    .tag(0)
                
                CorpWalletTransactionsView(characterId: characterId,
                                         division: division,
                                         divisionName: divisionName,
                                         viewModel: transactionsViewModel,
                                         skipInitialLoad: true)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    // 顶部选择器
                    Picker("", selection: $selectedTab) {
                        Text(NSLocalizedString("Main_Wallet_Journal", comment: ""))
                            .tag(0)
                        Text(NSLocalizedString("Main_Market_Transactions", comment: ""))
                            .tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(divisionName)
        .task {
            // 只在第一次加载时执行数据加载
            if !hasLoadedData {
                async let journalLoad = journalViewModel.loadJournalData
                async let transactionsLoad = transactionsViewModel.loadTransactionData
                _ = await (journalLoad, transactionsLoad)
                hasLoadedData = true
            }
        }
    }
} 
