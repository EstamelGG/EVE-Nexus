import SwiftUI

struct Faction: Identifiable {
    let id: Int
    let name: String
    let iconName: String

    init?(from row: [String: Any]) {
        guard let id = row["id"] as? Int,
            let name = row["name"] as? String,
            let iconName = row["iconName"] as? String
        else {
            return nil
        }
        self.id = id
        self.name = name
        self.iconName = iconName
    }
}

struct FactionDetailView: View {
    let faction: Faction
    @State private var corporations: [Corporation] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var searchText = ""

    private var filteredCorporations: [Corporation] {
        if searchText.isEmpty {
            return corporations
        } else {
            return corporations.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                        .cornerRadius(6)
                    Text(error.localizedDescription)
                        .font(.headline)
                    Button(NSLocalizedString("Main_Setting_Reset", comment: "")) {
                        loadCorporations()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Section(NSLocalizedString("Main_LP_Store_Corps", comment: "")) {
                    ForEach(filteredCorporations) { corporation in
                        NavigationLink(
                            destination: CorporationLPStoreView(
                                corporationId: corporation.id, corporationName: corporation.name
                            )
                        ) {
                            HStack {
                                IconManager.shared.loadImage(for: corporation.iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36, height: 36)
                                    .cornerRadius(6)

                                Text(corporation.name)
                                    .padding(.leading, 8)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(faction.name)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        )
        .onAppear {
            loadCorporations()
        }
    }

    private func loadCorporations() {
        isLoading = true
        error = nil

        let query = """
                SELECT c.corporation_id, c.name, c.faction_id, c.icon_filename
                FROM npcCorporations c
                WHERE c.faction_id = ?
                ORDER BY c.name
            """

        let result = DatabaseManager.shared.executeQuery(query, parameters: [faction.id])
        switch result {
        case let .success(rows):
            corporations = rows.compactMap { Corporation(from: $0) }
            isLoading = false
        case let .error(errorMessage):
            error = NSError(
                domain: "com.eve.nexus",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
            isLoading = false
        }
    }
}
