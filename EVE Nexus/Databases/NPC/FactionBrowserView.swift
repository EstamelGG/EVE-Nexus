import SwiftUI

// 势力信息数据模型
struct FactionItem: Identifiable {
    let id: Int
    let name: String
    let enName: String // 添加英文名称
    let zhName: String // 添加中文名称
    let shortDescription: String
    let description: String
    let iconName: String
}

// 军团信息数据模型
struct CorporationItem: Identifiable {
    let id: Int
    let name: String
    let enName: String // 添加英文名称
    let zhName: String // 添加中文名称
    let description: String
    let iconFileName: String
    let factionId: Int // 添加势力ID字段
    let militiaFaction: Int? // 添加民兵势力ID字段

    var isMilitia: Bool {
        if let militia = militiaFaction, militia > 0 {
            return true
        }
        return false
    }
}

// 声望数据模型
struct StandingInfo {
    let fromId: Int
    let fromType: String // agent, npc_corp, faction
    let standing: Double
}

// 根据声望值确定颜色
func standingColor(_ standing: Double) -> Color {
    switch standing {
    case 0.1...:
        return .blue
    case 0.01 ..< 0.1:
        return .cyan
    case -0.01 ..< 0.01:
        return .gray
    case -0.1 ..< -0.01:
        return .orange
    default: // <= -0.1
        return .red
    }
}

// 势力浏览器视图
struct FactionBrowserView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let characterId: Int?

    @State private var factions: [FactionItem] = []
    @State private var allCorporations: [CorporationItem] = []
    @State private var corporationsByFaction: [Int: [CorporationItem]] = [:]
    @State private var standings: [Int: StandingInfo] = [:]
    @State private var isLoadingStandings = false
    @State private var isLoadingData = true
    @State private var hasInitialized = false
    @State private var searchText = ""

    // 搜索过滤的势力 - 只匹配名称字段
    private var filteredFactions: [FactionItem] {
        if searchText.isEmpty {
            return []
        }
        return factions.filter { faction in
            faction.name.localizedCaseInsensitiveContains(searchText)
                || faction.enName.localizedCaseInsensitiveContains(searchText)
                || faction.zhName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // 搜索过滤的军团 - 只匹配名称字段
    private var filteredCorporations: [CorporationItem] {
        if searchText.isEmpty {
            return []
        }
        return allCorporations.filter { corporation in
            corporation.name.localizedCaseInsensitiveContains(searchText)
                || corporation.enName.localizedCaseInsensitiveContains(searchText)
                || corporation.zhName.localizedCaseInsensitiveContains(searchText)
        }
    }

    init(databaseManager: DatabaseManager, characterId: Int? = nil) {
        self.databaseManager = databaseManager
        self.characterId = characterId
    }

    var body: some View {
        if isLoadingData {
            VStack {
                ProgressView()
                    .scaleEffect(1.2)
                Text(NSLocalizedString("Loading_Data", comment: "正在加载数据..."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(NSLocalizedString("Main_NPC_Faction", comment: ""))
            .onAppear {
                loadDataIfNeeded()
            }
        } else {
            List {
                if !searchText.isEmpty {
                    // 搜索结果 - 势力部分
                    if !filteredFactions.isEmpty {
                        Section(header: Text(NSLocalizedString("Main_NPC_Faction", comment: ""))) {
                            ForEach(filteredFactions, id: \.id) { faction in
                                NavigationLink(
                                    destination: FactionDetailView(
                                        faction: faction,
                                        corporations: corporationsByFaction[faction.id] ?? [],
                                        databaseManager: databaseManager,
                                        characterId: characterId
                                    )
                                ) {
                                    HStack {
                                        IconManager.shared.loadImage(for: faction.iconName)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .cornerRadius(6)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(faction.name)
                                                    .contextMenu {
                                                        Button {
                                                            UIPasteboard.general.string =
                                                                faction.name
                                                        } label: {
                                                            Label(
                                                                NSLocalizedString(
                                                                    "Misc_Copy_Name", comment: ""
                                                                ),
                                                                systemImage: "doc.on.doc"
                                                            )
                                                        }
                                                        if !faction.enName.isEmpty
                                                            && faction.enName != faction.name
                                                        {
                                                            Button {
                                                                UIPasteboard.general.string =
                                                                    faction.enName
                                                            } label: {
                                                                Label(
                                                                    NSLocalizedString(
                                                                        "Misc_Copy_Trans",
                                                                        comment: ""
                                                                    ),
                                                                    systemImage: "translate"
                                                                )
                                                            }
                                                        }
                                                    }
                                                Spacer()
                                                // 显示声望在右侧
                                                if let standing = standings[faction.id] {
                                                    Text(String(format: "%.2f", standing.standing))
                                                        .font(.caption)
                                                        .foregroundColor(
                                                            standingColor(standing.standing))
                                                } else if characterId != nil && isLoadingStandings {
                                                    ProgressView()
                                                        .scaleEffect(0.7)
                                                }
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }

                    // 搜索结果 - 军团部分
                    if !filteredCorporations.isEmpty {
                        Section(header: Text(NSLocalizedString("Corporation_Detail", comment: ""))) {
                            ForEach(filteredCorporations, id: \.id) { corporation in
                                NavigationLink(
                                    destination: NPCCorporationDetailView(
                                        corporation: corporation,
                                        databaseManager: databaseManager
                                    )
                                ) {
                                    HStack {
                                        CorporationIconView(
                                            corporationId: corporation.id,
                                            iconFileName: corporation.iconFileName, size: 32
                                        )
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(corporation.name)
                                                    .contextMenu {
                                                        Button {
                                                            UIPasteboard.general.string =
                                                                corporation.name
                                                        } label: {
                                                            Label(
                                                                NSLocalizedString(
                                                                    "Misc_Copy_Name", comment: ""
                                                                ),
                                                                systemImage: "doc.on.doc"
                                                            )
                                                        }
                                                        if !corporation.enName.isEmpty
                                                            && corporation.enName != corporation.name
                                                        {
                                                            Button {
                                                                UIPasteboard.general.string =
                                                                    corporation.enName
                                                            } label: {
                                                                Label(
                                                                    NSLocalizedString(
                                                                        "Misc_Copy_Trans", comment: ""
                                                                    ),
                                                                    systemImage: "translate"
                                                                )
                                                            }
                                                        }
                                                    }
                                                Spacer()
                                                // 显示声望在右侧
                                                if let standing = standings[corporation.id] {
                                                    Text(String(format: "%.2f", standing.standing))
                                                        .font(.caption)
                                                        .foregroundColor(standingColor(standing.standing))
                                                } else if characterId != nil && isLoadingStandings {
                                                    ProgressView()
                                                        .scaleEffect(0.7)
                                                }
                                            }

                                            // 显示所属势力
                                            if let factionName = factions.first(where: {
                                                $0.id == corporation.factionId
                                            })?.name {
                                                Text(factionName)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer()
                                        // 显示民兵tag
                                        if corporation.isMilitia {
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

                    // 没有搜索结果时显示
                    if filteredFactions.isEmpty && filteredCorporations.isEmpty {
                        Section {
                            HStack {
                                Spacer()
                                Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }
                } else {
                    // 默认显示 - 所有势力（无header）
                    ForEach(factions, id: \.id) { faction in
                        NavigationLink(
                            destination: FactionDetailView(
                                faction: faction,
                                corporations: corporationsByFaction[faction.id] ?? [],
                                databaseManager: databaseManager,
                                characterId: characterId
                            )
                        ) {
                            HStack {
                                IconManager.shared.loadImage(for: faction.iconName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(faction.name)
                                            .contextMenu {
                                                Button {
                                                    UIPasteboard.general.string = faction.name
                                                } label: {
                                                    Label(
                                                        NSLocalizedString(
                                                            "Misc_Copy_Name", comment: ""
                                                        ),
                                                        systemImage: "doc.on.doc"
                                                    )
                                                }
                                                if !faction.enName.isEmpty
                                                    && faction.enName != faction.name
                                                {
                                                    Button {
                                                        UIPasteboard.general.string = faction.enName
                                                    } label: {
                                                        Label(
                                                            NSLocalizedString(
                                                                "Misc_Copy_Trans", comment: ""
                                                            ),
                                                            systemImage: "translate"
                                                        )
                                                    }
                                                }
                                            }
                                        Spacer()
                                        // 显示声望在右侧
                                        if let standing = standings[faction.id] {
                                            Text(String(format: "%.2f", standing.standing))
                                                .font(.caption)
                                                .foregroundColor(standingColor(standing.standing))
                                        } else if characterId != nil && isLoadingStandings {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
            .navigationTitle(NSLocalizedString("Main_NPC_Faction", comment: ""))
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: NSLocalizedString("Main_Search_Placeholder", comment: "")
            )
            .onAppear {
                loadDataIfNeeded()
            }
        }
    }

    // 仅在需要时加载数据
    private func loadDataIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        Task {
            await loadAllData()
        }
    }

    // 加载所有数据
    private func loadAllData() async {
        await MainActor.run {
            self.isLoadingData = true
        }

        // 并行加载势力和军团数据
        async let factionsResult = loadAllFactions()
        async let corporationsResult = loadAllCorporations()

        let (loadedFactions, loadedCorporations) = await (factionsResult, corporationsResult)

        // 按势力分组军团
        let groupedCorporations = Dictionary(grouping: loadedCorporations) { $0.factionId }

        await MainActor.run {
            self.factions = loadedFactions
            self.allCorporations = loadedCorporations
            self.corporationsByFaction = groupedCorporations
            self.isLoadingData = false
        }

        // 加载声望数据（如果有角色ID）
        if characterId != nil {
            await loadStandings()
        }
    }

    // 加载所有势力
    private func loadAllFactions() async -> [FactionItem] {
        let query =
            "SELECT id, name, en_name, zh_name, shortDescription, description, iconName FROM factions"

        var factions: [FactionItem] = []
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let id = row["id"] as? Int,
                   let name = row["name"] as? String,
                   let enName = row["en_name"] as? String,
                   let zhName = row["zh_name"] as? String,
                   let shortDescription = row["shortDescription"] as? String,
                   let description = row["description"] as? String,
                   let iconName = row["iconName"] as? String
                {
                    factions.append(
                        FactionItem(
                            id: id,
                            name: name,
                            enName: enName,
                            zhName: zhName,
                            shortDescription: shortDescription,
                            description: description,
                            iconName: iconName
                        ))
                }
            }
        }

        // 使用本地化比较进行排序
        return factions.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // 加载所有军团
    private func loadAllCorporations() async -> [CorporationItem] {
        let query =
            "SELECT corporation_id, name, en_name, zh_name, description, icon_filename, faction_id, militia_faction FROM npcCorporations"

        var corporations: [CorporationItem] = []
        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let corporationId = row["corporation_id"] as? Int,
                   let name = row["name"] as? String,
                   let enName = row["en_name"] as? String,
                   let zhName = row["zh_name"] as? String,
                   let description = row["description"] as? String,
                   let iconFileName = row["icon_filename"] as? String,
                   let factionId = row["faction_id"] as? Int
                {
                    let militiaFaction = row["militia_faction"] as? Int
                    corporations.append(
                        CorporationItem(
                            id: corporationId,
                            name: name,
                            enName: enName,
                            zhName: zhName,
                            description: description,
                            iconFileName: iconFileName.isEmpty
                                ? "corporation_default" : iconFileName,
                            factionId: factionId,
                            militiaFaction: militiaFaction
                        ))
                }
            }
        }

        // 使用本地化比较进行排序
        return corporations.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // 加载声望数据
    private func loadStandings() async {
        guard let characterId = characterId else { return }

        await MainActor.run {
            self.isLoadingStandings = true
        }

        do {
            let standingsData = try await CharacterStandingsAPI.shared.fetchStandings(
                characterId: characterId)

            // 将声望数据转换为字典，便于查找
            var standingsDict: [Int: StandingInfo] = [:]
            for standing in standingsData {
                let standingInfo = StandingInfo(
                    fromId: standing.from_id,
                    fromType: standing.from_type,
                    standing: standing.standing
                )
                standingsDict[standing.from_id] = standingInfo
            }

            await MainActor.run {
                self.standings = standingsDict
                self.isLoadingStandings = false
            }
        } catch is CancellationError {
            // 静默处理取消错误
            await MainActor.run {
                self.isLoadingStandings = false
            }
        } catch {
            Logger.error("加载声望数据失败: \(error)")
            await MainActor.run {
                self.isLoadingStandings = false
            }
        }
    }
}

// 势力详情页面
struct FactionDetailView: View {
    let faction: FactionItem
    let corporations: [CorporationItem] // 预加载的军团数据
    @ObservedObject var databaseManager: DatabaseManager
    let characterId: Int?

    @State private var standings: [Int: StandingInfo] = [:]
    @State private var isLoadingStandings = false
    @State private var hasInitialized = false

    var body: some View {
        List {
            // 第一个section：势力基本信息
            Section {
                // 第一行：图标和基本信息
                HStack(spacing: 16) {
                    IconManager.shared.loadImage(for: faction.iconName)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(faction.name)
                            .font(.title2)
                            .fontWeight(.semibold)
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
                        if !faction.shortDescription.isEmpty {
                            Text(faction.shortDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 8)

                // 第二行：完整描述
                Text(faction.description)
                    .font(.body)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = faction.description
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
            }

            // 第二个section：该势力的所有军团
            Section(header: Text(NSLocalizedString("Corporation_Detail", comment: ""))) {
                ForEach(corporations, id: \.id) { corporation in
                    NavigationLink(
                        destination: NPCCorporationDetailView(
                            corporation: corporation,
                            databaseManager: databaseManager
                        )
                    ) {
                        HStack {
                            CorporationIconView(
                                corporationId: corporation.id,
                                iconFileName: corporation.iconFileName, size: 32
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(corporation.name)
                                        .contextMenu {
                                            Button {
                                                UIPasteboard.general.string = corporation.name
                                            } label: {
                                                Label(
                                                    NSLocalizedString(
                                                        "Misc_Copy_Name", comment: ""
                                                    ),
                                                    systemImage: "doc.on.doc"
                                                )
                                            }
                                            if !corporation.enName.isEmpty
                                                && corporation.enName != corporation.name
                                            {
                                                Button {
                                                    UIPasteboard.general.string = corporation.enName
                                                } label: {
                                                    Label(
                                                        NSLocalizedString(
                                                            "Misc_Copy_Trans", comment: ""
                                                        ),
                                                        systemImage: "translate"
                                                    )
                                                }
                                            }
                                        }
                                    Spacer()
                                    // 显示声望在右侧
                                    if let standing = standings[corporation.id] {
                                        Text(String(format: "%.2f", standing.standing))
                                            .font(.caption)
                                            .foregroundColor(standingColor(standing.standing))
                                    } else if characterId != nil && isLoadingStandings {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                }
                            }
                            Spacer()
                            // 显示民兵tag
                            if corporation.isMilitia {
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
        .navigationTitle(faction.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadStandingsIfNeeded()
        }
    }

    // 仅在需要时加载声望数据
    private func loadStandingsIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        Task {
            await loadStandings()
        }
    }

    // 加载声望数据
    private func loadStandings() async {
        guard let characterId = characterId else { return }

        await MainActor.run {
            self.isLoadingStandings = true
        }

        do {
            let standingsData = try await CharacterStandingsAPI.shared.fetchStandings(
                characterId: characterId)

            // 将声望数据转换为字典，便于查找
            var standingsDict: [Int: StandingInfo] = [:]
            for standing in standingsData {
                let standingInfo = StandingInfo(
                    fromId: standing.from_id,
                    fromType: standing.from_type,
                    standing: standing.standing
                )
                standingsDict[standing.from_id] = standingInfo
            }

            await MainActor.run {
                self.standings = standingsDict
                self.isLoadingStandings = false
            }
        } catch is CancellationError {
            // 静默处理取消错误
            await MainActor.run {
                self.isLoadingStandings = false
            }
        } catch {
            Logger.error("加载声望数据失败: \(error)")
            await MainActor.run {
                self.isLoadingStandings = false
            }
        }
    }
}

// 军团详情页面
struct NPCCorporationDetailView: View {
    let corporation: CorporationItem
    @ObservedObject var databaseManager: DatabaseManager

    @State private var hasLPStoreData = false
    @State private var isLoadingLPStore = true
    @State private var lpStoreError: Error?

    var body: some View {
        List {
            // 第一个section：军团基本信息
            Section {
                // 军团图标、名称和描述
                HStack(spacing: 16) {
                    CorporationIconView(
                        corporationId: corporation.id, iconFileName: corporation.iconFileName,
                        size: 64
                    )

                    Text(corporation.name)
                        .font(.title2)
                        .fontWeight(.semibold)
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

                    Spacer()
                }
                .padding(.vertical, 8)

                // 军团描述
                Text(corporation.description)
                    .font(.body)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = corporation.description
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
            }

            // 第二个section：LP商店
            Section {
                if isLoadingLPStore {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(NSLocalizedString("LP_Store_Loading", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if hasLPStoreData {
                    NavigationLink(
                        destination: CorporationLPStoreView(
                            corporationId: corporation.id,
                            corporationName: corporation.name
                        )
                    ) {
                        HStack {
                            IconManager.shared.loadImage(for: "lpstore")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(4)
                            Text(NSLocalizedString("LP_Store_View", comment: ""))
                            Spacer()
                        }
                    }
                } else {
                    HStack {
                        IconManager.shared.loadImage(for: "lpstore")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                            .opacity(0.5)
                        Text(NSLocalizedString("LP_Store_No_Data", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(corporation.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await checkLPStoreData()
        }
    }

    // 检查LP商店数据
    private func checkLPStoreData() async {
        isLoadingLPStore = true
        lpStoreError = nil

        // 使用Task来在后台线程执行
        let result = await Task {
            do {
                // 直接从 SDE 数据库获取 LP 商店数据
                let offers = try await LPStoreAPI.shared.fetchCorporationLPStoreOffers(
                    corporationId: corporation.id
                )
                return !offers.isEmpty
            } catch {
                // 如果查询失败，设置错误但不影响UI状态
                lpStoreError = error
                return false
            }
        }.value

        hasLPStoreData = result
        isLoadingLPStore = false
    }
}
