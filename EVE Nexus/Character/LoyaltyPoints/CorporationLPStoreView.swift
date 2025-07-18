import SwiftUI

struct CategoryInfo {
    let name: String
    let iconFileName: String
}

struct LPStoreItemInfo {
    let name: String
    let enName: String
    let zhName: String
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
            NavigationLink(
                destination: ItemInfoMap.getItemInfoView(
                    itemID: offer.typeId,
                    databaseManager: DatabaseManager.shared
                )
            ) {
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
                                Text("\(FormatUtil.formatISK(Double(offer.iskCost)))")
                                    .foregroundColor(.green)
                            }
                        }
                        .font(.subheadline)
                    }
                }
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = itemInfo.name
                    } label: {
                        Label(NSLocalizedString("Misc_Copy_LP_Offer_Name", comment: ""), systemImage: "doc.on.doc")
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
            return offers
        } else {
            return offers.filter { offer in
                if let itemInfo = itemInfos[offer.typeId] {
                    return itemInfo.name.localizedCaseInsensitiveContains(searchText) ||
                           itemInfo.enName.localizedCaseInsensitiveContains(searchText) ||
                           itemInfo.zhName.localizedCaseInsensitiveContains(searchText)
                }
                return false
            }
        }
    }

    var body: some View {
        List {
            Section(NSLocalizedString("Main_LP_Store_section", comment: "")) {
                if !searchText.isEmpty && filteredOffers.isEmpty {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
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

struct CategoryOffers {
    let category: CategoryInfo
    var offers: [LPStoreOffer]
}

struct CorporationLPStoreView: View {
    let corporationId: Int
    let corporationName: String
    @State private var offers: [LPStoreOffer] = []
    @State private var itemInfos: [Int: LPStoreItemInfo] = [:]
    @State private var categoryInfos: [Int: CategoryInfo] = [:]
    @State private var categoryOffers: [CategoryOffers] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var hasLoadedData = false
    @State private var searchText = ""

    private var filteredOffers: [LPStoreOffer] {
        if searchText.isEmpty {
            return []
        }
        
        var matchedOffers: [LPStoreOffer] = []
        for category in categoryOffers {
            let filteredOffers = category.offers.filter { offer in
                if let itemInfo = itemInfos[offer.typeId] {
                    return itemInfo.name.localizedCaseInsensitiveContains(searchText) ||
                           itemInfo.enName.localizedCaseInsensitiveContains(searchText) ||
                           itemInfo.zhName.localizedCaseInsensitiveContains(searchText)
                }
                return false
            }
            matchedOffers.append(contentsOf: filteredOffers)
        }
        
        return matchedOffers.sorted { offer1, offer2 in
            if let info1 = itemInfos[offer1.typeId],
               let info2 = itemInfos[offer2.typeId] {
                return info1.name.localizedStandardCompare(info2.name) == .orderedAscending
            }
            return false
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
                        Task {
                            await loadOffers()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if offers.isEmpty {
                Section {
                    NoDataSection()
                }
                .listSectionSpacing(.compact)
            } else {
                if !searchText.isEmpty {
                    if filteredOffers.isEmpty {
                        Section {
                            HStack {
                                Spacer()
                                Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    } else {
                        Section(NSLocalizedString("Main_Search_Results", comment: "")) {
                            ForEach(filteredOffers, id: \.offerId) { offer in
                                if let itemInfo = itemInfos[offer.typeId] {
                                    LPStoreOfferView(
                                        offer: offer,
                                        itemInfo: itemInfo,
                                        requiredItemInfos: itemInfos
                                    )
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                } else {
                    Section(NSLocalizedString("Main_LP_Store_category", comment: "")) {
                        ForEach(categoryOffers, id: \.category.name) { category in
                            NavigationLink(
                                destination: LPStoreGroupView(
                                    categoryName: category.category.name,
                                    offers: category.offers,
                                    itemInfos: itemInfos
                                )
                            ) {
                                HStack {
                                    IconManager.shared.loadImage(for: category.category.iconFileName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36)
                                        .cornerRadius(6)
                                    Text(category.category.name)
                                        .padding(.leading, 8)

                                    Spacer()
                                    Text("\(category.offers.count)")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
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
            offers = try await LPStoreAPI.shared.fetchCorporationLPStoreOffers(
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
                    SELECT type_id, name, en_name, zh_name, icon_filename, bpc_icon_filename, category_name, categoryID
                    FROM types
                    WHERE type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ",")))
                """

            if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                var infos: [Int: LPStoreItemInfo] = [:]
                var categoryIds = Set<Int>()

                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                        let name = row["name"] as? String,
                        let enName = row["en_name"] as? String,
                        let zhName = row["zh_name"] as? String,
                        let iconFileName = row["icon_filename"] as? String,
                        let categoryName = row["category_name"] as? String,
                        let categoryId = row["categoryID"] as? Int
                    {
                        let bpcIconFileName = row["bpc_icon_filename"] as? String
                        let finalIconFileName: String

                        if let bpcIcon = bpcIconFileName, !bpcIcon.isEmpty {
                            finalIconFileName = bpcIcon
                        } else {
                            finalIconFileName = iconFileName.isEmpty ? "not_found" : iconFileName
                        }

                        infos[typeId] = LPStoreItemInfo(
                            name: name,
                            enName: enName,
                            zhName: zhName,
                            iconFileName: finalIconFileName,
                            categoryName: categoryName,
                            categoryId: categoryId
                        )
                        categoryIds.insert(categoryId)
                    }
                }
                itemInfos = infos

                // 4. 获取分类信息
                if !categoryIds.isEmpty {
                    let categoryQuery = """
                            SELECT category_id, name, icon_filename
                            FROM categories
                            WHERE category_id IN (\(categoryIds.sorted().map { String($0) }.joined(separator: ",")))
                        """

                    if case let .success(categoryRows) = DatabaseManager.shared.executeQuery(
                        categoryQuery)
                    {
                        var categories: [Int: CategoryInfo] = [:]
                        for row in categoryRows {
                            if let categoryId = row["category_id"] as? Int,
                                let name = row["name"] as? String,
                                let iconFileName = row["icon_filename"] as? String
                            {
                                categories[categoryId] = CategoryInfo(
                                    name: name,
                                    iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName
                                )
                            }
                        }
                        categoryInfos = categories
                    }
                }

                // 5. 按目录组织物品
                var categoryOffersDict: [Int: [LPStoreOffer]] = [:]
                for offer in offers {
                    if let categoryId = itemInfos[offer.typeId]?.categoryId {
                        categoryOffersDict[categoryId, default: []].append(offer)
                    }
                }

                // 6. 转换为数组并排序
                categoryOffers = categoryOffersDict.compactMap { id, offers in
                    guard let categoryInfo = categoryInfos[id] else { return nil }
                    return CategoryOffers(
                        category: categoryInfo,
                        offers: offers.sorted { offer1, offer2 in
                            if let info1 = itemInfos[offer1.typeId],
                               let info2 = itemInfos[offer2.typeId] {
                                return info1.name.localizedStandardCompare(info2.name) == .orderedAscending
                            }
                            return false
                        }
                    )
                }.sorted { $0.category.name.localizedStandardCompare($1.category.name) == .orderedAscending }
            }

            isLoading = false
            hasLoadedData = true
        } catch {
            self.error = error
            isLoading = false
        }
    }
}
