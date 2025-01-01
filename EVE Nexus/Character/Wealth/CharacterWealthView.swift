import SwiftUI

struct CharacterWealthView: View {
    let characterId: Int
    @StateObject private var viewModel: CharacterWealthViewModel
    
    init(characterId: Int) {
        self.characterId = characterId
        self._viewModel = StateObject(wrappedValue: CharacterWealthViewModel(characterId: characterId))
    }
    
    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                // 总资产
                Section {
                    HStack {
                        Image("Folder")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .cornerRadius(6)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Wealth_Total", comment: ""))
                            Text(FormatUtil.format(viewModel.totalWealth) + " ISK")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 36)
                }
                
                // 资产明细
                Section {
                    ForEach(viewModel.wealthItems) { item in
                        HStack {
                            Image(item.type.icon)
                                .resizable()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Wealth_" + item.type.rawValue, comment: ""))
                                Text(item.details)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(item.formattedValue + " ISK")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(height: 36)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Wealth", comment: ""))
        .task {
            await viewModel.loadWealthData()
        }
        .refreshable {
            await viewModel.loadWealthData(forceRefresh: true)
        }
    }
} 