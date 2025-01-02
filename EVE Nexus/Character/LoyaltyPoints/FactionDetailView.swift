import SwiftUI

struct FactionDetailView: View {
    let faction: Faction
    @State private var corporations: [Corporation] = []
    @State private var isLoading = true
    @State private var error: Error?
    
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
                        .cornerRadius(6)
                    Text(error.localizedDescription)
                        .font(.headline)
                    Button(NSLocalizedString("Main_Setting_Reset", comment: "")) {
                        loadCorporations()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ForEach(corporations) { corporation in
                    NavigationLink(destination: CorporationLPStoreView(corporationId: corporation.id, corporationName: corporation.name)) {
                        HStack {
                            IconManager.shared.loadImage(for: corporation.iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                            
                            Text(corporation.name)
                                .padding(.leading, 8)
                        }
                        .padding(.vertical, 2)
                        .frame(height: 36)
                    }
                }
            }
        }
        .navigationTitle(faction.name)
        .onAppear {
            loadCorporations()
        }
    }
    
    private func loadCorporations() {
        isLoading = true
        error = nil
        
        let query = """
            SELECT c.corporation_id, c.name, c.faction_id, i.iconFile_new
            FROM npcCorporations c
            LEFT JOIN iconIDs i ON c.icon_id = i.icon_id
            WHERE c.faction_id = ?
            ORDER BY c.name
        """
        
        let result = DatabaseManager.shared.executeQuery(query, parameters: [faction.id])
        switch result {
        case .success(let rows):
            corporations = rows.compactMap { Corporation(from: $0) }
            isLoading = false
        case .error(let errorMessage):
            error = NSError(domain: "com.eve.nexus", 
                          code: -1, 
                          userInfo: [NSLocalizedDescriptionKey: errorMessage])
            isLoading = false
        }
    }
}
