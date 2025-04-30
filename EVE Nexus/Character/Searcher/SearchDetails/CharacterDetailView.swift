import SwiftUI

// 移除HTML标签的扩展
extension String {
    fileprivate func removeHTMLTags() -> String {
        // 移除所有HTML标签
        let text = replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        // 将HTML实体转换为对应字符
        return text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CharacterDetailView: View {
    let characterId: Int
    let character: EVECharacterInfo
    @State private var portrait: UIImage?
    @State private var characterInfo: CharacterPublicInfo?
    @State private var employmentHistory: [CharacterEmploymentHistory] = []
    @State private var corporationInfo: (name: String, icon: UIImage?)?
    @State private var allianceInfo: (name: String, icon: UIImage?)?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var selectedTab = 0  // 添加选项卡状态
    // 添加声望相关的状态
    @State private var personalStandings: [Int: Double] = [:]
    @State private var corpStandings: [Int: Double] = [:]
    @State private var allianceStandings: [Int: Double] = [:]
    @State private var myCorpInfo: (name: String, icon: UIImage?)?
    @State private var myAllianceInfo: (name: String, icon: UIImage?)?
    @State private var standingsLoaded = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = error {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(error.localizedDescription)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                }
            } else if let characterInfo = characterInfo {
                // 基本信息和组织信息合并到一个 Section
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        // 左侧头像
                        if let portrait = portrait {
                            Image(uiImage: portrait)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        // 右侧信息
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer()
                                .frame(height: 8)

                            // 人物名称
                            Text(characterInfo.name)
                                .font(.system(size: 20, weight: .bold))
                                .textSelection(.enabled)
                                .lineLimit(1)

                            // 人物头衔
                            if let title = characterInfo.title, !title.isEmpty {
                                Text(title.removeHTMLTags())
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            } else {
                                Text("[\(NSLocalizedString("Main_No_Title", comment: ""))]")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .padding(.top, 2)
                            }

                            Spacer()
                                .frame(minHeight: 8)

                            // 军团信息
                            if let corpInfo = corporationInfo {
                                HStack(spacing: 8) {
                                    if let icon = corpInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(corpInfo.name)
                                        .font(.system(size: 14))
                                        .textSelection(.enabled)
                                        .lineLimit(1)
                                }
                            }

                            // 联盟信息
                            HStack(spacing: 8) {
                                if let allianceInfo = allianceInfo, let icon = allianceInfo.icon {
                                    Image(uiImage: icon)
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(allianceInfo.name)
                                        .textSelection(.enabled)
                                        .font(.system(size: 14))
                                        .lineLimit(1)
                                } else {
                                    Image(systemName: "square.dashed")
                                        .resizable()
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(.gray)
                                    Text("\(NSLocalizedString("No Alliance", comment: ""))")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.top, 4)

                            Spacer()
                                .frame(height: 8)
                        }
                        .frame(height: 96)  // 与头像等高
                    }
                    .padding(.vertical, 4)
                }

                // 添加Picker组件
                Section {
                    Picker(selection: $selectedTab, label: Text("")) {
                        Text(NSLocalizedString("Standings", comment: ""))
                            .tag(0)
                        Text(NSLocalizedString("Employment History", comment: ""))
                            .tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if selectedTab == 0 {
                        StandingsView(
                            characterId: characterId,
                            character: character,
                            targetCharacter: characterInfo,
                            corporationInfo: corporationInfo,
                            allianceInfo: allianceInfo,
                            personalStandings: personalStandings,
                            corpStandings: corpStandings,
                            allianceStandings: allianceStandings,
                            myCorpInfo: myCorpInfo,
                            myAllianceInfo: myAllianceInfo
                        )
                    } else if selectedTab == 1 {
                        EmploymentHistoryView(history: employmentHistory)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCharacterDetails()
        }
    }

    private func loadCharacterDetails() async {
        Logger.info("开始加载角色详细信息 - 角色ID: \(characterId)")
        isLoading = true
        error = nil

        do {
            // 并发加载所有需要的数据
            Logger.info("开始并发加载角色信息、头像和雇佣历史")
            async let characterInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: characterId, forceRefresh: true
            )
            async let portraitTask = CharacterAPI.shared.fetchCharacterPortrait(
                characterId: characterId, catchImage: false
            )
            async let historyTask = CharacterAPI.shared.fetchEmploymentHistory(
                characterId: characterId)

            // 等待所有数据加载完成
            let (info, portrait, history) = try await (characterInfoTask, portraitTask, historyTask)
            Logger.info("成功加载角色基本信息")
            Logger.info("雇佣历史记录数: \(history.count)")

            // 更新状态
            characterInfo = info
            self.portrait = portrait
            employmentHistory = history

            // 加载军团信息
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(
                corporationId: info.corporation_id)
            {
                Logger.info("成功加载军团信息: \(corpInfo.name)")
                let corpIcon = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: info.corporation_id)
                corporationInfo = (name: corpInfo.name, icon: corpIcon)
            }

            // 加载联盟信息
            if let allianceId = info.alliance_id {
                let allianceNames = try? await UniverseAPI.shared.getNamesWithFallback(ids: [
                    allianceId
                ])
                if let allianceName = allianceNames?[allianceId]?.name {
                    Logger.info("成功加载联盟信息: \(allianceName)")
                    let allianceIcon = try? await AllianceAPI.shared.fetchAllianceLogo(
                        allianceID: allianceId)
                    allianceInfo = (name: allianceName, icon: allianceIcon)
                }
            }

            // 加载声望数据
            if !standingsLoaded {
                await loadStandings()
                standingsLoaded = true
            }

        } catch {
            Logger.error("加载角色详细信息失败: \(error)")
            self.error = error
        }

        isLoading = false
        Logger.info("角色详细信息加载完成")
    }

    private func loadStandings() async {
        // 加载我的军团信息
        if let corpId = character.corporationId {
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(
                corporationId: corpId)
            {
                let corpIcon = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: corpId)
                myCorpInfo = (name: corpInfo.name, icon: corpIcon)
            }
        }

        // 加载我的联盟信息
        if let allianceId = character.allianceId {
            let allianceNames = try? await UniverseAPI.shared.getNamesWithFallback(ids: [allianceId]
            )
            if let allianceName = allianceNames?[allianceId]?.name {
                let allianceIcon = try? await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: allianceId)
                myAllianceInfo = (name: allianceName, icon: allianceIcon)
            }
        }

        // 加载个人声望
        if let contacts = try? await GetCharContacts.shared.fetchContacts(
            characterId: character.CharacterID)
        {
            for contact in contacts {
                personalStandings[contact.contact_id] = contact.standing
            }
        }

        // 加载军团声望
        if let corpId = character.corporationId,
            let contacts = try? await GetCorpContacts.shared.fetchContacts(
                characterId: character.CharacterID, corporationId: corpId
            )
        {
            for contact in contacts {
                corpStandings[contact.contact_id] = contact.standing
            }
        }

        // 加载联盟声望
        if let allianceId = character.allianceId,
            let contacts = try? await GetAllianceContacts.shared.fetchContacts(
                characterId: character.CharacterID, allianceId: allianceId
            )
        {
            for contact in contacts {
                allianceStandings[contact.contact_id] = contact.standing
            }
        }
    }

    // 声望行视图
    struct StandingRowView: View {
        let leftPortrait: (id: Int, type: MailRecipient.RecipientType)
        let rightPortrait: (id: Int, type: MailRecipient.RecipientType)
        let leftName: String
        let rightName: String
        let standing: Double?
        @State private var leftImage: UIImage?
        @State private var rightImage: UIImage?

        var body: some View {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // 左侧头像和名称
                    HStack(spacing: 6) {
                        Text(leftName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        if let image = leftImage {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(3)
                        } else {
                            Color.gray
                                .frame(width: 24, height: 24)
                                .cornerRadius(3)
                        }
                    }
                    .frame(width: geometry.size.width * 0.4, alignment: .trailing)

                    // 中间声望值
                    if let standing = standing {
                        Text(
                            standing > 0
                                ? "+\(String(format: "%.0f", standing))"
                                : standing < 0 ? "\(String(format: "%.0f", standing))" : "0"
                        )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(getStandingColor(standing: standing))
                        .frame(width: geometry.size.width * 0.2, alignment: .center)
                    } else {
                        Text("0")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: geometry.size.width * 0.2, alignment: .center)
                    }

                    // 右侧头像和名称
                    HStack(spacing: 6) {
                        if let image = rightImage {
                            Image(uiImage: image)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(3)
                        } else {
                            Color.gray
                                .frame(width: 24, height: 24)
                                .cornerRadius(3)
                        }
                        Text(rightName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    .frame(width: geometry.size.width * 0.4, alignment: .leading)
                }
            }
            .frame(height: 32)  // 设置固定高度以确保一致性
            .task {
                await loadImages()
            }
        }

        private func loadImages() async {
            // 加载左侧头像
            switch leftPortrait.type {
            case .character:
                leftImage = try? await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: leftPortrait.id)
            case .corporation:
                leftImage = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: leftPortrait.id)
            case .alliance:
                leftImage = try? await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: leftPortrait.id)
            default:
                break
            }

            // 加载右侧头像
            switch rightPortrait.type {
            case .character:
                rightImage = try? await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: rightPortrait.id, catchImage: false
                )
            case .corporation:
                rightImage = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: rightPortrait.id)
            case .alliance:
                rightImage = try? await AllianceAPI.shared.fetchAllianceLogo(
                    allianceID: rightPortrait.id)
            default:
                break
            }
        }

        private func getStandingColor(standing: Double) -> Color {
            switch standing {
            case 10.0:
                return Color.blue  // 深蓝
            case 5.0..<10.0:
                return Color.blue  // 深蓝
            case 0.1..<5.0:
                return Color(red: 0.3, green: 0.7, blue: 1.0)  // 浅蓝
            case 0.0:
                return Color.secondary  // 次要颜色
            case -5.0..<0.0:
                return Color(red: 1.0, green: 0.5, blue: 0.0)  // 橙红
            case -10.0 ... -5.0:
                return Color.red  // 红色
            case ..<(-10.0):
                return Color.red  // 红色
            default:
                return Color.secondary
            }
        }
    }

    // 声望详情视图
    struct StandingsView: View {
        let characterId: Int
        let character: EVECharacterInfo
        let targetCharacter: CharacterPublicInfo?
        let corporationInfo: (name: String, icon: UIImage?)?
        let allianceInfo: (name: String, icon: UIImage?)?
        let personalStandings: [Int: Double]
        let corpStandings: [Int: Double]
        let allianceStandings: [Int: Double]
        let myCorpInfo: (name: String, icon: UIImage?)?
        let myAllianceInfo: (name: String, icon: UIImage?)?

        var body: some View {
            VStack {
                if let targetCharacter = targetCharacter {
                    VStack(alignment: .leading, spacing: 8) {
                        // 个人声望
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("Personal Standings", comment: ""))
                                .font(.headline)
                                .padding(.bottom, 4)

                            // 我对目标角色
                            StandingRowView(
                                leftPortrait: (id: character.CharacterID, type: .character),
                                rightPortrait: (id: characterId, type: .character),
                                leftName: character.CharacterName,
                                rightName: targetCharacter.name,
                                standing: personalStandings[characterId]
                            )

                            // 我军团对目标角色
                            if let corpId = character.corporationId {
                                StandingRowView(
                                    leftPortrait: (id: corpId, type: .corporation),
                                    rightPortrait: (id: characterId, type: .character),
                                    leftName: myCorpInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: targetCharacter.name,
                                    standing: corpStandings[characterId]
                                )
                            }

                            // 我联盟对目标角色
                            if let allianceId = character.allianceId {
                                StandingRowView(
                                    leftPortrait: (id: allianceId, type: .alliance),
                                    rightPortrait: (id: characterId, type: .character),
                                    leftName: myAllianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: targetCharacter.name,
                                    standing: allianceStandings[characterId]
                                )
                            }
                        }

                        Divider()

                        // 军团声望
                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("Corporation Standings", comment: ""))
                                .font(.headline)
                                .padding(.bottom, 4)

                            // 我对目标军团
                            StandingRowView(
                                leftPortrait: (id: character.CharacterID, type: .character),
                                rightPortrait: (
                                    id: targetCharacter.corporation_id, type: .corporation
                                ),
                                leftName: character.CharacterName,
                                rightName: corporationInfo?.name
                                    ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                standing: personalStandings[targetCharacter.corporation_id]
                            )

                            // 我军团对目标军团
                            if let corpId = character.corporationId {
                                StandingRowView(
                                    leftPortrait: (id: corpId, type: .corporation),
                                    rightPortrait: (
                                        id: targetCharacter.corporation_id, type: .corporation
                                    ),
                                    leftName: myCorpInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: corporationInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: corpStandings[targetCharacter.corporation_id]
                                )
                            }

                            // 我联盟对目标军团
                            if let allianceId = character.allianceId {
                                StandingRowView(
                                    leftPortrait: (id: allianceId, type: .alliance),
                                    rightPortrait: (
                                        id: targetCharacter.corporation_id, type: .corporation
                                    ),
                                    leftName: myAllianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    rightName: corporationInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: allianceStandings[targetCharacter.corporation_id]
                                )
                            }
                        }

                        if let targetAllianceId = targetCharacter.alliance_id {
                            Divider()

                            // 联盟声望
                            VStack(alignment: .leading, spacing: 8) {
                                Text(NSLocalizedString("Alliance Standings", comment: ""))
                                    .font(.headline)
                                    .padding(.bottom, 4)

                                // 我对目标联盟
                                StandingRowView(
                                    leftPortrait: (id: character.CharacterID, type: .character),
                                    rightPortrait: (id: targetAllianceId, type: .alliance),
                                    leftName: character.CharacterName,
                                    rightName: allianceInfo?.name
                                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                    standing: personalStandings[targetAllianceId]
                                )

                                // 我军团对目标联盟
                                if let corpId = character.corporationId {
                                    StandingRowView(
                                        leftPortrait: (id: corpId, type: .corporation),
                                        rightPortrait: (id: targetAllianceId, type: .alliance),
                                        leftName: myCorpInfo?.name
                                            ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                        rightName: allianceInfo?.name
                                            ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                        standing: corpStandings[targetAllianceId]
                                    )
                                }

                                // 我联盟对目标联盟
                                if let allianceId = character.allianceId {
                                    StandingRowView(
                                        leftPortrait: (id: allianceId, type: .alliance),
                                        rightPortrait: (id: targetAllianceId, type: .alliance),
                                        leftName: myAllianceInfo?.name
                                            ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                        rightName: allianceInfo?.name
                                            ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                        standing: allianceStandings[targetAllianceId]
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 雇佣历史视图
    struct EmploymentHistoryView: View {
        let history: [CharacterEmploymentHistory]

        var body: some View {
            if history.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "exclamationmark.triangle")
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.record_id) { index, record in
                        if let startDate = parseDate(record.start_date) {
                            let endDate = index > 0 ? parseDate(history[index - 1].start_date) : nil

                            VStack(spacing: 0) {
                                EmploymentHistoryRowView(
                                    corporationId: record.corporation_id,
                                    startDate: startDate,
                                    endDate: endDate
                                )
                                .padding(.vertical, 4)

                                if index < history.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }

        private func parseDate(_ dateString: String) -> Date? {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            return dateFormatter.date(from: dateString)
        }
    }

    // 雇佣历史行视图
    struct EmploymentHistoryRowView: View {
        let corporationId: Int
        let startDate: Date
        let endDate: Date?
        @State private var corporationInfo: (name: String, icon: UIImage?)?

        var body: some View {
            HStack(spacing: 6) {
                // 军团图标
                if let icon = corporationInfo?.icon {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .cornerRadius(3)
                } else {
                    Color.gray
                        .frame(width: 24, height: 24)
                        .cornerRadius(3)
                }

                // 右侧信息
                VStack(alignment: .leading, spacing: 2) {
                    // 军团名称
                    Text(corporationInfo?.name ?? NSLocalizedString("Misc_Loading", comment: ""))
                        .font(.system(size: 12))
                        .lineLimit(1)

                    // 时间信息
                    HStack(spacing: 4) {
                        Text(formatDateRange(start: startDate, end: endDate))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(formatDuration(start: startDate, end: endDate))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task {
                await loadCorporationInfo()
            }
        }

        private func loadCorporationInfo() async {
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(
                corporationId: corporationId)
            {
                let corpIcon = try? await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: corporationId)
                await MainActor.run {
                    self.corporationInfo = (name: corpInfo.name, icon: corpIcon)
                }
            }
        }

        private func formatDateRange(start: Date, end: Date?) -> String {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy.MM.dd"
            let startStr = dateFormatter.string(from: start)

            if let end = end {
                let endStr = dateFormatter.string(from: end)
                return "\(startStr) - \(endStr)"
            } else {
                return "\(startStr) - 至今"
            }
        }

        private func formatDuration(start: Date, end: Date?) -> String {
            let components = Calendar.current.dateComponents(
                [.day, .hour], from: start, to: end ?? Date()
            )
            let days = components.day ?? 0
            let hours = components.hour ?? 0

            if days == 0 {
                return "(\(hours)小时)"
            } else {
                return "(\(days)天)"
            }
        }
    }
}
