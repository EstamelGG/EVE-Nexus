import SwiftUI

/// 人物表单子页面：势力与军衔（懒加载；无势力数据时显示占位）
struct CharacterFactionPage: View {
    let character: EVECharacterInfo

    @State private var faction: (name: String, faction_id: Int, iconName: String)?
    @State private var rank: Int?
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                if let faction {
                    HStack {
                        factionIcon(faction.iconName)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Character_Faction", comment: ""))
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(faction.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let rank {
                        HStack {
                            factionIcon("\(faction.faction_id)_\(rank)")

                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Character_Rank", comment: ""))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(
                                    NSLocalizedString(
                                        "rank_\(faction.faction_id)_\(rank)", comment: ""
                                    )
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity)
                } else {
                    Text(NSLocalizedString("Character_No_Faction", comment: "无势力占位"))
                        .foregroundColor(.secondary)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .navigationTitle(NSLocalizedString("Character_Faction_And_Rank", comment: "势力与军衔"))
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func factionIcon(_ iconFileName: String) -> some View {
        IconManager.shared.loadImage(for: iconFileName)
            .resizable()
            .frame(width: 36, height: 36)
            .cornerRadius(6)
    }

    private func load() async {
        guard
            let publicInfo = try? await CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: character.CharacterID
            ),
            let factionId = publicInfo.faction_id,
            let factionInfo = SDEMemoryStore.faction(for: factionId)
        else {
            withAnimation(.easeInOut(duration: 0.3)) {
                isLoading = false
            }
            return
        }

        // 军衔需额外请求 FW 数据，不阻塞势力信息展示
        let fwStats = try? await CharacterFWStatsAPI.shared.getFWStats(
            characterId: character.CharacterID
        )

        withAnimation(.easeInOut(duration: 0.3)) {
            faction = (
                name: factionInfo.name,
                faction_id: factionId,
                iconName: factionInfo.iconName
            )
            rank = fwStats?.current_rank
            isLoading = false
        }
    }
}
