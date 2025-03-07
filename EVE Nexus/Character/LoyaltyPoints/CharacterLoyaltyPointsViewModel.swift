import Foundation
import SwiftUI

struct CorporationLoyaltyInfo: Identifiable {
    let id: Int
    let corporationId: Int
    let loyaltyPoints: Int
    let corporationName: String
    let iconFileName: String
}

@MainActor
class CharacterLoyaltyPointsViewModel: ObservableObject {
    @Published var loyaltyPoints: [CorporationLoyaltyInfo] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var hasLoadedData = false

    func fetchLoyaltyPoints(characterId: Int, forceRefresh: Bool = false) {
        if hasLoadedData && !forceRefresh {
            return
        }

        isLoading = true
        error = nil

        Task {
            await loadLoyaltyPoints(characterId: characterId, forceRefresh: forceRefresh)
        }
    }

    func refreshLoyaltyPoints(characterId: Int) async {
        isLoading = true
        error = nil
        await loadLoyaltyPoints(characterId: characterId, forceRefresh: true)
    }

    private func loadLoyaltyPoints(characterId: Int, forceRefresh: Bool) async {
        do {
            let points = try await CharacterLoyaltyPointsAPI.shared.fetchLoyaltyPoints(
                characterId: characterId, forceRefresh: forceRefresh
            )
            var corporationInfo: [CorporationLoyaltyInfo] = []

            for point in points {
                if let corpInfo = try await getCorporationInfo(corporationId: point.corporation_id)
                {
                    corporationInfo.append(
                        CorporationLoyaltyInfo(
                            id: point.corporation_id,
                            corporationId: point.corporation_id,
                            loyaltyPoints: point.loyalty_points,
                            corporationName: corpInfo.name,
                            iconFileName: corpInfo.iconFileName
                        ))
                }
            }

            loyaltyPoints = corporationInfo.sorted(by: { $0.corporationId < $1.corporationId })
            hasLoadedData = true
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    private func getCorporationInfo(corporationId: Int) async throws -> (
        name: String, iconFileName: String
    )? {
        let query = """
                SELECT name, icon_id FROM npcCorporations WHERE corporation_id = \(corporationId)
            """

        guard case let .success(rows) = SQLiteManager.shared.executeQuery(query),
            let result = rows.first,
            let name = result["name"] as? String,
            let iconId = result["icon_id"] as? Int
        else {
            return nil
        }

        let iconQuery = """
                SELECT iconFile_new FROM iconIDs WHERE icon_id = \(iconId)
            """

        guard case let .success(iconRows) = SQLiteManager.shared.executeQuery(iconQuery),
            let iconResult = iconRows.first,
            let iconFileName = iconResult["iconFile_new"] as? String
        else {
            return (name, "")
        }

        return (name, iconFileName)
    }
}
