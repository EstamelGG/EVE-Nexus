import SwiftUI

struct CharacterLoyaltyPointsView: View {
    @StateObject private var viewModel = CharacterLoyaltyPointsViewModel()
    let characterId: Int
    
    var body: some View {
        List {
            if viewModel.isLoading {
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
                                .frame(width: 40, height: 40)
                        } else {
                            AsyncImage(url: URL(string: "https://images.evetech.net/corporations/\(loyalty.corporationId)/logo")) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 40, height: 40)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(loyalty.corporationName)
                                .font(.headline)
                            Text("\(loyalty.loyaltyPoints) LP")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
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
