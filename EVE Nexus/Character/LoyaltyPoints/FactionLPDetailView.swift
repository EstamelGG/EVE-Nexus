import SwiftUI

struct Faction: Identifiable {
    let id: Int
    let name: String
    let enName: String
    let zhName: String
    let iconName: String
    var corporations: [Corporation]

    init?(from row: [String: Any], corporations: [Corporation] = []) {
        guard let id = row["faction_id"] as? Int,
            let name = row["faction_name"] as? String,
            let enName = row["faction_en_name"] as? String,
            let zhName = row["faction_zh_name"] as? String,
            let iconName = row["faction_icon"] as? String
        else {
            return nil
        }
        self.id = id
        self.name = name
        self.enName = enName
        self.zhName = zhName
        self.iconName = iconName
        self.corporations = corporations
    }
}

struct Corporation: Identifiable {
    let id: Int
    let name: String
    let enName: String
    let zhName: String
    let factionId: Int
    let iconFileName: String

    init?(from row: [String: Any]) {
        guard let corporationId = row["corporation_id"] as? Int,
            let name = row["corp_name"] as? String,
            let enName = row["corp_en_name"] as? String,
            let zhName = row["corp_zh_name"] as? String,
            let factionId = row["faction_id"] as? Int
        else {
            return nil
        }

        id = corporationId
        self.name = name
        self.enName = enName
        self.zhName = zhName
        self.factionId = factionId
        self.iconFileName =
            (row["icon_filename"] as? String)?.isEmpty == true
            ? "corporations_default" : (row["icon_filename"] as? String ?? "corporations_default")
    }
}


struct FactionLPDetailView: View {
    let faction: Faction
    @State private var searchText = ""

    private var filteredCorporations: [Corporation] {
        if searchText.isEmpty {
            return faction.corporations
        } else {
            return faction.corporations.filter { corporation in
                corporation.name.localizedCaseInsensitiveContains(searchText) ||
                corporation.enName.localizedCaseInsensitiveContains(searchText) ||
                corporation.zhName.localizedCaseInsensitiveContains(searchText)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            Section(NSLocalizedString("Main_LP_Store_Corps", comment: "")) {
                if filteredCorporations.isEmpty && !searchText.isEmpty {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
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
    }
}
