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
                        .frame(width: 36)
                    
                    VStack(alignment: .leading) {
                        Text("\(offer.quantity)x \(itemInfo.name)")
                            .font(.headline)
                            .lineLimit(1)
                        
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
                    }
                }
            }
            .buttonStyle(.plain)
            
            if !offer.requiredItems.isEmpty {
                Text(NSLocalizedString("Main_LP_Required_Items", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                let sortedItems = offer.requiredItems.sorted { $0.typeId < $1.typeId }
                ForEach(sortedItems, id: \.typeId) { item in
                    if let info = requiredItemInfos[item.typeId] {
                        HStack {
                            IconManager.shared.loadImage(for: info.iconFileName)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(6)
                                .frame(width: 24, height: 24)
                            
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
    @State private var searchText = ""
    
    private var filteredOffers: [LPStoreOffer] {
        if searchText.isEmpty {
            return sortedOffers
        } else {
            return sortedOffers.filter { offer in
                if let itemInfo = itemInfos[offer.typeId] {
                    return itemInfo.name.localizedCaseInsensitiveContains(searchText)
                }
                return false
            }
        }
    }
    
    private var sortedOffers: [LPStoreOffer] {
        offers.sorted { offer1, offer2 in
            if offer1.typeId != offer2.typeId {
                return offer1.typeId < offer2.typeId
            }
            if offer1.lpCost != offer2.lpCost {
                return offer1.lpCost < offer2.lpCost
            }
            return offer1.iskCost < offer2.iskCost
        }
    }
    
    var body: some View {
        List {
            ForEach(filteredOffers, id: \.offerId) { offer in
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        )
    }
}

struct CorporationLPStoreView: View {
    let corporationId: Int
    let corporationName: String
    @State private var offers: [LPStoreOffer] = []
    @State private var itemInfos: [Int: LPStoreItemInfo] = [:]
    @State private var categoryInfos: [String: CategoryInfo] = [:]
    @State private var isLoading = true
    @State private var error: Error?
    @State private var hasLoadedData = false
    @State private var searchText = ""
    
    private var filteredCategoryOffers: [(CategoryInfo, [LPStoreOffer])] {
        let groups = Dictionary(grouping: offers) { offer in
            itemInfos[offer.typeId]?.categoryName ?? ""
        }
        
        let filtered = groups.compactMap { name, offers -> (CategoryInfo, [LPStoreOffer])? in
            guard let categoryInfo = categoryInfos[name] else { return nil }
            
            if searchText.isEmpty {
                return (categoryInfo, offers)
            } else {
                let filteredOffers = offers.filter { offer in
                    if let itemInfo = itemInfos[offer.typeId] {
                        return itemInfo.name.localizedCaseInsensitiveContains(searchText)
                    }
                    return false
                }
                return filteredOffers.isEmpty ? nil : (categoryInfo, filteredOffers)
            }
        }.sorted { $0.0.name < $1.0.name }
        
        return filtered
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
            } else if offers.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 30))
                                .foregroundColor(.gray)
                            Text(NSLocalizedString("Orders_No_Data", comment: ""))
                                .foregroundColor(.gray)
                        }
                        .padding()
                        Spacer()
                    }
                }
                .listSectionSpacing(.compact)
            } else {
                ForEach(filteredCategoryOffers, id: \.0.name) { categoryInfo, offers in
                    NavigationLink(destination: LPStoreGroupView(
                        categoryName: categoryInfo.name,
                        offers: offers,
                        itemInfos: itemInfos
                    )) {
                        HStack {
                            IconManager.shared.loadImage(for: categoryInfo.iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36)
                                .cornerRadius(6)
                            Text(categoryInfo.name)
                                .padding(.leading, 8)
                            
                            Spacer()
                            Text("\(offers.count)")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(corporationName)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        )
        .refreshable {
            await loadOffers(forceRefresh: true)
        }
        .task {
            if !hasLoadedData {
                await loadOffers()
            }
        }
    }
    
    private func loadOffers(forceRefresh: Bool = false) async {
        if hasLoadedData && !forceRefresh {
            return
        }
        
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
                            iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName,
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
                                    iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName
                                )
                            }
                        }
                        categoryInfos = categories
                    }
                }
            }
            
            isLoading = false
            hasLoadedData = true
        } catch {
            self.error = error
            isLoading = false
        }
    }
}
