import SwiftUI

struct CharacterLoyaltyPointsStoreView: View {
    @State private var factions: [Faction] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var hasLoadedData = false
    @State private var searchText = ""
    
    private var filteredFactions: [Faction] {
        if searchText.isEmpty {
            return factions
        } else {
            return factions.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .font(.headline)
                    Button(NSLocalizedString("Main_Setting_Reset", comment: "")) {
                        loadFactions()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ForEach(filteredFactions) { faction in
                    NavigationLink(destination: FactionDetailView(faction: faction)) {
                        HStack {
                            IconManager.shared.loadImage(for: faction.iconName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36)
                            
                            Text(faction.name)
                                .padding(.leading, 8)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("Main_LP_Store", comment: ""))
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        )
        .onAppear {
            if !hasLoadedData {
                loadFactions()
            }
        }
    }
    
    private func loadFactions() {
        if hasLoadedData {
            return
        }
        
        isLoading = true
        error = nil
        
        let query = """
            SELECT * FROM factions
        """
        
        let result = DatabaseManager.shared.executeQuery(query)
        switch result {
        case .success(let rows):
            factions = rows.compactMap { Faction(from: $0) }
            isLoading = false
            hasLoadedData = true
        case .error(let errorMessage):
            error = NSError(domain: "com.eve.nexus", 
                          code: -1, 
                          userInfo: [NSLocalizedDescriptionKey: errorMessage])
            isLoading = false
        }
    }
}

