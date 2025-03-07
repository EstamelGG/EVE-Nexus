import SwiftUI

struct SearcherView: View {
    let character: EVECharacterInfo
    @StateObject private var viewModel = SearcherViewModel()
    @State private var searchText = ""
    @State private var selectedSearchType = SearchType.character
    @State private var isLoadingContacts = true
    @State private var loadingError: Error?
    @State private var hasLoadedContacts = false

    // 过滤条件
    @State private var corporationFilter = ""
    @State private var allianceFilter = ""
    @State private var tickerFilter = ""
    @State private var selectedStructureType = StructureType.all

    enum SearchType: String, CaseIterable {
        case character = "Main_Search_Type_Character"
        case corporation = "Main_Search_Type_Corporation"
        case alliance = "Main_Search_Type_Alliance"
        case structure = "Main_Search_Type_Structure"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }

        // 转换为MailRecipient.RecipientType
        var recipientType: MailRecipient.RecipientType {
            switch self {
            case .character:
                return .character
            case .corporation:
                return .corporation
            case .alliance:
                return .alliance
            case .structure:
                return .character  // 建筑物没有对应的类型，暂时使用character
            }
        }
    }

    enum StructureType: String, CaseIterable {
        case all = "Main_Search_Filter_All"
        case station = "Main_Search_Filter_Station"
        case structure = "Main_Search_Filter_Structure"

        var localizedName: String {
            NSLocalizedString(rawValue, comment: "")
        }
    }

    // 搜索结果数据模型
    struct SearchResult: Identifiable {
        let id: Int
        let name: String
        let type: SearchType
        var corporationName: String?
        var allianceName: String?
        var allianceId: Int?
        var corporationId: Int?
        var structureType: StructureType?
        var locationInfo: (security: Double, systemName: String, regionName: String)?
        var typeInfo: String?  // 图标文件名
        var additionalInfo: String?

        init(
            id: Int, name: String, type: SearchType, structureType: StructureType? = nil,
            locationInfo: (security: Double, systemName: String, regionName: String)? = nil,
            typeInfo: String? = nil,
            additionalInfo: String? = nil,
            allianceId: Int? = nil,
            corporationId: Int? = nil
        ) {
            self.id = id
            self.name = name
            self.type = type
            self.structureType = structureType
            self.locationInfo = locationInfo
            self.typeInfo = typeInfo
            self.additionalInfo = additionalInfo
            self.allianceId = allianceId
            self.corporationId = corporationId
        }
    }

    // 搜索响应数据结构
    struct SearchResponse: Codable {
        let character: [Int]?
        let corporation: [Int]?
        let alliance: [Int]?
        let station: [Int]?
        let structure: [Int]?
    }

    var body: some View {
        VStack(spacing: 0) {
            // 搜索类型选择器
            Picker("", selection: $selectedSearchType) {
                ForEach(SearchType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top)
            .onChange(of: selectedSearchType) { _, _ in
                // 清空搜索结果和状态
                viewModel.searchResults = []
                viewModel.filteredResults = []
                viewModel.error = nil
                viewModel.searchingStatus = ""

                // 如果有搜索文本，则重新搜索
                if !searchText.isEmpty && searchText.count > 2 {
                    viewModel.debounceSearch(
                        characterId: character.CharacterID, searchText: searchText,
                        type: selectedSearchType
                    )
                }
            }

            // 搜索框
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField(
                        NSLocalizedString("Main_Search_Placeholder", comment: ""), text: $searchText
                    )
                    .submitLabel(.search)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                // 过滤条件部分，只在角色搜索和建筑搜索时显示
                if selectedSearchType == .character || selectedSearchType == .structure {
                    Section(
                        header: Text(NSLocalizedString("Main_Search_Filter_Title", comment: ""))
                    ) {
                        filterView

                        if selectedSearchType == .character {
                            Button(action: clearFilters) {
                                Text(NSLocalizedString("Main_Search_Filter_Clear", comment: ""))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                // 搜索结果部分
                if !searchText.isEmpty {
                    Section(
                        header: Text(
                            "\(NSLocalizedString("Main_Search_Results", comment: "")) (\(viewModel.filteredResults.count)/\(viewModel.searchResults.count))"
                        )
                    ) {
                        if !viewModel.searchingStatus.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Text(viewModel.searchingStatus)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else if viewModel.error != nil {
                            HStack {
                                Spacer()
                                VStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.red)
                                    Text(NSLocalizedString("Main_Search_Failed", comment: ""))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        } else if searchText.count <= 2 {
                            Text(NSLocalizedString("Main_Search_Min_Length", comment: ""))
                                .foregroundColor(.secondary)
                        } else if viewModel.filteredResults.isEmpty {
                            if viewModel.searchResults.isEmpty {
                                Text(NSLocalizedString("Main_Search_No_Results", comment: ""))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(
                                    NSLocalizedString(
                                        "Main_Search_No_Filtered_Results", comment: ""
                                    )
                                )
                                .foregroundColor(.secondary)
                            }
                        } else {
                            ForEach(viewModel.filteredResults) { result in
                                if result.type == .structure {
                                    SearchResultRow(result: result, character: character)
                                } else {
                                    NavigationLink(destination: {
                                        switch result.type {
                                        case .character:
                                            CharacterDetailView(
                                                characterId: result.id, character: character
                                            )
                                        case .corporation:
                                            CorporationDetailView(
                                                corporationId: result.id, character: character
                                            )
                                        case .alliance:
                                            AllianceDetailView(
                                                allianceId: result.id, character: character
                                            )
                                        default:
                                            SearchResultRow(result: result, character: character)
                                        }
                                    }) {
                                        SearchResultRow(result: result, character: character)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Search_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isLoadingContacts {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else if loadingError != nil {
                    Button(action: {
                        Task {
                            isLoadingContacts = true
                            hasLoadedContacts = false
                            await loadContactsData()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .onAppear {
            if !hasLoadedContacts {
                Task {
                    await loadContactsData()
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                viewModel.searchResults = []
                viewModel.filteredResults = []
                viewModel.error = nil
                viewModel.searchingStatus = ""
            } else if newValue.count <= 2 {
                viewModel.searchResults = []
                viewModel.filteredResults = []
                viewModel.error = nil
                viewModel.searchingStatus = ""
            } else {
                viewModel.debounceSearch(
                    characterId: character.CharacterID, searchText: newValue,
                    type: selectedSearchType
                )
            }
        }
        .onChange(of: corporationFilter) { _, _ in
            viewModel.filterResults(
                corporationFilter: corporationFilter, allianceFilter: allianceFilter
            )
        }
        .onChange(of: allianceFilter) { _, _ in
            viewModel.filterResults(
                corporationFilter: corporationFilter, allianceFilter: allianceFilter
            )
        }
        .onChange(of: selectedStructureType) { _, _ in
            viewModel.updateStructureFilters(
                structureType: selectedStructureType
            )
        }
    }

    private func loadContactsData() async {
        guard !hasLoadedContacts else { return }

        do {
            // 并行加载所有联系人数据
            async let characterContacts = GetCharContacts.shared.fetchContacts(
                characterId: character.CharacterID)
            async let corporationContacts = GetCorpContacts.shared.fetchContacts(
                characterId: character.CharacterID, corporationId: character.corporationId ?? 0
            )

            // 如果角色有联盟，也加载联盟联系人
            if let allianceId = character.allianceId {
                async let allianceContacts = GetAllianceContacts.shared.fetchContacts(
                    characterId: character.CharacterID, allianceId: allianceId
                )
                _ = try await [characterContacts, corporationContacts, allianceContacts]
            } else {
                _ = try await [characterContacts, corporationContacts]
            }

            await MainActor.run {
                isLoadingContacts = false
                loadingError = nil
                hasLoadedContacts = true
            }
        } catch {
            await MainActor.run {
                isLoadingContacts = false
                loadingError = error
                Logger.error("加载联系人数据失败: \(error)")
            }
        }
    }

    @ViewBuilder
    private var filterView: some View {
        switch selectedSearchType {
        case .character:
            TextField(
                NSLocalizedString("Main_Search_Filter_Corporation", comment: ""),
                text: $corporationFilter
            )
            TextField(
                NSLocalizedString("Main_Search_Filter_Alliance", comment: ""), text: $allianceFilter
            )
        case .corporation:
            EmptyView()
        case .alliance:
            EmptyView()
        case .structure:
            Picker(
                NSLocalizedString("Main_Search_Filter_Structure_Type", comment: ""),
                selection: $selectedStructureType
            ) {
                ForEach(StructureType.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }

            Button(action: clearFilters) {
                Text(NSLocalizedString("Main_Search_Filter_Clear", comment: ""))
                    .foregroundColor(.red)
            }
        }
    }

    private func clearFilters() {
        corporationFilter = ""
        allianceFilter = ""
        tickerFilter = ""
        selectedStructureType = .all
        // 清除过滤器时重置过滤结果
        viewModel.filterResults(corporationFilter: "", allianceFilter: "")
    }
}

// 搜索结果行视图
struct SearchResultRow: View {
    let result: SearcherView.SearchResult
    let character: EVECharacterInfo
    @State private var allianceName: String?
    @State private var isLoadingAlliance = false
    @State private var allianceId: Int?
    @State private var isLoadingCorpInfo = false
    @State private var hasAttemptedCorpInfoLoad = false
    @State private var hasAttemptedAllianceLoad = false
    @State private var loadTask: Task<Void, Never>?
    @State private var standingIcon: String = "ColorTag-Neutral"

    private func determineStandingIcon() async {
        Logger.debug("开始计算声望 - 目标ID: \(result.id), 类型: \(result.type), 名称: \(result.name)")

        // 如果是建筑搜索，直接返回中立图标
        if result.type == .structure {
            standingIcon = "ColorTag-Neutral"
            Logger.debug("建筑类型，直接返回中立图标")
            return
        }

        // 获取目标的完整信息（军团ID和联盟ID）
        var targetInfo = (
            entityId: result.id,
            corpId: result.type == .character
                ? result.corporationId : (result.type == .corporation ? result.id : nil),
            allianceId: result.type == .alliance ? result.id : nil
        )

        // 如果是军团，使用已加载的联盟ID
        if result.type == .corporation {
            targetInfo.allianceId = allianceId
            // 如果还没有尝试加载联盟信息，启动加载任务
            if !hasAttemptedCorpInfoLoad {
                loadTask?.cancel()
                loadTask = Task {
                    await loadCorporationInfo()
                }
            }
        }
        // 如果是角色，使用其联盟ID
        else if result.type == .character {
            targetInfo.allianceId = result.allianceId
        }

        // 1. 检查个人声望设置
        if let contacts = try? await GetCharContacts.shared.fetchContacts(
            characterId: character.CharacterID)
        {
            Logger.debug("获取到个人联系人列表，数量: \(contacts.count)")

            // 检查负面声望
            // 1.1 检查对目标本身的负面声望
            if let directContact = contacts.first(where: { $0.contact_id == targetInfo.entityId }),
                directContact.standing < 0
            {
                standingIcon = getStandingIcon(standing: directContact.standing)
                Logger.debug("找到个人对目标的负面声望: \(directContact.standing)")
                return
            }

            // 1.2 如果目标是角色或军团，检查对其军团的负面声望
            if let corpId = targetInfo.corpId,
                let corpContact = contacts.first(where: { $0.contact_id == corpId }),
                corpContact.standing < 0
            {
                standingIcon = getStandingIcon(standing: corpContact.standing)
                Logger.debug("找到个人对目标军团的负面声望: \(corpContact.standing)")
                return
            }

            // 1.3 检查对其联盟的负面声望
            if let allianceId = targetInfo.allianceId,
                let allianceContact = contacts.first(where: { $0.contact_id == allianceId }),
                allianceContact.standing < 0
            {
                standingIcon = getStandingIcon(standing: allianceContact.standing)
                Logger.debug("找到个人对目标联盟的负面声望: \(allianceContact.standing)")
                return
            }

            // 检查正面声望
            var positiveStanding: Double? = nil

            // 1.4 检查对目标本身的正面声望
            if let directContact = contacts.first(where: { $0.contact_id == targetInfo.entityId }),
                directContact.standing > 0
            {
                positiveStanding = directContact.standing
                Logger.debug("找到个人对目标的正面声望: \(directContact.standing)")
            }

            // 1.5 如果目标是角色或军团，检查对其军团的正面声望
            if positiveStanding == nil,
                let corpId = targetInfo.corpId,
                let corpContact = contacts.first(where: { $0.contact_id == corpId }),
                corpContact.standing > 0
            {
                positiveStanding = corpContact.standing
                Logger.debug("找到个人对目标军团的正面声望: \(corpContact.standing)")
            }

            // 1.6 检查对其联盟的正面声望
            if positiveStanding == nil,
                let allianceId = targetInfo.allianceId,
                let allianceContact = contacts.first(where: { $0.contact_id == allianceId }),
                allianceContact.standing > 0
            {
                positiveStanding = allianceContact.standing
                Logger.debug("找到个人对目标联盟的正面声望: \(allianceContact.standing)")
            }

            if let standing = positiveStanding {
                standingIcon = getStandingIcon(standing: standing)
                Logger.debug("使用个人正面声望: \(standing)")
                return
            }
        }

        // 2. 检查军团声望设置
        if let corpId = character.corporationId,
            let contacts = try? await GetCorpContacts.shared.fetchContacts(
                characterId: character.CharacterID, corporationId: corpId
            )
        {
            Logger.debug("获取到军团联系人列表，数量: \(contacts.count)")

            // 检查负面声望
            // 2.1 检查对目标本身的负面声望
            if let directContact = contacts.first(where: { $0.contact_id == targetInfo.entityId }),
                directContact.standing < 0
            {
                standingIcon = getStandingIcon(standing: directContact.standing)
                Logger.debug("找到军团对目标的负面声望: \(directContact.standing)")
                return
            }

            // 2.2 如果目标是角色或军团，检查对其军团的负面声望
            if let corpId = targetInfo.corpId,
                let corpContact = contacts.first(where: { $0.contact_id == corpId }),
                corpContact.standing < 0
            {
                standingIcon = getStandingIcon(standing: corpContact.standing)
                Logger.debug("找到军团对目标军团的负面声望: \(corpContact.standing)")
                return
            }

            // 2.3 检查对其联盟的负面声望
            if let allianceId = targetInfo.allianceId,
                let allianceContact = contacts.first(where: { $0.contact_id == allianceId }),
                allianceContact.standing < 0
            {
                standingIcon = getStandingIcon(standing: allianceContact.standing)
                Logger.debug("找到军团对目标联盟的负面声望: \(allianceContact.standing)")
                return
            }

            // 检查正面声望
            var positiveStanding: Double? = nil

            // 2.4 检查对目标本身的正面声望
            if let directContact = contacts.first(where: { $0.contact_id == targetInfo.entityId }),
                directContact.standing > 0
            {
                positiveStanding = directContact.standing
                Logger.debug("找到军团对目标的正面声望: \(directContact.standing)")
            }

            // 2.5 如果目标是角色或军团，检查对其军团的正面声望
            if positiveStanding == nil,
                let corpId = targetInfo.corpId,
                let corpContact = contacts.first(where: { $0.contact_id == corpId }),
                corpContact.standing > 0
            {
                positiveStanding = corpContact.standing
                Logger.debug("找到军团对目标军团的正面声望: \(corpContact.standing)")
            }

            // 2.6 检查对其联盟的正面声望
            if positiveStanding == nil,
                let allianceId = targetInfo.allianceId,
                let allianceContact = contacts.first(where: { $0.contact_id == allianceId }),
                allianceContact.standing > 0
            {
                positiveStanding = allianceContact.standing
                Logger.debug("找到军团对目标联盟的正面声望: \(allianceContact.standing)")
            }

            if let standing = positiveStanding {
                standingIcon = getStandingIcon(standing: standing)
                Logger.debug("使用军团正面声望: \(standing)")
                return
            }
        }

        // 3. 检查联盟声望设置
        if let allianceId = character.allianceId,
            let contacts = try? await GetAllianceContacts.shared.fetchContacts(
                characterId: character.CharacterID, allianceId: allianceId
            )
        {
            Logger.debug("获取到联盟联系人列表，数量: \(contacts.count)")

            // 检查负面声望
            // 3.1 检查对目标本身的负面声望
            if let directContact = contacts.first(where: { $0.contact_id == targetInfo.entityId }),
                directContact.standing < 0
            {
                standingIcon = getStandingIcon(standing: directContact.standing)
                Logger.debug("找到联盟对目标的负面声望: \(directContact.standing)")
                return
            }

            // 3.2 如果目标是角色或军团，检查对其军团的负面声望
            if let corpId = targetInfo.corpId,
                let corpContact = contacts.first(where: { $0.contact_id == corpId }),
                corpContact.standing < 0
            {
                standingIcon = getStandingIcon(standing: corpContact.standing)
                Logger.debug("找到联盟对目标军团的负面声望: \(corpContact.standing)")
                return
            }

            // 3.3 检查对其联盟的负面声望
            if let allianceId = targetInfo.allianceId,
                let allianceContact = contacts.first(where: { $0.contact_id == allianceId }),
                allianceContact.standing < 0
            {
                standingIcon = getStandingIcon(standing: allianceContact.standing)
                Logger.debug("找到联盟对目标联盟的负面声望: \(allianceContact.standing)")
                return
            }

            // 检查正面声望
            var positiveStanding: Double? = nil

            // 3.4 检查对目标本身的正面声望
            if let directContact = contacts.first(where: { $0.contact_id == targetInfo.entityId }),
                directContact.standing > 0
            {
                positiveStanding = directContact.standing
                Logger.debug("找到联盟对目标的正面声望: \(directContact.standing)")
            }

            // 3.5 如果目标是角色或军团，检查对其军团的正面声望
            if positiveStanding == nil,
                let corpId = targetInfo.corpId,
                let corpContact = contacts.first(where: { $0.contact_id == corpId }),
                corpContact.standing > 0
            {
                positiveStanding = corpContact.standing
                Logger.debug("找到联盟对目标军团的正面声望: \(corpContact.standing)")
            }

            // 3.6 检查对其联盟的正面声望
            if positiveStanding == nil,
                let allianceId = targetInfo.allianceId,
                let allianceContact = contacts.first(where: { $0.contact_id == allianceId }),
                allianceContact.standing > 0
            {
                positiveStanding = allianceContact.standing
                Logger.debug("找到联盟对目标联盟的正面声望: \(allianceContact.standing)")
            }

            if let standing = positiveStanding {
                standingIcon = getStandingIcon(standing: standing)
                Logger.debug("使用联盟正面声望: \(standing)")
                return
            }
        }

        // 4. 检查是否同军团
        if let corpId = character.corporationId {
            Logger.debug("检查是否同军团 - 角色军团ID: \(corpId)")
            if result.type == .character {
                if let resultCorpId = result.corporationId, corpId == resultCorpId {
                    standingIcon = "ColorTag-StarGreen9"
                    Logger.debug("是同军团成员，设置为绿色星星")
                    return
                }
            } else if result.type == .corporation && corpId == result.id {
                standingIcon = "ColorTag-StarGreen9"
                Logger.debug("是当前军团，设置为绿色星星")
                return
            }
        }

        // 5. 检查是否同联盟
        if let allianceId = character.allianceId {
            Logger.debug("检查是否同联盟 - 角色联盟ID: \(allianceId)")
            if result.type == .character {
                if let resultAllianceId = result.allianceId, allianceId == resultAllianceId {
                    standingIcon = "ColorTag-StarBlue9"
                    Logger.debug("是同联盟成员，设置为蓝色星星")
                    return
                }
            } else if result.type == .corporation {
                if targetInfo.allianceId == allianceId {
                    standingIcon = "ColorTag-StarBlue9"
                    Logger.debug("是同联盟军团，设置为蓝色星星")
                    return
                }
            } else if result.type == .alliance && allianceId == result.id {
                standingIcon = "ColorTag-StarBlue9"
                Logger.debug("是当前联盟，设置为蓝色星星")
                return
            }
        }

        // 6. 如果都没有匹配，设置为中立
        standingIcon = "ColorTag-Neutral"
        Logger.debug("没有找到任何声望设置，使用中立图标")
    }

    private func getStandingIcon(standing: Double) -> String {
        let standingValues = [-10.0, -5.0, 0.0, 5.0, 10.0]
        let icons = [
            "ColorTag-MinusRed9", "ColorTag-MinusOrange9", "ColorTag-Neutral",
            "ColorTag-PlusLightBlue9", "ColorTag-PlusDarkBlue9",
        ]

        // 找到最接近的声望值
        var closestIndex = 0
        var minDiff = abs(standing - standingValues[0])

        for (index, value) in standingValues.enumerated() {
            let diff = abs(standing - value)
            if diff < minDiff {
                minDiff = diff
                closestIndex = index
            }
        }

        return icons[closestIndex]
    }

    var body: some View {
        HStack(spacing: 12) {
            // 头像/图标
            if let iconFilename = result.typeInfo {
                IconManager.shared.loadImage(for: iconFilename)
                    .resizable()
                    .frame(width: 38, height: 38)
                    .cornerRadius(6)
            } else {
                UniversePortrait(id: result.id, type: result.type.recipientType, size: 32)
                    .frame(width: 38, height: 38)
                    .cornerRadius(6)
            }

            // 信息
            VStack(alignment: .leading, spacing: 2) {
                // 第一行：名称
                Text(result.name)
                    .font(.body)

                // 第二行：军团和联盟信息
                if result.type == .character {
                    if let corpName = result.corporationName {
                        Text(corpName)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Text("[No Corp]")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    if let allianceName = result.allianceName {
                        Text("\(allianceName)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        Text("[No Alliance]")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                } else if result.type == .corporation {
                    // 军团搜索时显示联盟信息
                    if let allianceName = allianceName {
                        Text("[\(allianceName)]")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                // 第三行：位置信息（仅建筑搜索时显示）
                if let locationInfo = result.locationInfo {
                    HStack(spacing: 4) {
                        // 安全等级
                        Text(formatSystemSecurity(locationInfo.security))
                            .foregroundColor(getSecurityColor(locationInfo.security))

                        // 星系名
                        Text("\(locationInfo.systemName) / \(locationInfo.regionName)")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }

            Spacer()

            // 声望图标（非建筑搜索时显示）
            if result.type != .structure {
                Image(standingIcon)
                    .resizable()
                    .cornerRadius(1)
                    .frame(width: 12, height: 12)
                    .shadow(color: Color.secondary, radius: 2, x: 0, y: 0)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            scheduleLoad()
            // 只在非建筑搜索时，且不是军团类型时立即计算声望
            if result.type != .structure && result.type != .corporation {
                Task {
                    await determineStandingIcon()
                }
            }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private func scheduleLoad() {
        loadTask?.cancel()
        loadTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms delay
            if !Task.isCancelled {
                // 只有当结果类型是军团时才加载军团信息
                if result.type == .corporation && !hasAttemptedCorpInfoLoad {
                    await loadCorporationInfo()
                    // 如果加载到了联盟ID，继续加载联盟名称
                    if allianceId != nil && !hasAttemptedAllianceLoad {
                        await loadAllianceName()
                        // 只有在军团信息和联盟名称都加载完成后，才计算声望
                        if !Task.isCancelled {
                            await determineStandingIcon()
                        }
                    } else {
                        // 如果军团没有联盟，也可以计算声望了
                        if !Task.isCancelled {
                            await determineStandingIcon()
                        }
                    }
                }
                // 如果是角色搜索结果且已有联盟ID，直接加载联盟名称
                else if result.type == .character && result.allianceId != nil
                    && !hasAttemptedAllianceLoad
                {
                    allianceId = result.allianceId
                    await loadAllianceName()
                }
            }
        }
    }

    private func loadCorporationInfo() async {
        guard !isLoadingCorpInfo && !hasAttemptedCorpInfoLoad else { return }

        isLoadingCorpInfo = true
        hasAttemptedCorpInfoLoad = true
        do {
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(
                corporationId: result.id)
            {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.allianceId = corpInfo.alliance_id
                    }
                }
            }
        }
        isLoadingCorpInfo = false
    }

    private func loadAllianceName() async {
        guard let allianceId = allianceId, !isLoadingAlliance && !hasAttemptedAllianceLoad else {
            return
        }

        isLoadingAlliance = true
        hasAttemptedAllianceLoad = true
        do {
            let allianceNamesWithCategories = try await UniverseAPI.shared.getNamesWithFallback(
                ids: [allianceId])
            if let allianceName = allianceNamesWithCategories[allianceId]?.name {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.allianceName = allianceName
                    }
                }
            }
        } catch {
            Logger.error("加载联盟名称失败: \(error)")
        }
        isLoadingAlliance = false
    }
}

// 视图模型
@MainActor
class SearcherViewModel: ObservableObject {
    @Published var searchResults: [SearcherView.SearchResult] = []
    @Published var filteredResults: [SearcherView.SearchResult] = []
    @Published var searchingStatus = ""
    @Published var error: Error?

    private var searchTask: Task<Void, Never>?
    private var currentCorpFilter = ""
    private var currentAllianceFilter = ""
    private var currentStructureType: SearcherView.StructureType = .all
    private var corporationNames: [Int: String] = [:]
    private var allianceNames: [Int: String] = [:]

    // 直接从ESI获取名称的方法
    private func fetchNamesFromESI(ids: [Int]) async throws -> [Int: String] {
        let urlString = "https://esi.evetech.net/latest/universe/names/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 准备请求数据
        let jsonData = try JSONEncoder().encode(ids)

        // 发送POST请求
        let data = try await NetworkManager.shared.fetchData(
            from: url,
            method: "POST",
            body: jsonData
        )

        // 解析响应数据
        let responses = try JSONDecoder().decode([UniverseNameResponse].self, from: data)

        // 转换为字典
        var namesMap: [Int: String] = [:]
        for response in responses {
            namesMap[response.id] = response.name
        }

        return namesMap
    }

    // 直接从ESI获取角色公开信息的方法
    private func fetchCharacterInfoFromESI(characterId: Int) async throws -> CharacterPublicInfo {
        let urlString =
            "https://esi.evetech.net/latest/characters/\(characterId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        let data = try await NetworkManager.shared.fetchData(from: url)
        return try JSONDecoder().decode(CharacterPublicInfo.self, from: data)
    }

    func search(characterId: Int, searchText: String, type: SearcherView.SearchType) async {
        // 先检查搜索文本是否有效
        guard !searchText.isEmpty && searchText.count > 2 else {
            searchResults = []
            filteredResults = []
            searchingStatus = ""
            return
        }

        searchingStatus = NSLocalizedString("Main_Search_Status_Searching", comment: "")

        do {
            error = nil
            searchResults = []
            filteredResults = []

            switch type {
            case .character:
                let characterSearch = CharacterSearchView(
                    characterId: characterId,
                    searchText: searchText,
                    searchResults: Binding(
                        get: { self.searchResults },
                        set: { self.searchResults = $0 }
                    ),
                    filteredResults: Binding(
                        get: { self.filteredResults },
                        set: { self.filteredResults = $0 }
                    ),
                    searchingStatus: Binding(
                        get: { self.searchingStatus },
                        set: { self.searchingStatus = $0 }
                    ),
                    error: Binding(
                        get: { self.error },
                        set: { self.error = $0 }
                    ),
                    corporationFilter: currentCorpFilter,
                    allianceFilter: currentAllianceFilter
                )
                await characterSearch.search()
                // 搜索完成后应用当前过滤条件
                if type == .character {
                    filterResults(
                        corporationFilter: currentCorpFilter, allianceFilter: currentAllianceFilter
                    )
                }

            case .corporation:
                let corporationSearch = CorporationSearchView(
                    characterId: characterId,
                    searchText: searchText,
                    searchResults: Binding(
                        get: { self.searchResults },
                        set: { self.searchResults = $0 }
                    ),
                    filteredResults: Binding(
                        get: { self.filteredResults },
                        set: { self.filteredResults = $0 }
                    ),
                    searchingStatus: Binding(
                        get: { self.searchingStatus },
                        set: { self.searchingStatus = $0 }
                    ),
                    error: Binding(
                        get: { self.error },
                        set: { self.error = $0 }
                    )
                )
                await corporationSearch.search()

            case .alliance:
                let allianceSearch = AllianceSearchView(
                    characterId: characterId,
                    searchText: searchText,
                    searchResults: Binding(
                        get: { self.searchResults },
                        set: { self.searchResults = $0 }
                    ),
                    filteredResults: Binding(
                        get: { self.filteredResults },
                        set: { self.filteredResults = $0 }
                    ),
                    searchingStatus: Binding(
                        get: { self.searchingStatus },
                        set: { self.searchingStatus = $0 }
                    ),
                    error: Binding(
                        get: { self.error },
                        set: { self.error = $0 }
                    )
                )
                await allianceSearch.search()

            case .structure:
                let structureSearch = StructureSearchView(
                    characterId: characterId,
                    searchText: searchText,
                    searchResults: Binding(
                        get: { self.searchResults },
                        set: { self.searchResults = $0 }
                    ),
                    filteredResults: Binding(
                        get: { self.filteredResults },
                        set: { self.filteredResults = $0 }
                    ),
                    searchingStatus: Binding(
                        get: { self.searchingStatus },
                        set: { self.searchingStatus = $0 }
                    ),
                    error: Binding(
                        get: { self.error },
                        set: { self.error = $0 }
                    ),
                    structureType: currentStructureType
                )
                try await structureSearch.search()
                // 搜索完成后应用当前建筑类型过滤条件
                if type == .structure {
                    updateStructureFilters(structureType: currentStructureType)
                }
            }

        } catch {
            if error is CancellationError {
                Logger.debug("搜索任务被取消")
                return
            }
            Logger.error("搜索失败: \(error)")
            self.error = error
        }
        searchingStatus = ""
    }

    func filterResults(corporationFilter: String, allianceFilter: String) {
        // 保存当前的过滤条件
        currentCorpFilter = corporationFilter
        currentAllianceFilter = allianceFilter

        let corpFilter = corporationFilter.lowercased()
        let allianceFilter = allianceFilter.lowercased()

        if corpFilter.isEmpty && allianceFilter.isEmpty {
            // 如果没有过滤条件，显示所有结果
            filteredResults = searchResults
        } else {
            // 根据过滤条件筛选结果
            filteredResults = searchResults.filter { result in
                let matchCorp =
                    corpFilter.isEmpty
                    || (result.corporationName?.lowercased().contains(corpFilter) ?? false)
                let matchAlliance =
                    allianceFilter.isEmpty
                    || (result.allianceName?.lowercased().contains(allianceFilter) ?? false)
                return matchCorp && matchAlliance
            }
        }

        Logger.debug("过滤结果：原有 \(searchResults.count) 个结果，过滤后剩余 \(filteredResults.count) 个结果")
    }

    func debounceSearch(characterId: Int, searchText: String, type: SearcherView.SearchType) {
        searchTask?.cancel()

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
            if Task.isCancelled { return }
            await search(characterId: characterId, searchText: searchText, type: type)
        }
    }

    func updateStructureFilters(structureType: SearcherView.StructureType) {
        currentStructureType = structureType

        // 根据建筑类型过滤结果
        if structureType == .all {
            filteredResults = searchResults
        } else {
            filteredResults = searchResults.filter { result in
                result.structureType == structureType
            }
        }
    }
}
