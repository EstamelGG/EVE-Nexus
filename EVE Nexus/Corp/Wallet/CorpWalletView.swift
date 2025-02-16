import SwiftUI

struct CorpWalletView: View {
    let characterId: Int
    @Environment(\.dismiss) private var dismiss
    @State private var wallets: [CorpWallet] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showError = false
    
    // 格式化金额
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }
    
    private func loadWallets(forceRefresh: Bool = false) {
        isLoading = true
        error = nil
        
        Task {
            do {
                let result = try await CorpWalletAPI.shared.fetchCorpWallets(characterId: characterId, forceRefresh: forceRefresh)
                await MainActor.run {
                    self.wallets = result.sorted { $0.division < $1.division }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.showError = true
                    self.isLoading = false
                }
                Logger.error("获取军团钱包数据失败: \(error)")
            }
        }
    }
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                    Spacer()
                }
            } else {
                ForEach(wallets, id: \.division) { wallet in
                    NavigationLink(destination: CorpWalletDivisionDetails(
                        characterId: characterId,
                        division: wallet.division,
                        divisionName: wallet.name ?? String(format: NSLocalizedString("Main_Corporation_Wallet_Default", comment: ""), wallet.division)
                    )) {
                        HStack {
                            // 钱包图标
                            Image("wallet")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                // 钱包分部名称
                                Text(wallet.name ?? String(format: NSLocalizedString("Main_Corporation_Wallet_Default", comment: ""), wallet.division))
                                    .font(.system(size: 16))
                                    .foregroundColor(.primary)
                                
                                // 余额
                                Text("\(formatBalance(wallet.balance)) ISK")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 2)
                            
                            Spacer()
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("Main_Corporation_wallet", comment: ""))
        .refreshable {
            loadWallets(forceRefresh: true)
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text(NSLocalizedString("Common_Error", comment: "")),
                message: Text(error?.localizedDescription ?? NSLocalizedString("Common_Unknown_Error", comment: "")),
                dismissButton: .default(Text(NSLocalizedString("Common_OK", comment: ""))) {
                    dismiss()
                }
            )
        }
        .onAppear {
            loadWallets()
        }
    }
} 
