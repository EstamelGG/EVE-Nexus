import SwiftUI

@MainActor
final class CorpWalletDivisionViewModel: ObservableObject {
    let journalViewModel: CorpWalletJournalViewModel
    let transactionsViewModel: CorpWalletTransactionsViewModel

    init(characterId: Int, division: Int, databaseManager: DatabaseManager) {
        journalViewModel = CorpWalletJournalViewModel(
            characterId: characterId, division: division
        )
        transactionsViewModel = CorpWalletTransactionsViewModel(
            characterId: characterId, division: division, databaseManager: databaseManager
        )
    }

    func loadInitialData() async {
        // 同时加载两个视图的数据
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.journalViewModel.loadJournalData()
            }
            group.addTask {
                await self.transactionsViewModel.loadTransactionData()
            }
        }
    }

    func refreshData() async {
        // 同时刷新两个视图的数据
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.journalViewModel.loadJournalData(forceRefresh: true)
            }
            group.addTask {
                await self.transactionsViewModel.loadTransactionData(forceRefresh: true)
            }
        }
    }
}

struct CorpWalletDivisionDetails: View {
    let characterId: Int
    let division: Int
    let divisionName: String
    @State private var selectedTab = 0
    @StateObject private var viewModel: CorpWalletDivisionViewModel

    init(characterId: Int, division: Int, divisionName: String) {
        self.characterId = characterId
        self.division = division
        self.divisionName = divisionName
        _viewModel = StateObject(
            wrappedValue: CorpWalletDivisionViewModel(
                characterId: characterId,
                division: division,
                databaseManager: DatabaseManager.shared
            ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部选择器
            Picker("", selection: $selectedTab) {
                Text(NSLocalizedString("Main_Wallet_Journal", comment: ""))
                    .tag(0)
                Text(NSLocalizedString("Main_Market_Transactions", comment: ""))
                    .tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 4)

            // 内容视图
            TabView(selection: $selectedTab) {
                CorpWalletJournalView(viewModel: viewModel.journalViewModel)
                    .tag(0)

                CorpWalletTransactionsView(viewModel: viewModel.transactionsViewModel)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(edges: .bottom)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(divisionName)
        .ignoresSafeArea(edges: .bottom)
        .task {
            await viewModel.loadInitialData()
        }
        .refreshable {
            await viewModel.refreshData()
        }
    }
}
