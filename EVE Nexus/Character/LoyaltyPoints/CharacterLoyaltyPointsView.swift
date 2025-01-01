import SwiftUI

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
                            if !loyalty.iconFileName.isEmpty {
                                IconManager.shared.loadImage(for: loyalty.iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                            } else {
                                AsyncImage(url: URL(string: "https://images.evetech.net/corporations/\(loyalty.corporationId)/logo")) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                    case .failure:
                                        IconManager.shared.loadImage(for: "corporations_default.png")
                                            .resizable()
                                            .scaledToFit()
                                    case .empty:
                                        ProgressView()
                                    @unknown default:
                                        IconManager.shared.loadImage(for: "corporations_default.png")
                                            .resizable()
                                            .scaledToFit()
                                    }
                                }
                                .frame(width: 36, height: 36)
                            }
                            
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
                NavigationLink(destination: EmptyView()) {
                    Text(NSLocalizedString("Main_LP_Store", comment: ""))
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
