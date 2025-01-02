import SwiftUI

struct CategoryInfo {
    let name: String
    let iconFileName: String
}

struct LPStoreItemInfo {
    let name: String
    let iconFileName: String
    let categoryName: String
    let categoryId: Int
}

struct LPStoreOfferView: View {
    let offer: LPStoreOffer
    let itemInfo: LPStoreItemInfo
    let requiredItemInfos: [Int: LPStoreItemInfo]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            NavigationLink(destination: ItemInfoMap.getItemInfoView(
                itemID: offer.typeId,
                categoryID: itemInfo.categoryId,
                databaseManager: DatabaseManager.shared
            )) {
                HStack {
                    IconManager.shared.loadImage(for: itemInfo.iconFileName)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(6)
                        .frame(width: 36, height: 36)
                    
                    VStack(alignment: .leading) {
                        Text(itemInfo.name)
                            .font(.headline)
                        Text("\(offer.quantity)x")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            
            HStack(spacing: 4) {
                if offer.lpCost > 0 {
                    Text("\(offer.lpCost) LP")
                        .foregroundColor(.blue)
                }
                
                if offer.lpCost > 0 && offer.iskCost > 0 {
                    Text("+")
                }
                
                if offer.iskCost > 0 {
                    Text("\(FormatUtil.formatISK(Double(offer.iskCost))) ISK")
                        .foregroundColor(.green)
                }
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
        .padding(.vertical, 2)
    }
}

struct LPStoreGroupView: View {
    let categoryName: String
    let offers: [LPStoreOffer]
    let itemInfos: [Int: LPStoreItemInfo]
    
    var body: some View {
        List {
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
        .navigationTitle(categoryName)
    }
}

struct CorporationLPStoreView: View {
    let corporationId: Int
    @State private var offers: [LPStoreOffer] = []
    @State private var itemInfos: [Int: LPStoreItemInfo] = [:]
    @State private var categoryInfos: [String: CategoryInfo] = [:]
    @State private var isLoading = true
    @State private var error: Error?
    
    private var categoryOffers: [(CategoryInfo, [LPStoreOffer])] {
        let groups = Dictionary(grouping: offers) { offer in
            itemInfos[offer.typeId]?.categoryName ?? ""
        }
        return groups.compactMap { name, offers in
            guard let categoryInfo = categoryInfos[name] else { return nil }
            return (categoryInfo, offers)
        }.sorted { $0.0.name < $1.0.name }
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
                        Task {
                            await loadOffers()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ForEach(categoryOffers, id: \.0.name) { categoryInfo, offers in
                    NavigationLink(destination: LPStoreGroupView(
                        categoryName: categoryInfo.name,
                        offers: offers,
                        itemInfos: itemInfos
                    )) {
                        HStack {
                            IconManager.shared.loadImage(for: categoryInfo.iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .cornerRadius(6)
                            Text(categoryInfo.name)
                                .padding(.leading, 8)
                            
                            Spacer()
                            Text("\(offers.count)")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: 36)
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
                SELECT type_id, name, icon_filename, category_name, categoryID
                FROM types
                WHERE type_id IN (\(typeIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                var infos: [Int: LPStoreItemInfo] = [:]
                var categoryNames = Set<String>()
                
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let name = row["name"] as? String,
                       let iconFileName = row["icon_filename"] as? String,
                       let categoryName = row["category_name"] as? String,
                       let categoryId = row["categoryID"] as? Int {
                        infos[typeId] = LPStoreItemInfo(
                            name: name,
                            iconFileName: iconFileName.isEmpty ? "items_7_64_15.png" : iconFileName,
                            categoryName: categoryName,
                            categoryId: categoryId
                        )
                        categoryNames.insert(categoryName)
                    }
                }
                itemInfos = infos
                
                // 4. 获取分类信息
                if !categoryNames.isEmpty {
                    let categoryQuery = """
                        SELECT name, icon_filename
                        FROM categories
                        WHERE name IN (\(categoryNames.map { "'\($0)'" }.joined(separator: ",")))
                    """
                    
                    if case .success(let categoryRows) = DatabaseManager.shared.executeQuery(categoryQuery) {
                        var categories: [String: CategoryInfo] = [:]
                        for row in categoryRows {
                            if let name = row["name"] as? String,
                               let iconFileName = row["icon_filename"] as? String {
                                categories[name] = CategoryInfo(
                                    name: name,
                                    iconFileName: iconFileName.isEmpty ? "items_7_64_15.png" : iconFileName
                                )
                            }
                        }
                        categoryInfos = categories
                    }
                }
            }
            
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
}
