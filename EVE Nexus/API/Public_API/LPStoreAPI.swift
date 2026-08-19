import Foundation

struct LPStoreOffer: Codable {
    let akCost: Int
    let iskCost: Int
    let lpCost: Int
    let offerId: Int
    let quantity: Int
    let requiredItems: [RequiredItem]
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case akCost = "ak_cost"
        case iskCost = "isk_cost"
        case lpCost = "lp_cost"
        case offerId = "offer_id"
        case quantity
        case requiredItems = "required_items"
        case typeId = "type_id"
    }
}

struct RequiredItem: Codable {
    let quantity: Int
    let typeId: Int

    enum CodingKeys: String, CodingKey {
        case quantity
        case typeId = "type_id"
    }
}

// MARK: - LP商店API

@globalActor actor LPStoreAPIActor {
    static let shared = LPStoreAPIActor()
}

@LPStoreAPIActor
class LPStoreAPI {
    static let shared = LPStoreAPI()

    private init() {}

    // MARK: - 公共方法

    /// 获取单个军团的LP商店兑换列表
    /// - Parameters:
    ///   - corporationId: 军团ID
    /// - Returns: LP商店兑换列表
    func fetchCorporationLPStoreOffers(corporationId: Int) async throws -> [LPStoreOffer] {
        // 直接从 SDE 数据库读取数据
        return try await loadFromSDEDatabase(corporationId: corporationId)
    }

    // MARK: - 私有方法

    /// 从 SDE 内存索引加载单个军团的 LP 商店数据
    private func loadFromSDEDatabase(corporationId: Int) async throws -> [LPStoreOffer] {
        // 内存索引取该军团的 offer 列表
        guard let offerIds = SDEMemoryStore.loyaltyOffersByCorporation[corporationId],
              !offerIds.isEmpty
        else {
            return []
        }

        var offers: [LPStoreOffer] = []
        for offerId in offerIds.sorted() {
            guard let output = SDEMemoryStore.loyaltyOfferOutputs[offerId] else { continue }

            let requiredItems = (SDEMemoryStore.loyaltyOfferRequirements[offerId] ?? [])
                .map { RequiredItem(quantity: $0.quantity, typeId: $0.typeID) }

            offers.append(
                LPStoreOffer(
                    akCost: output.akCost,
                    iskCost: output.iskCost,
                    lpCost: output.lpCost,
                    offerId: offerId,
                    quantity: output.quantity,
                    requiredItems: requiredItems,
                    typeId: output.typeID
                )
            )
        }

        return offers
    }
}
