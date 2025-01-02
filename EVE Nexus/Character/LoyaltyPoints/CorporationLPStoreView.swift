import SwiftUI

struct LPStoreOfferView: View {
    let offer: LPStoreOffer
    @State private var itemName: String = ""
    @State private var itemIconFileName: String = ""
    @State private var requiredItemNames: [String] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconManager.shared.loadImage(for: itemIconFileName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                
                VStack(alignment: .leading) {
                    Text(itemName)
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
            
            if !requiredItemNames.isEmpty {
                Text(NSLocalizedString("Main_LP_Required_Items", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(offer.requiredItems.indices, id: \.self) { index in
                    HStack {
                        Text("\(offer.requiredItems[index].quantity)x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(requiredItemNames[index])
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            loadItemInfo()
        }
    }
    
    private func loadItemInfo() {
        // 获取物品信息
        let query = """
            SELECT name, icon_filename
            FROM types
            WHERE type_id = ?
        """
        
        if case .success(let rows) = DatabaseManager.shared.executeQuery(query, parameters: [offer.typeId]),
           let row = rows.first,
           let name = row["name"] as? String,
           let iconFileName = row["icon_filename"] as? String {
            itemName = name
            itemIconFileName = iconFileName.isEmpty ? "items_7_64_15.png" : iconFileName
        }
        
        // 加载所需物品名称
        requiredItemNames = offer.requiredItems.compactMap { item in
            DatabaseManager.shared.getTypeName(for: item.typeId)
        }
    }
}

struct CorporationLPStoreView: View {
    let corporationId: Int
    @State private var offers: [LPStoreOffer] = []
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
                    LPStoreOfferView(offer: offer)
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
            offers = try await LPStoreAPI.shared.fetchLPStoreOffers(
                corporationId: corporationId,
                forceRefresh: forceRefresh
            )
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