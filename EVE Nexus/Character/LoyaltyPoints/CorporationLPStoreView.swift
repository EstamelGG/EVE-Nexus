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

/// Jita 清单不可用时：说明文案 + 右侧刷新重试
private struct LPJitaPriceListErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(message)
                .font(.caption)
                .foregroundColor(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(NSLocalizedString("Fitting_Refresh", comment: ""))
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 4, trailing: 18))
    }
}

struct LPStoreOfferView: View {
    let offer: LPStoreOffer
    let itemInfo: LPStoreItemInfo
    let requiredItemInfos: [Int: LPStoreItemInfo]
    let marketPrices: [Int: Double] // 所需物品的市场价格字典
    let isLoadingPrices: Bool // 是否正在加载价格

    var body: some View {
        NavigationLink(
            destination: ItemInfoMap.getItemInfoView(
                itemID: offer.typeId,
                databaseManager: DatabaseManager.shared
            )
        ) {
            HStack(alignment: .center, spacing: 12) {
                // 左侧：offer 图标（垂直居中）
                IconManager.shared.loadImage(for: itemInfo.iconFileName)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(6)
                    .frame(width: 36, height: 36)

                // 右侧：所有内容垂直排列
                VStack(alignment: .leading, spacing: 4) {
                    // 商品名称和数量
                    Text("\(offer.quantity)× \(itemInfo.name)")
                        .font(.headline)
                        .lineLimit(1)

                    // 价格信息
                    HStack(spacing: 4) {
                        if offer.lpCost > 0 {
                            Text("\(offer.lpCost) LP")
                                .foregroundColor(.blue)
                                .fontWeight(.semibold)
                        }

                        if offer.lpCost > 0 && offer.iskCost > 0 {
                            Text("+")
                        }

                        if offer.iskCost > 0 {
                            Text("\(FormatUtil.formatISK(Double(offer.iskCost)))")
                                .foregroundColor(.green)
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.subheadline)

                    // 所需物品（如果有）
                    if !offer.requiredItems.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(NSLocalizedString("Main_LP_Required_Items", comment: ""))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if isLoadingPrices {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 12, height: 12)
                                } else {
                                    let totalPrice = calculateTotalRequiredItemsPrice()
                                    if totalPrice > 0 {
                                        Text("(\(FormatUtil.formatISK(totalPrice)))")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            let sortedItems = offer.requiredItems.sorted { $0.typeId < $1.typeId }
                            ForEach(sortedItems, id: \.typeId) { item in
                                if let info = requiredItemInfos[item.typeId] {
                                    HStack(spacing: 6) {
                                        IconManager.shared.loadImage(for: info.iconFileName)
                                            .resizable()
                                            .scaledToFit()
                                            .cornerRadius(6)
                                            .frame(width: 20, height: 20)

                                        Text("\(item.quantity)×")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(info.name)
                                            .font(.caption)

                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = itemInfo.name
            } label: {
                Label(
                    NSLocalizedString("Misc_Copy_LP_Offer_Name", comment: ""),
                    systemImage: "doc.on.doc"
                )
            }

            if !offer.requiredItems.isEmpty {
                let sortedItems = offer.requiredItems.sorted { $0.typeId < $1.typeId }

                Button {
                    let materialsText = sortedItems.compactMap { item -> String? in
                        guard let info = requiredItemInfos[item.typeId] else { return nil }
                        return "\(info.name)\t\(item.quantity)"
                    }.joined(separator: "\n")
                    UIPasteboard.general.string = materialsText
                } label: {
                    Label(
                        NSLocalizedString("LP_Copy_Required_Materials", comment: ""),
                        systemImage: "list.bullet.rectangle"
                    )
                }

                // 分割线
                Divider()

                // 所需物品的"查看 xxx"按钮
                ForEach(sortedItems, id: \.typeId) { item in
                    if let info = requiredItemInfos[item.typeId] {
                        NavigationLink(
                            destination: ItemInfoMap.getItemInfoView(
                                itemID: item.typeId,
                                databaseManager: DatabaseManager.shared
                            )
                        ) {
                            Label(
                                "\(NSLocalizedString("View", comment: "")) \(info.name)",
                                systemImage: "info.circle"
                            )
                        }
                    }
                }
            }
        }
    }

    // 计算所需物品的总价格
    private func calculateTotalRequiredItemsPrice() -> Double {
        var totalPrice: Double = 0
        for requiredItem in offer.requiredItems {
            if let price = marketPrices[requiredItem.typeId], price > 0 {
                totalPrice += price * Double(requiredItem.quantity)
            }
        }
        return totalPrice
    }
}

struct LPStoreGroupView: View {
    let categoryName: String
    let offers: [LPStoreOffer]
    let itemInfos: [Int: LPStoreItemInfo]
    @State private var searchText = ""
    @State private var marketPrices: [Int: Double] = [:]
    @State private var isLoadingPrices = false
    @State private var hasLoadedPrices = false
    @State private var jitaPriceListErrorMessage: String?

    private var filteredOffers: [LPStoreOffer] {
        if searchText.isEmpty {
            return offers
        } else {
            return offers.filter { offer in
                if let itemInfo = itemInfos[offer.typeId] {
                    return itemInfo.name.localizedCaseInsensitiveContains(searchText)
                        || itemInfo.enName.localizedCaseInsensitiveContains(searchText)
                        || itemInfo.zhName.localizedCaseInsensitiveContains(searchText)
                }
                return false
            }
        }
    }

    var body: some View {
        List {
            Section(NSLocalizedString("Main_LP_Store_section", comment: "")) {
                if let jitaPriceListErrorMessage {
                    LPJitaPriceListErrorBanner(message: jitaPriceListErrorMessage) {
                        Task { await retryLoadJitaPriceList() }
                    }
                }
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
                                requiredItemInfos: itemInfos,
                                marketPrices: marketPrices,
                                isLoadingPrices: isLoadingPrices
                            )
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(categoryName)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        )
        .task {
            // 只在首次加载时获取价格，从子页面返回时不会重新加载
            guard !hasLoadedPrices else { return }
            await loadMarketPrices(forceRefresh: false)
        }
    }

    private func retryLoadJitaPriceList() async {
        await MainActor.run { hasLoadedPrices = false }
        await loadMarketPrices(forceRefresh: true)
    }

    // 收集所有所需物品并一次性获取价格
    private func loadMarketPrices(forceRefresh: Bool) async {
        // 如果已经加载过，直接返回
        if hasLoadedPrices {
            return
        }

        // 收集所有所需物品的 typeId（去重）
        var typeIds = Set<Int>()
        for offer in offers {
            for requiredItem in offer.requiredItems {
                typeIds.insert(requiredItem.typeId)
            }
        }

        guard !typeIds.isEmpty else {
            // 即使没有所需物品，也标记为已加载，避免重复检查
            await MainActor.run {
                hasLoadedPrices = true
            }
            return
        }

        await MainActor.run {
            isLoadingPrices = true
            jitaPriceListErrorMessage = nil
        }

        do {
            let prices = try await MarketPriceUtil.getJitaOrderPricesFromGitHubList(
                typeIds: Array(typeIds),
                forceRefresh: forceRefresh
            )
            await MainActor.run {
                self.marketPrices = prices
                self.isLoadingPrices = false
                self.hasLoadedPrices = true
                self.jitaPriceListErrorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.marketPrices = [:]
                self.isLoadingPrices = false
                self.hasLoadedPrices = true
                self.jitaPriceListErrorMessage = error.localizedDescription
            }
        }
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
    @State private var hasLoadedPrices = false
    @State private var hasInitialized = false
    @State private var searchText = ""
    @State private var marketPrices: [Int: Double] = [:]
    @State private var isLoadingPrices = false
    @State private var jitaPriceListErrorMessage: String?

    private var filteredOffers: [LPStoreOffer] {
        if searchText.isEmpty {
            return []
        }

        var matchedOffers: [LPStoreOffer] = []
        for category in categoryOffers {
            let filteredOffers = category.offers.filter { offer in
                if let itemInfo = itemInfos[offer.typeId] {
                    return itemInfo.name.localizedCaseInsensitiveContains(searchText)
                        || itemInfo.enName.localizedCaseInsensitiveContains(searchText)
                        || itemInfo.zhName.localizedCaseInsensitiveContains(searchText)
                }
                return false
            }
            matchedOffers.append(contentsOf: filteredOffers)
        }

        return matchedOffers.sorted { offer1, offer2 in
            if let info1 = itemInfos[offer1.typeId],
               let info2 = itemInfos[offer2.typeId]
            {
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
                            if let jitaPriceListErrorMessage {
                                LPJitaPriceListErrorBanner(message: jitaPriceListErrorMessage) {
                                    Task { await retryLoadCorporationJitaPriceList() }
                                }
                            }
                            ForEach(filteredOffers, id: \.offerId) { offer in
                                if let itemInfo = itemInfos[offer.typeId] {
                                    LPStoreOfferView(
                                        offer: offer,
                                        itemInfo: itemInfo,
                                        requiredItemInfos: itemInfos,
                                        marketPrices: marketPrices,
                                        isLoadingPrices: isLoadingPrices
                                    )
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                } else {
                    Section(NSLocalizedString("Main_LP_Store_category", comment: "")) {
                        if let jitaPriceListErrorMessage {
                            LPJitaPriceListErrorBanner(message: jitaPriceListErrorMessage) {
                                Task { await retryLoadCorporationJitaPriceList() }
                            }
                        }
                        ForEach(categoryOffers, id: \.category.name) { category in
                            NavigationLink(
                                destination: LPStoreGroupView(
                                    categoryName: category.category.name,
                                    offers: category.offers,
                                    itemInfos: itemInfos
                                )
                            ) {
                                HStack {
                                    IconManager.shared.loadImage(
                                        for: category.category.iconFileName
                                    )
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
        // 移除嵌套的搜索功能，避免与主搜索页面冲突
        // .searchable(
        //     text: $searchText,
        //     placement: .navigationBarDrawer(displayMode: .always),
        //     prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
        // )
        .task {
            // 只在首次初始化时加载数据，从子页面返回时不会重新加载
            guard !hasInitialized else { return }

            if !hasLoadedData {
                await loadOffers()
            }
            if !hasLoadedPrices {
                await loadMarketPrices(forceRefresh: false)
            }

            hasInitialized = true
        }
    }

    private func retryLoadCorporationJitaPriceList() async {
        await MainActor.run { hasLoadedPrices = false }
        await loadMarketPrices(forceRefresh: true)
    }

    private func loadOffers() async {
        if hasLoadedData {
            return
        }

        isLoading = true
        error = nil

        do {
            // 1. 获取所有商品
            offers = try await LPStoreAPI.shared.fetchCorporationLPStoreOffers(
                corporationId: corporationId
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
                               let info2 = itemInfos[offer2.typeId]
                            {
                                return info1.name.localizedStandardCompare(info2.name)
                                    == .orderedAscending
                            }
                            return false
                        }
                    )
                }.sorted {
                    $0.category.name.localizedStandardCompare($1.category.name) == .orderedAscending
                }
            }

            isLoading = false
            hasLoadedData = true
        } catch {
            self.error = error
            isLoading = false
        }
    }

    // 收集所有所需物品并一次性获取价格
    private func loadMarketPrices(forceRefresh: Bool) async {
        // 如果已经加载过，直接返回
        if hasLoadedPrices {
            return
        }

        // 收集所有所需物品的 typeId（去重）
        var typeIds = Set<Int>()
        for offer in offers {
            for requiredItem in offer.requiredItems {
                typeIds.insert(requiredItem.typeId)
            }
        }

        guard !typeIds.isEmpty else {
            // 即使没有所需物品，也标记为已加载，避免重复检查
            await MainActor.run {
                hasLoadedPrices = true
            }
            return
        }

        await MainActor.run {
            isLoadingPrices = true
            jitaPriceListErrorMessage = nil
        }

        do {
            let prices = try await MarketPriceUtil.getJitaOrderPricesFromGitHubList(
                typeIds: Array(typeIds),
                forceRefresh: forceRefresh
            )
            await MainActor.run {
                self.marketPrices = prices
                self.isLoadingPrices = false
                self.hasLoadedPrices = true
                self.jitaPriceListErrorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.marketPrices = [:]
                self.isLoadingPrices = false
                self.hasLoadedPrices = true
                self.jitaPriceListErrorMessage = error.localizedDescription
            }
        }
    }
}
