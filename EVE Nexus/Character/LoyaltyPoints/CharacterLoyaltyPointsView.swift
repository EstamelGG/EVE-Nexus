import SwiftUI

struct CorporationLogoView: View {
    let corporationId: Int
    let iconFileName: String
    @State private var corporationLogo: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if !iconFileName.isEmpty {
                CorporationIconView(
                    corporationId: corporationId, iconFileName: iconFileName, size: 36
                )
            } else if let logo = corporationLogo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            } else if isLoading {
                ProgressView()
                    .frame(width: 36, height: 36)
            } else {
                Image("corporations_default")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }
        }
        .onAppear {
            if iconFileName.isEmpty {
                isLoading = true
                Task {
                    do {
                        corporationLogo = try await CorporationAPI.shared.fetchCorporationLogo(
                            corporationId: corporationId)
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
            if !viewModel.loyaltyPoints.isEmpty {
                Section(NSLocalizedString("Main_LP_Basic_Info", comment: "")) {
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
                                .cornerRadius(6)
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
                            NavigationLink(
                                destination: CorporationLPStoreView(
                                    corporationId: loyalty.corporationId,
                                    corporationName: loyalty.corporationName
                                )
                            ) {
                                HStack {
                                    CorporationLogoView(
                                        corporationId: loyalty.corporationId,
                                        iconFileName: loyalty.iconFileName
                                    )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(loyalty.corporationName)
                                            .contextMenu {
                                                Button {
                                                    UIPasteboard.general.string = loyalty.corporationName
                                                } label: {
                                                    Label(
                                                        NSLocalizedString("Misc_Copy_Name", comment: ""),
                                                        systemImage: "doc.on.doc"
                                                    )
                                                }
                                                if !loyalty.enName.isEmpty && loyalty.enName != loyalty.corporationName {
                                                    Button {
                                                        UIPasteboard.general.string = loyalty.enName
                                                    } label: {
                                                        Label(
                                                            NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                                            systemImage: "translate"
                                                        )
                                                    }
                                                }
                                            }
                                        Text("\(loyalty.loyaltyPoints) LP")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if loyalty.isMilitia {
                                        Text(NSLocalizedString("Main_LP_Militia", comment: ""))
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.8))
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            } else if viewModel.isLoading {
                Section(NSLocalizedString("Main_LP_Basic_Info", comment: "")) {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }

            Section(NSLocalizedString("Main_LP_Store", comment: "")) {
                NavigationLink(destination: CharacterLoyaltyPointsStoreView()) {
                    HStack {
                        Image("lpstore")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
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
