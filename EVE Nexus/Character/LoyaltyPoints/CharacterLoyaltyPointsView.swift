import SwiftUI

struct CorporationLogoView: View {
    let corporationId: Int
    let iconFileName: String
    @State private var corporationLogo: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if !iconFileName.isEmpty {
                IconManager.shared.loadImage(for: iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            } else if let logo = corporationLogo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            } else if isLoading {
                ProgressView()
                    .frame(width: 36, height: 36)
            } else {
                IconManager.shared.loadImage(for: "corporations_default.png")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            }
        }
        .onAppear {
            if iconFileName.isEmpty {
                isLoading = true
                Task {
                    do {
                        corporationLogo = try await CorporationAPI.shared.fetchCorporationLogo(corporationId: corporationId)
                    } catch {
                        Logger.error("获取军团图标失败: \(error)")
                    }
                    isLoading = false
                }
            }
        }
    }
}

struct CharacterLoyaltyPointsView: View {
    @StateObject private var viewModel = CharacterLoyaltyPointsViewModel()
    let characterId: Int
    
    var body: some View {
        List {
            Section(NSLocalizedString("Main_LP_Basic_Info", comment: "")) {
                if viewModel.isLoading && viewModel.loyaltyPoints.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let error = viewModel.error {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(NSLocalizedString("Main_Database_Loading", comment: ""))
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button(NSLocalizedString("Main_Setting_Reset", comment: "")) {
                            viewModel.fetchLoyaltyPoints(characterId: characterId)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ForEach(viewModel.loyaltyPoints) { loyalty in
                        HStack {
                            CorporationLogoView(corporationId: loyalty.corporationId, iconFileName: loyalty.iconFileName)
                            
                            VStack(alignment: .leading) {
                                Text(loyalty.corporationName)
                                Text("\(loyalty.loyaltyPoints) LP")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(height: 36)
                    }
                }
            }
            
            Section {
                NavigationLink(destination: CharacterLoyaltyPointsStoreView()) {
                    HStack {
                        Image("lpstore")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text(NSLocalizedString("Main_LP_Store", comment: ""))
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refreshLoyaltyPoints(characterId: characterId)
        }
        .navigationTitle(NSLocalizedString("Main_Loyalty_Points", comment: ""))
        .onAppear {
            viewModel.fetchLoyaltyPoints(characterId: characterId)
        }
    }
}

#Preview {
    NavigationView {
        CharacterLoyaltyPointsView(characterId: 2112625428)
    }
} 
