import SwiftUI

struct LPStoreItemInfo {
    let name: String
    let iconFileName: String
}

struct LPStoreOfferView: View {
    let offer: LPStoreOffer
    let itemInfo: LPStoreItemInfo
    let requiredItemInfos: [Int: LPStoreItemInfo]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconManager.shared.loadImage(for: itemInfo.iconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading) {
                    Text(itemInfo.name)
                        .font(.headline)
                    Text("\(offer.quantity)x")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                Text("\(offer.lpCost) LP")
                    .foregroundColor(.blue)
                Text("+")
                Text("\(FormatUtil.formatISK(Double(offer.iskCost))) ISK")
                    .foregroundColor(.green)
            }
            .font(.subheadline)
            
            if !offer.requiredItems.isEmpty {
                Text(NSLocalizedString("Main_LP_Required_Items", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(offer.requiredItems, id: \.typeId) { item in
                    if let info = requiredItemInfos[item.typeId] {
                        HStack {
                            Text("\(item.quantity)x")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(info.name)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct CorporationLPStoreView: View {
    let corporationId: Int
    @State private var offers: [LPStoreOffer] = []
    @State private var itemInfos: [Int: LPStoreItemInfo] = [:]
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
                    Text(error.localizedDescription)
                        .font(.headline)
                    Button(NSLocalizedString("Main_Setting_Reset", comment: "")) {
                        Task {
                            await loadOffers()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ForEach(offers, id: \.offerId) { offer in
                    if let itemInfo = itemInfos[offer.typeId] {
                        LPStoreOfferView(
                            offer: offer,
                            itemInfo: itemInfo,
                            requiredItemInfos: itemInfos
                        )
                    }
                }
            }
        }
        .refreshable {
            await loadOffers(forceRefresh: true)
        }
        .task {
            await loadOffers()
        }
    }
    
    private func loadOffers(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        
        do {
            // 1. 获取所有商品
            offers = try await LPStoreAPI.shared.fetchLPStoreOffers(
                corporationId: corporationId,
                forceRefresh: forceRefresh
            )
            
            // 2. 收集所有需要查询的物品ID
            var typeIds = Set<Int>()
            typeIds.formUnion(offers.map { $0.typeId })
            for offer in offers {
                typeIds.formUnion(offer.requiredItems.map { $0.typeId })
            }
            
            // 3. 一次性查询所有物品信息
            let query = """
                SELECT type_id, name, icon_filename
                FROM types
                WHERE type_id IN (\(typeIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                var infos: [Int: LPStoreItemInfo] = [:]
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let name = row["name"] as? String,
                       let iconFileName = row["icon_filename"] as? String {
                        infos[typeId] = LPStoreItemInfo(
                            name: name,
                            iconFileName: iconFileName.isEmpty ? "items_7_64_15.png" : iconFileName
                        )
                    }
                }
                itemInfos = infos
            }
            
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

#Preview {
    NavigationView {
        CorporationLPStoreView(corporationId: 1000035)
    }
} 