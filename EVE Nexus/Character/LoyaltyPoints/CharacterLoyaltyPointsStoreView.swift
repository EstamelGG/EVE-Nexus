import SwiftUI

struct CharacterLoyaltyPointsStoreView: View {
    @State private var factions: [Faction] = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var hasLoadedData = false
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var lpSearchResults: [LPSearchResult] = []
    @State private var isSearchingItems = false
    @State private var shouldExecuteSearch = false

    private var searchResults: (factions: [Faction], corporations: [Corporation]) {
        // 如果搜索文本为空，直接返回空结果，不进行任何计算
        guard !debouncedSearchText.isEmpty else {
            return ([], [])
        }

        var matchedFactions: [Faction] = []
        var matchedCorporations: [Corporation] = []

        // 搜索势力和军团名称（全语种）
        for faction in factions {
            if faction.matches(debouncedSearchText) {
                matchedFactions.append(faction)
            }

            for corporation in faction.corporations {
                if corporation.matches(debouncedSearchText) {
                    matchedCorporations.append(corporation)
                }
            }
        }

        // 对搜索结果进行本地化排序
        matchedFactions.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        matchedCorporations.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return (matchedFactions, matchedCorporations)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                } else if let error = error {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(error.localizedDescription)
                            .font(.headline)
                        Button(NSLocalizedString("Main_Setting_Reset", comment: "")) {
                            loadFactions()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    // 正常势力列表视图
                    Section(NSLocalizedString("Main_LP_Store_Factions", comment: "")) {
                        ForEach(factions) { faction in
                            NavigationLink(destination: FactionLPDetailView(faction: faction)) {
                                HStack {
                                    IconManager.shared.loadImage(for: faction.iconName)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36)
                                    Text(faction.name)
                                        .padding(.leading, 8)
                                        .contextMenu {
                                            Button {
                                                UIPasteboard.general.string = faction.name
                                            } label: {
                                                Label(
                                                    NSLocalizedString("Misc_Copy_Name", comment: ""),
                                                    systemImage: "doc.on.doc"
                                                )
                                            }
                                            if !faction.enName.isEmpty && faction.enName != faction.name {
                                                Button {
                                                    UIPasteboard.general.string = faction.enName
                                                } label: {
                                                    Label(
                                                        NSLocalizedString("Misc_Copy_Trans", comment: ""),
                                                        systemImage: "translate"
                                                    )
                                                }
                                            }
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
        .navigationTitle(NSLocalizedString("Main_LP_Store", comment: ""))
        .searchable(
            text: $searchText,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(NSLocalizedString("Main_Search_Placeholder", comment: ""))
        )
        .onSubmit(of: .search) {
            if !searchText.isEmpty {
                debouncedSearchText = searchText
                searchLPItems(searchText: searchText)
                shouldExecuteSearch = true
            }
        }
        .onAppear {
            if !hasLoadedData {
                loadFactions()
            }
        }
        .onDisappear {
            // 取消搜索任务
            searchTask?.cancel()
        }
        .navigationDestination(isPresented: $shouldExecuteSearch) {
            LPSearchResultsView(
                searchText: searchText,
                searchResults: searchResults,
                lpSearchResults: lpSearchResults
            )
        }
    }

    private func loadFactions() {
        if hasLoadedData {
            return
        }

        isLoading = true
        error = nil

        Task {
            do {
                // 内存索引取有 LP 商店数据的军团
                let corporationIds = Array(SDEMemoryStore.loyaltyOffersByCorporation.keys)

                var factionDict: [Int: (names: LocalizedText, iconName: String, corporations: [Corporation])] = [:]

                for corporationId in corporationIds {
                    guard let corp = SDEMemoryStore.npcCorporation(for: corporationId)
                    else { continue }

                    let factionId = corp.factionID ?? 0
                    let factionInfo = SDEMemoryStore.faction(for: factionId)
                    let factionNames = factionInfo?.names
                        ?? LocalizedText(
                            de: "Unknown Faction", en: "Unknown Faction", es: "Unknown Faction",
                            fr: "Unknown Faction", ja: "Unknown Faction", ko: "Unknown Faction",
                            ru: "Unknown Faction",
                            zh: NSLocalizedString("Main_LP_Unknown_Faction", comment: "")
                        )
                    let factionIcon = factionInfo?.iconName ?? "not_found"

                    if factionDict[factionId] == nil {
                        factionDict[factionId] = (factionNames, factionIcon, [])
                    }

                    factionDict[factionId]?.corporations.append(
                        Corporation(
                            id: corporationId,
                            names: corp.names,
                            factionId: factionId,
                            iconFileName: corp.iconFilename,
                            militiaFaction: corp.militiaFaction
                        )
                    )
                }

                let loadedFactions = factionDict.compactMap { id, data -> Faction? in
                    guard !data.corporations.isEmpty else { return nil }
                    let corps = data.corporations.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                    return Faction(
                        id: id,
                        names: data.names,
                        iconName: data.iconName,
                        corporations: corps
                    )
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

                await MainActor.run {
                    self.factions = loadedFactions
                    isLoading = false
                    hasLoadedData = true
                }

                Logger.info(" 成功加载LP商店数据 - 势力数量: \(loadedFactions.count)")
            }
        }
    }

    private func searchLPItems(searchText: String) {
        isSearchingItems = true

        Task {
            do {
                // 1. 内存索引搜索 LP 物品（全语种名称匹配产出物品，再反查 offer 与军团）
                var typeIds: Set<Int> = []
                var categoryIds: Set<Int> = []
                var searchOffers: [LPSearchOffer] = []
                var seenOfferIds = Set<Int>()

                for (typeId, offerIdList) in SDEMemoryStore.loyaltyOfferOutputsByType {
                    guard let typeInfo = SDEMemoryStore.type(for: typeId),
                          typeInfo.names.matchesSearch(searchText)
                    else { continue }

                    for offerId in offerIdList where seenOfferIds.insert(offerId).inserted {
                        // 反查军团（offer 归属）
                        var corporationId: Int? = nil
                        var factionId: Int? = nil
                        for (corpID, corpOfferIds) in SDEMemoryStore.loyaltyOffersByCorporation
                            where corpOfferIds.contains(offerId)
                        {
                            corporationId = corpID
                            factionId = SDEMemoryStore.npcCorporation(for: corpID)?.factionID
                            break
                        }

                        guard let corporationId else { continue }

                        typeIds.insert(typeId)
                        searchOffers.append(
                            LPSearchOffer(
                                typeId: typeId,
                                typeName: "",
                                typeIcon: "",
                                offerId: offerId,
                                factionId: factionId,
                                corporationId: corporationId
                            )
                        )
                    }
                }

                if typeIds.isEmpty {
                    await MainActor.run {
                        isSearchingItems = false
                        lpSearchResults = []
                    }
                    return
                }

                // 2. 内存索引获取物品信息（原 WHERE type_id IN (...) AND categoryID NOT IN (2118, 91)）
                var typeInfos: [Int: (name: String, icon: String, categoryId: Int)] = [:]
                for typeId in typeIds {
                    guard let info = SDEMemoryStore.type(for: typeId),
                          info.categoryID != 2118, info.categoryID != 91
                    else { continue }
                    typeInfos[typeId] = (info.name, info.iconFilename, info.categoryID)
                    categoryIds.insert(info.categoryID)
                }

                // 3. 获取分类信息（内存索引）
                var categoryInfos: [Int: (name: String, icon: String)] = [:]
                for categoryId in categoryIds {
                    if let category = SDEMemoryStore.category(for: categoryId) {
                        categoryInfos[categoryId] = (category.name, category.iconFilename)
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
