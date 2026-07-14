import SwiftUI

// MARK: - 搜索相关数据模型

struct LPSearchResult {
    let categoryId: Int
    let categoryName: String
    let categoryIcon: String
    let offerCount: Int
    let offers: [LPSearchOffer]
}

struct LPSearchOffer {
    let typeId: Int
    let typeName: String
    let typeIcon: String
    let offerId: Int
    let factionId: Int?
    let corporationId: Int
}

struct LPOfferSupplier {
    let factionId: Int?
    let factionName: String?
    let corporationId: Int
    let corporationName: String
    let corporationEnName: String
    let corporationIcon: String
    let militiaFaction: Int?

    var isMilitia: Bool {
        if let militia = militiaFaction, militia > 0 {
            return true
        }
        return false
    }
}

struct Faction: Identifiable {
    let id: Int
    let names: LocalizedText
    let iconName: String
    var corporations: [Corporation]

    var name: String {
        names.resolved()
    }

    var enName: String {
        names.en
    }

    func matches(_ query: String) -> Bool {
        names.matchesSearch(query)
    }

    init(id: Int, names: LocalizedText, iconName: String, corporations: [Corporation] = []) {
        self.id = id
        self.names = names
        self.iconName = iconName
        self.corporations = corporations
    }
}

struct Corporation: Identifiable {
    let id: Int
    let names: LocalizedText
    let factionId: Int
    let iconFileName: String
    let militiaFaction: Int?

    var name: String {
        names.resolved()
    }

    var enName: String {
        names.en
    }

    var isMilitia: Bool {
        if let militia = militiaFaction, militia > 0 {
            return true
        }
        return false
    }

    func matches(_ query: String) -> Bool {
        names.matchesSearch(query)
    }

    init(
        id: Int,
        names: LocalizedText,
        factionId: Int,
        iconFileName: String,
        militiaFaction: Int?
    ) {
        self.id = id
        self.names = names
        self.factionId = factionId
        self.iconFileName = iconFileName.isEmpty ? "corporations_default" : iconFileName
        self.militiaFaction = militiaFaction
    }
}

struct FactionLPDetailView: View {
    let faction: Faction
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var lpSearchResults: [LPSearchResult] = []
    @State private var isSearchingItems = false

    private var filteredCorporations: [Corporation] {
        if debouncedSearchText.isEmpty {
            return faction.corporations
        } else {
            return faction.corporations.filter { $0.matches(debouncedSearchText) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        List {
            if !debouncedSearchText.isEmpty {
                // 显示LP物品搜索结果
                if !lpSearchResults.isEmpty {
                    Section(NSLocalizedString("Main_LP_Available_Items", comment: "可用物品")) {
                        ForEach(lpSearchResults, id: \.categoryId) { category in
                            NavigationLink(
                                destination: LPSearchCategoryView(
                                    categoryName: category.categoryName,
                                    offers: category.offers
                                )
                            ) {
                                HStack {
                                    IconManager.shared.loadImage(for: category.categoryIcon)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36)
                                        .cornerRadius(6)
                                    Text(category.categoryName)
                                        .padding(.leading, 8)

                                    Spacer()
                                    Text("\(category.offerCount)")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }

                if filteredCorporations.isEmpty && lpSearchResults.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }

            if !filteredCorporations.isEmpty || debouncedSearchText.isEmpty {
                Section(NSLocalizedString("Main_LP_Store_Corps", comment: "")) {
                    ForEach(filteredCorporations) { corporation in
                        NavigationLink(
                            destination: CorporationLPStoreView(
                                corporationId: corporation.id, corporationName: corporation.name
                            )
                        ) {
                            HStack {
                                CorporationIconView(
                                    corporationId: corporation.id,
                                    iconFileName: corporation.iconFileName, size: 36
                                )

                                Text(corporation.name)
                                    .padding(.leading, 8)
                                    .contextMenu {
                                        Button {
                                            UIPasteboard.general.string = corporation.name
                                        } label: {
                                            Label(
                                                NSLocalizedString("Misc_Copy_Name", comment: ""),
                                                systemImage: "doc.on.doc"
                                            )
                                        }
                                        if !corporation.enName.isEmpty && corporation.enName != corporation.name {
                                            Button {
                                                UIPasteboard.general.string = corporation.enName
                                            } label: {
                                                Label(
                                                    NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                                    systemImage: "translate"
                                                )
                                            }
                                        }
                                    }

                                if corporation.isMilitia {
                                    Spacer()
                                    Text(NSLocalizedString("Main_LP_Militia", comment: ""))
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.8))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(faction.name)
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()

            if newValue.isEmpty {
                debouncedSearchText = ""
                lpSearchResults = []
                return
            }

            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                if !Task.isCancelled {
                    await MainActor.run {
                        debouncedSearchText = newValue
                        if !newValue.isEmpty {
                            searchLPItems(searchText: newValue, factionId: faction.id)
                        } else {
                            lpSearchResults = []
                        }
                    }
                }
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func searchLPItems(searchText: String, factionId: Int) {
        isSearchingItems = true

        Task {
            do {
                // 1. 从 SDE 数据库搜索该势力下的物品（全语种名称）
                let itemSearchQuery = """
                    SELECT DISTINCT
                        loo.type_id,
                        lo.offer_id,
                        nc.faction_id,
                        lo.corporation_id
                    FROM loyalty_offers lo
                    JOIN loyalty_offer_outputs loo ON lo.offer_id = loo.offer_id
                    LEFT JOIN npcCorporations nc ON lo.corporation_id = nc.corporation_id
                    LEFT JOIN types t ON loo.type_id = t.type_id
                    WHERE nc.faction_id = ?
                    AND \(LocalizedText.typeLangNameLikeSQL)
                """
                var nameParams: [Any] = [factionId]
                nameParams.append(contentsOf: LocalizedText.typeLangNameLikeParams(searchText))

                let itemResult = DatabaseManager.shared.executeQuery(
                    itemSearchQuery, parameters: nameParams
                )
                guard case let .success(itemRows) = itemResult else {
                    await MainActor.run {
                        isSearchingItems = false
                        lpSearchResults = []
                    }
                    return
                }

                // 收集type_ids
                var typeIds: Set<Int> = []
                var categoryIds: Set<Int> = []
                var searchOffers: [LPSearchOffer] = []

                for row in itemRows {
                    guard
                        let typeId = row["type_id"] as? Int,
                        let offerId = row["offer_id"] as? Int,
                        let corporationId = row["corporation_id"] as? Int
                    else {
                        continue
                    }

                    let searchFactionId = row["faction_id"] as? Int

                    typeIds.insert(typeId)
                    searchOffers.append(
                        LPSearchOffer(
                            typeId: typeId,
                            typeName: "",
                            typeIcon: "",
                            offerId: offerId,
                            factionId: searchFactionId,
                            corporationId: corporationId
                        )
                    )
                }

                if typeIds.isEmpty {
                    await MainActor.run {
                        isSearchingItems = false
                        lpSearchResults = []
                    }
                    return
                }

                // 2. 从DatabaseManager获取物品详细信息
                let typeQuery = """
                    SELECT type_id, name, icon_filename, categoryID 
                    FROM types 
                    WHERE type_id IN (\(typeIds.sorted().map { String($0) }.joined(separator: ","))) 
                    AND categoryID NOT IN (2118, 91)
                """

                let typeResult = DatabaseManager.shared.executeQuery(typeQuery)
                guard case let .success(typeRows) = typeResult else {
                    await MainActor.run {
                        isSearchingItems = false
                        lpSearchResults = []
                    }
                    return
                }

                var typeInfos: [Int: (name: String, icon: String, categoryId: Int)] = [:]

                for row in typeRows {
                    guard let typeId = row["type_id"] as? Int,
                          let name = row["name"] as? String,
                          let categoryId = row["categoryID"] as? Int
                    else {
                        continue
                    }
                    let iconFileName = row["icon_filename"] as? String ?? ""

                    typeInfos[typeId] = (
                        name, iconFileName.isEmpty ? "not_found" : iconFileName, categoryId
                    )
                    categoryIds.insert(categoryId)
                }

                // 3. 获取分类信息
                var categoryInfos: [Int: (name: String, icon: String)] = [:]
                if !categoryIds.isEmpty {
                    let categoryQuery = """
                        SELECT category_id, name, icon_filename 
                        FROM categories 
                        WHERE category_id IN (\(categoryIds.sorted().map { String($0) }.joined(separator: ",")))
                    """

                    if case let .success(categoryRows) = DatabaseManager.shared.executeQuery(
                        categoryQuery
                    ) {
                        for row in categoryRows {
                            guard let categoryId = row["category_id"] as? Int,
                                  let name = row["name"] as? String
                            else {
                                continue
                            }
                            let iconFileName = row["icon_filename"] as? String ?? ""

                            categoryInfos[categoryId] = (
                                name, iconFileName.isEmpty ? "not_found" : iconFileName
                            )
                        }
                    }
                }

                // 4. 组织搜索结果
                var categoryOffersDict: [Int: [LPSearchOffer]] = [:]

                for var offer in searchOffers {
                    guard let typeInfo = typeInfos[offer.typeId] else { continue }

                    // 更新offer信息
                    offer = LPSearchOffer(
                        typeId: offer.typeId,
                        typeName: typeInfo.name,
                        typeIcon: typeInfo.icon,
                        offerId: offer.offerId,
                        factionId: offer.factionId,
                        corporationId: offer.corporationId
                    )

                    categoryOffersDict[typeInfo.categoryId, default: []].append(offer)
                }

                // 5. 转换为最终结果，按type_id去重
                let results = categoryOffersDict.compactMap {
                    categoryId, offers -> LPSearchResult? in
                    guard let categoryInfo = categoryInfos[categoryId] else { return nil }

                    // 按type_id去重，每个物品类型只保留一个offer
                    var uniqueOffers: [Int: LPSearchOffer] = [:]
                    for offer in offers {
                        if uniqueOffers[offer.typeId] == nil {
                            uniqueOffers[offer.typeId] = offer
                        }
                    }

                    let deduplicatedOffers = Array(uniqueOffers.values).sorted {
                        $0.typeName.localizedStandardCompare($1.typeName) == .orderedAscending
                    }

                    return LPSearchResult(
                        categoryId: categoryId,
                        categoryName: categoryInfo.name,
                        categoryIcon: categoryInfo.icon,
                        offerCount: deduplicatedOffers.count,
                        offers: deduplicatedOffers
                    )
                }.sorted {
                    $0.categoryName.localizedStandardCompare($1.categoryName) == .orderedAscending
                }

                await MainActor.run {
                    isSearchingItems = false
                    lpSearchResults = results
                }
            }
        }
    }
}

// MARK: - LP搜索相关视图

struct LPSearchCategoryView: View {
    let categoryName: String
    let offers: [LPSearchOffer]
    @State private var searchText = ""

    private var uniqueFilteredOffers: [LPSearchOffer] {
        let filtered: [LPSearchOffer]
        if searchText.isEmpty {
            filtered = offers
        } else {
            filtered = offers.filter { offer in
                offer.typeName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // 按type_id去重，每个物品类型只保留一个
        var uniqueOffers: [Int: LPSearchOffer] = [:]
        for offer in filtered {
            if uniqueOffers[offer.typeId] == nil {
                uniqueOffers[offer.typeId] = offer
            }
        }

        return uniqueOffers.values.sorted {
            $0.typeName.localizedStandardCompare($1.typeName) == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section(NSLocalizedString("Main_LP_Store_Items", comment: "物品")) {
                if !searchText.isEmpty && uniqueFilteredOffers.isEmpty {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    ForEach(uniqueFilteredOffers, id: \.typeId) { offer in
                        NavigationLink(
                            destination: LPItemSuppliersView(offer: offer)
                        ) {
                            HStack {
                                IconManager.shared.loadImage(for: offer.typeIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 36)
                                    .cornerRadius(6)
                                Text(offer.typeName)
                                    .padding(.leading, 8)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(categoryName)
    }
}

struct LPItemSuppliersView: View {
    let offer: LPSearchOffer
    @State private var suppliers: [LPOfferSupplier] = []
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
                        loadSuppliers()
                    }
                    .buttonStyle(.bordered)
                }
            } else if suppliers.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                // 按势力分组显示供应商
                let factionGroups = Dictionary(grouping: suppliers) { $0.factionId }
                let sortedFactionIds = factionGroups.keys.sorted { factionId1, factionId2 in
                    let faction1Name =
                        suppliers.first { $0.factionId == factionId1 }?.factionName ?? ""
                    let faction2Name =
                        suppliers.first { $0.factionId == factionId2 }?.factionName ?? ""
                    return faction1Name.localizedStandardCompare(faction2Name) == .orderedAscending
                }

                ForEach(sortedFactionIds, id: \.self) { factionId in
                    let factionSuppliers = factionGroups[factionId] ?? []
                    let factionName =
                        factionSuppliers.first?.factionName
                            ?? NSLocalizedString("Main_LP_Unknown_Faction", comment: "未知势力")

                    Section(factionName) {
                        ForEach(factionSuppliers, id: \.corporationId) { supplier in
                            NavigationLink(
                                destination: SpecificItemOfferView(
                                    corporationId: supplier.corporationId,
                                    corporationName: supplier.corporationName,
                                    targetTypeId: offer.typeId,
                                    itemInfo: LPStoreItemInfo(
                                        names: SDEMemoryStore.type(for: offer.typeId)?.names
                                            ?? LocalizedText(
                                                de: offer.typeName, en: offer.typeName,
                                                es: offer.typeName, fr: offer.typeName,
                                                ja: offer.typeName, ko: offer.typeName,
                                                ru: offer.typeName, zh: offer.typeName
                                            ),
                                        iconFileName: offer.typeIcon,
                                        categoryName: "",
                                        categoryId: 0
                                    )
                                )
                            ) {
                                HStack {
                                    CorporationIconView(
                                        corporationId: supplier.corporationId,
                                        iconFileName: supplier.corporationIcon,
                                        size: 36
                                    )
                                    Text(supplier.corporationName)
                                        .padding(.leading, 8)
                                        .contextMenu {
                                            Button {
                                                UIPasteboard.general.string = supplier.corporationName
                                            } label: {
                                                Label(
                                                    NSLocalizedString("Misc_Copy_Name", comment: ""),
                                                    systemImage: "doc.on.doc"
                                                )
                                            }
                                            if !supplier.corporationEnName.isEmpty && supplier.corporationEnName != supplier.corporationName {
                                                Button {
                                                    UIPasteboard.general.string = supplier.corporationEnName
                                                } label: {
                                                    Label(
                                                        NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                                        systemImage: "translate"
                                                    )
                                                }
                                            }
                                        }

                                    if supplier.isMilitia {
                                        Spacer()
                                        Text(NSLocalizedString("Main_LP_Militia", comment: ""))
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.8))
                                            .foregroundColor(.white)
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
        }
        .navigationTitle(offer.typeName)
        .task {
            loadSuppliers()
        }
    }

    private func loadSuppliers() {
        isLoading = true
        error = nil

        Task {
            do {
                // 查询提供此物品的所有军团
                let itemSearchQuery = """
                    SELECT DISTINCT 
                        lo.corporation_id,
                        nc.faction_id
                    FROM loyalty_offers lo
                    JOIN loyalty_offer_outputs loo ON lo.offer_id = loo.offer_id
                    LEFT JOIN npcCorporations nc ON lo.corporation_id = nc.corporation_id
                    WHERE loo.type_id = \(offer.typeId)
                """

                let result = DatabaseManager.shared.executeQuery(itemSearchQuery)
                guard case let .success(rows) = result else {
                    await MainActor.run {
                        error = NSError(
                            domain: "com.eve.nexus", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "查询失败"]
                        )
                        isLoading = false
                    }
                    return
                }

                var corporationIds: Set<Int> = []
                var factionIds: Set<Int> = []
                var corporationFactionMap: [Int: Int?] = [:]

                for row in rows {
                    guard let corporationId = row["corporation_id"] as? Int else {
                        continue
                    }

                    let factionId = row["faction_id"] as? Int

                    corporationIds.insert(corporationId)
                    if let factionId = factionId {
                        factionIds.insert(factionId)
                    }
                    corporationFactionMap[corporationId] = factionId
                }

                // 查询军团和势力信息
                var corporationInfos: [Int: (name: String, enName: String, icon: String, militiaFaction: Int?)] = [:]
                var factionInfos: [Int: String] = [:]

                if !corporationIds.isEmpty {
                    let corpQuery = """
                        SELECT corporation_id, name, en_name, icon_filename, militia_faction 
                        FROM npcCorporations 
                        WHERE corporation_id IN (\(corporationIds.sorted().map { String($0) }.joined(separator: ",")))
                    """

                    if case let .success(corpRows) = DatabaseManager.shared.executeQuery(corpQuery) {
                        for row in corpRows {
                            guard let corpId = row["corporation_id"] as? Int,
                                  let name = row["name"] as? String,
                                  let enName = row["en_name"] as? String
                            else {
                                continue
                            }

                            let iconFileName =
                                (row["icon_filename"] as? String)?.isEmpty == true
                                    ? "corporations_default"
                                    : (row["icon_filename"] as? String ?? "corporations_default")

                            let militiaFaction = row["militia_faction"] as? Int

                            corporationInfos[corpId] = (name, enName, iconFileName, militiaFaction)
                        }
                    }
                }

                if !factionIds.isEmpty {
                    let factionQuery = """
                        SELECT id, name 
                        FROM factions 
                        WHERE id IN (\(factionIds.sorted().map { String($0) }.joined(separator: ",")))
                    """

                    if case let .success(factionRows) = DatabaseManager.shared.executeQuery(
                        factionQuery
                    ) {
                        for row in factionRows {
                            guard let factionId = row["id"] as? Int,
                                  let name = row["name"] as? String
                            else {
                                continue
                            }

                            factionInfos[factionId] = name
                        }
                    }
                }

                // 构建供应商列表
                let supplierList = corporationIds.compactMap { corpId -> LPOfferSupplier? in
                    guard let corpInfo = corporationInfos[corpId] else { return nil }

                    let factionId = corporationFactionMap[corpId] ?? nil
                    let factionName = factionId.flatMap { factionInfos[$0] }

                    return LPOfferSupplier(
                        factionId: factionId,
                        factionName: factionName,
                        corporationId: corpId,
                        corporationName: corpInfo.name,
                        corporationEnName: corpInfo.enName,
                        corporationIcon: corpInfo.icon,
                        militiaFaction: corpInfo.militiaFaction
                    )
                }.sorted {
                    $0.corporationName.localizedStandardCompare($1.corporationName)
                        == .orderedAscending
                }

                await MainActor.run {
                    suppliers = supplierList
                    isLoading = false
                }
            }
        }
    }
}

struct SpecificItemOfferView: View {
    let corporationId: Int
    let corporationName: String
    let targetTypeId: Int
    let itemInfo: LPStoreItemInfo

    @State private var offers: [LPStoreOffer] = []
    @State private var requiredItemInfos: [Int: LPStoreItemInfo] = [:]
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
            } else if offers.isEmpty {
                Section {
                    NoDataSection()
                }
            } else {
                Section(NSLocalizedString("Main_LP_Store_section", comment: "")) {
                    ForEach(offers, id: \.offerId) { offer in
                        LPStoreOfferView(
                            offer: offer,
                            itemInfo: itemInfo,
                            requiredItemInfos: requiredItemInfos,
                            marketPrices: [:],
                            isLoadingPrices: false
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(itemInfo.name)
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadOffers()
        }
    }

    private func loadOffers() async {
        isLoading = true
        error = nil

        do {
            // 1. 获取军团的所有offers
            let allOffers = try await LPStoreAPI.shared.fetchCorporationLPStoreOffers(
                corporationId: corporationId
            )

            // 2. 筛选出目标物品的offers
            let targetOffers = allOffers.filter { $0.typeId == targetTypeId }

            // 3. 只查询所需物品的信息（主物品信息已经有了）
            var requiredTypeIds = Set<Int>()
            for offer in targetOffers {
                requiredTypeIds.formUnion(offer.requiredItems.map { $0.typeId })
            }

            var infos: [Int: LPStoreItemInfo] = [:]

            // 4. 如果有所需物品，查询它们的信息
            if !requiredTypeIds.isEmpty {
                for typeId in requiredTypeIds {
                    guard let info = SDEMemoryStore.type(for: typeId),
                          let category = SDEMemoryStore.category(for: info.categoryID)
                    else { continue }
                    let icon = info.bpcIconFilename ?? info.iconFilename
                    infos[typeId] = LPStoreItemInfo(
                        names: info.names,
                        iconFileName: icon.isEmpty ? "not_found" : icon,
                        categoryName: category.name,
                        categoryId: info.categoryID
                    )
                }
            }

            await MainActor.run {
                offers = targetOffers.sorted { offer1, offer2 in
                    // 按LP成本排序，成本低的在前
                    if offer1.lpCost != offer2.lpCost {
                        return offer1.lpCost < offer2.lpCost
                    }
                    // LP成本相同时按ISK成本排序
                    return offer1.iskCost < offer2.iskCost
                }
                requiredItemInfos = infos
                isLoading = false
            }

        } catch {
            await MainActor.run {
                self.error = error
                isLoading = false
            }
        }
    }
}
