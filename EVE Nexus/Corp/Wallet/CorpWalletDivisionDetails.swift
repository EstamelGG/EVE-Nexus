import SwiftUI

struct CorpWalletDivisionDetails: View {
    let characterId: Int
    let division: Int
    let divisionName: String
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // 内容视图
            TabView(selection: $selectedTab) {
                CorpWalletJournalView(characterId: characterId,
                                    division: division,
                                    divisionName: divisionName)
                                    .tag(0)
                
                CorpWalletTransactionsView(characterId: characterId,
                                         division: division,
                                         divisionName: divisionName,
                                         databaseManager: DatabaseManager.shared)
                                        .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
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
    }
} 
