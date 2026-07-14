import Foundation
import SwiftUI

struct CorporationLoyaltyInfo: Identifiable {
    let id: Int
    let corporationId: Int
    let loyaltyPoints: Int
    let enName: String
    let zhName: String
    let iconFileName: String
    let militiaFaction: Int?

    var corporationName: String {
        SDEMemoryStore.npcCorporation(for: corporationId)?.name ?? "Corp \(corporationId)"
    }

    var isMilitia: Bool {
        if let militia = militiaFaction, militia > 0 {
            return true
        }
        return false
    }
}

@MainActor
class CharacterLoyaltyPointsViewModel: ObservableObject {
    @Published var loyaltyPoints: [CorporationLoyaltyInfo] = []
    @Published var isLoading = false
    @Published var error: Error?

    private var hasLoadedData = false

    func fetchLoyaltyPoints(characterId: Int, forceRefresh: Bool = false) {
        if hasLoadedData, !forceRefresh {
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

            let corporationIds = points.map(\.corporation_id)
            let corpInfoMap = getCorporationInfos(corporationIds: corporationIds)

            let corporationInfo = points.compactMap { point -> CorporationLoyaltyInfo? in
                guard let corpInfo = corpInfoMap[point.corporation_id] else { return nil }
                return CorporationLoyaltyInfo(
                    id: point.corporation_id,
                    corporationId: point.corporation_id,
                    loyaltyPoints: point.loyalty_points,
                    enName: corpInfo.enName,
                    zhName: corpInfo.zhName,
                    iconFileName: corpInfo.iconFileName,
                    militiaFaction: corpInfo.militiaFaction
                )
            }

            loyaltyPoints = corporationInfo.sorted(by: { $0.corporationId < $1.corporationId })
            hasLoadedData = true
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    private func getCorporationInfos(corporationIds: [Int]) -> [Int: (
        enName: String, zhName: String, iconFileName: String, militiaFaction: Int?
    )] {
        var result: [Int: (
            enName: String, zhName: String, iconFileName: String, militiaFaction: Int?
        )] = [:]
        for id in corporationIds {
            guard let corp = SDEMemoryStore.npcCorporation(for: id) else { continue }
            result[id] = (
                corp.enName, corp.zhName, corp.iconFilename, corp.militiaFaction
            )
        }
        return result
    }
}
