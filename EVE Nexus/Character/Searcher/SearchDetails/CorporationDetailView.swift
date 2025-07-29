import SwiftUI

struct CorporationDetailView: View {
    let corporationId: Int
    let character: EVECharacterInfo
    @State private var logo: UIImage?
    @State private var corporationInfo: CorporationInfo?
    @State private var allianceInfo: (name: String, icon: UIImage?)?
    @State private var factionInfo: (name: String, iconName: String)?
    @State private var ceoInfo: CharacterPublicInfo?
    @State private var ceoPortrait: UIImage?
    @State private var isLoading = true
    @State private var error: Error?
    // 声望相关的状态
    @State private var personalStandings: [Int: Double] = [:]
    @State private var corpStandings: [Int: Double] = [:]
    @State private var allianceStandings: [Int: Double] = [:]
    @State private var myCorpInfo: (name: String, icon: UIImage?)?
    @State private var myAllianceInfo: (name: String, icon: UIImage?)?
    @State private var standingsLoaded = false
    @State private var selectedTab = 0  // 添加选项卡状态
    @State private var allianceHistory: [CorporationAllianceHistory] = []

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
            } else if let corporationInfo = corporationInfo {
                // 基本信息和组织信息
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        // 左侧Logo
                        if let logo = logo {
                            Image(uiImage: logo)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(.primary, lineWidth: 1)
                                        .opacity(0.3)
                                )
                        }

                        // 右侧信息
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer()
                                .frame(height: 8)

                            // 军团名称
                            Text(corporationInfo.name)
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(1)

                            // 军团代号
                            Text("[\(corporationInfo.ticker)]")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .padding(.top, 2)

                            Spacer()
                                .frame(minHeight: 8)

                            // CEO信息
                            if let ceoInfo = ceoInfo {
                                HStack(spacing: 8) {
                                    if let portrait = ceoPortrait {
                                        Image(uiImage: portrait)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text("\(NSLocalizedString("CEO", comment: "")): ")
                                        .font(.system(size: 14))
                                    Text(ceoInfo.name)
                                        .font(.system(size: 14))
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
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = corporationInfo.name
                            } label: {
                                Label(NSLocalizedString("Misc_Copy_CorpID", comment: ""), systemImage: "doc.on.doc")
                            }
                            if let ceoInfo = ceoInfo {
                                Button {
                                    UIPasteboard.general.string = ceoInfo.name
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy_CEO_CharID", comment: ""), systemImage: "doc.on.doc")
                                }
                            }
                            if let allianceInfo = allianceInfo {
                                Button {
                                    UIPasteboard.general.string = allianceInfo.name
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy_Alliance", comment: ""), systemImage: "doc.on.doc")
                                }
                            }
                        }
                        .frame(height: 96)  // 与Logo等高
                    }
                    .padding(.vertical, 4)
                }

                // 军团基本信息
                Section {
                    // 势力信息
                    if let faction = factionInfo {
                        HStack(spacing: 8) {
                            Text("\(NSLocalizedString("Character_Faction", comment: ""))")
                            Spacer()
                            IconManager.shared.loadImage(for: faction.iconName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(faction.name)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // 成员数量
                    HStack {
                        Text("\(NSLocalizedString("Member Count", comment: ""))")
                        Spacer()
                        Text("\(corporationInfo.member_count)")
                            .foregroundColor(.secondary)
                    }

                    // 税率
                    HStack {
                        Text("\(NSLocalizedString("Tax Rate", comment: ""))")
                        Spacer()
                        Text(String(format: "%.1f%%", corporationInfo.tax_rate * 100))
                            .foregroundColor(.secondary)
                    }

                    // 成立时间
                    if let dateFoundedStr = corporationInfo.date_founded,
                        let dateFounded = ISO8601DateFormatter().date(from: dateFoundedStr)
                    {
                        HStack {
                            Text("\(NSLocalizedString("Main_Founded", comment: ""))")
                            Spacer()
                            Text(dateFounded, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 军团描述
                if !corporationInfo.description.isEmpty {
                    let description = TextProcessingUtil.processDescription(corporationInfo.description)
                    Section(header: Text("\(NSLocalizedString("Description", comment: ""))")) {
                        Text(description)
                            .font(.system(size: 14))
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = description
                                } label: {
                                    Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                                }
                            }
                    }
                }
                // 添加Picker组件
                Section {
                    Picker(selection: $selectedTab, label: Text("")) {
                        Text(NSLocalizedString("Standings", comment: ""))
                            .tag(0)
                        Text(NSLocalizedString("Alliance History", comment: ""))
                            .tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if selectedTab == 0 {
                        StandingsView(
                            corporationId: corporationId,
                            character: character,
                            corporationInfo: corporationInfo,
                            allianceInfo: allianceInfo,
                            personalStandings: personalStandings,
                            corpStandings: corpStandings,
                            allianceStandings: allianceStandings,
                            myCorpInfo: myCorpInfo,
                            myAllianceInfo: myAllianceInfo
                        )
                    } else if selectedTab == 1 {
                        AllianceHistoryView(history: allianceHistory, corporationId: corporationId, corporationLogo: logo)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCorporationDetails()
        }
    }

    private func loadCorporationDetails() async {
        Logger.info("开始加载军团详细信息 - 军团ID: \(corporationId)")
        isLoading = true
        error = nil

        do {
            // 并发加载所有需要的数据
            Logger.info("开始并发加载军团信息、Logo和联盟历史")
            async let corporationInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: corporationId, forceRefresh: true
            )
            async let logoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: corporationId)
            async let allianceHistoryTask = CorporationAPI.shared.fetchAllianceHistory(
                corporationId: corporationId)

            // 等待所有数据加载完成
            let (info, logo, history) = try await (corporationInfoTask, logoTask, allianceHistoryTask)
            Logger.info("成功加载军团基本信息")

            // 更新状态
            corporationInfo = info
            self.logo = logo
            allianceHistory = history

            // 加载CEO信息
            if let ceoInfo = try? await CharacterAPI.shared.fetchCharacterPublicInfo(
                characterId: info.ceo_id)
            {
                Logger.info("成功加载CEO信息: \(ceoInfo.name)")
                let ceoPortrait = try? await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: info.ceo_id, catchImage: false
                )
                self.ceoInfo = ceoInfo
                self.ceoPortrait = ceoPortrait
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

            // 加载势力信息
            if let factionId = info.faction_id {
                let query = "SELECT name, iconName FROM factions WHERE id = ?"
                if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [factionId]),
                   let row = rows.first,
                   let name = row["name"] as? String,
                   let iconName = row["iconName"] as? String {
                    Logger.info("成功加载势力信息: \(name)")
                    factionInfo = (name: name, iconName: iconName)
                }
            }
            
            // 加载声望数据
            if !standingsLoaded {
                await loadStandings()
                standingsLoaded = true
            }

        } catch {
            Logger.error("加载军团详细信息失败: \(error)")
            self.error = error
        }

        isLoading = false
        Logger.info("军团详细信息加载完成")
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
                    corporationId: leftPortrait.id, size: 128
                )
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
        let corporationId: Int
        let character: EVECharacterInfo
        let corporationInfo: CorporationInfo
        let allianceInfo: (name: String, icon: UIImage?)?
        let personalStandings: [Int: Double]
        let corpStandings: [Int: Double]
        let allianceStandings: [Int: Double]
        let myCorpInfo: (name: String, icon: UIImage?)?
        let myAllianceInfo: (name: String, icon: UIImage?)?

        var body: some View {
            VStack {
                VStack(alignment: .leading, spacing: 8) {
                    // 军团声望
                    VStack(alignment: .leading, spacing: 8) {
                        Text(NSLocalizedString("Corporation Standings", comment: ""))
                            .font(.headline)
                            .padding(.bottom, 4)

                        // 我对目标军团
                        StandingRowView(
                            leftPortrait: (id: character.CharacterID, type: .character),
                            rightPortrait: (id: corporationId, type: .corporation),
                            leftName: character.CharacterName,
                            rightName: corporationInfo.name,
                            standing: personalStandings[corporationId]
                        )

                        // 我军团对目标军团
                        if let corpId = character.corporationId {
                            StandingRowView(
                                leftPortrait: (id: corpId, type: .corporation),
                                rightPortrait: (id: corporationId, type: .corporation),
                                leftName: myCorpInfo?.name
                                    ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                rightName: corporationInfo.name,
                                standing: corpStandings[corporationId]
                            )
                        }

                        // 我联盟对目标军团
                        if let allianceId = character.allianceId {
                            StandingRowView(
                                leftPortrait: (id: allianceId, type: .alliance),
                                rightPortrait: (id: corporationId, type: .corporation),
                                leftName: myAllianceInfo?.name
                                    ?? NSLocalizedString("Standing_Unknown", comment: ""),
                                rightName: corporationInfo.name,
                                standing: allianceStandings[corporationId]
                            )
                        }
                    }

                    if let targetAllianceId = corporationInfo.alliance_id {
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

// 联盟历史视图
struct AllianceHistoryView: View {
    let history: [CorporationAllianceHistory]
    let corporationId: Int
    let corporationLogo: UIImage?

    var body: some View {
        // 过滤掉没有联盟的记录（alliance_id为nil的记录）
        let filteredHistory = history.filter { $0.alliance_id != nil }
        
        if filteredHistory.isEmpty {
            ContentUnavailableView {
                Label(
                    NSLocalizedString("Misc_No_Data", comment: "无数据"),
                    systemImage: "exclamationmark.triangle")
            }
        } else {
            ForEach(Array(filteredHistory.enumerated()), id: \.element.record_id) { index, record in
                if let startDate = parseDate(record.start_date),
                   let allianceId = record.alliance_id {
                    let endDate = index > 0 ? parseDate(filteredHistory[index - 1].start_date) : nil

                    VStack(spacing: 0) {
                        AllianceHistoryRowView(
                            allianceId: allianceId,
                            startDate: startDate,
                            endDate: endDate,
                            corporationId: corporationId,
                            corporationLogo: corporationLogo
                        )
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

// 联盟历史行视图
struct AllianceHistoryRowView: View {
    let allianceId: Int
    let startDate: Date
    let endDate: Date?
    let corporationId: Int
    let corporationLogo: UIImage?
    @State private var allianceInfo: (name: String, icon: UIImage?)?

    var body: some View {
        HStack(spacing: 6) {
            // 联盟图标
            if let icon = allianceInfo?.icon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(3)
            } else {
                Color.gray
                    .frame(width: 32, height: 32)
                    .cornerRadius(3)
            }

            // 右侧信息
            VStack(alignment: .leading, spacing: 2) {
                // 联盟名称
                Text(allianceInfo?.name ?? NSLocalizedString("Misc_Loading", comment: ""))
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
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            if let allianceName = allianceInfo?.name {
                Button {
                    UIPasteboard.general.string = allianceName
                } label: {
                    Label(NSLocalizedString("Misc_Copy_Alliance", comment: ""), systemImage: "doc.on.doc")
                }
            }
        }
        .task {
            await loadAllianceInfo()
        }
    }

    private func loadAllianceInfo() async {
        // 获取联盟名称
        if let allianceNames = try? await UniverseAPI.shared.getNamesWithFallback(ids: [allianceId]),
           let name = allianceNames[allianceId]?.name {
            // 并发加载联盟图标
            let allianceIcon = try? await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
            
            await MainActor.run {
                self.allianceInfo = (name: name, icon: allianceIcon)
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
            return "\(startStr) - \(NSLocalizedString("Misc_Now", comment: "now"))"
        }
    }

    private func formatDuration(start: Date, end: Date?) -> String {
        let components = Calendar.current.dateComponents(
            [.day, .hour], from: start, to: end ?? Date()
        )
        let days = components.day ?? 0
        let hours = components.hour ?? 0

        if days == 0 {
            return "(\(String(format: NSLocalizedString("Time_Hours_Long", comment: ""), hours)))"
        } else {
            return "(\(String(format: NSLocalizedString("Time_Days_Long", comment: ""), days)))"
        }
    }
}
