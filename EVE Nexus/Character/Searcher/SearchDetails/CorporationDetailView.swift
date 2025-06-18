import SwiftUI

struct CorporationDetailView: View {
    let corporationId: Int
    let character: EVECharacterInfo
    @State private var logo: UIImage?
    @State private var corporationInfo: CorporationInfo?
    @State private var allianceInfo: (name: String, icon: UIImage?)?
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
                        }

                        // 右侧信息
                        VStack(alignment: .leading, spacing: 0) {
                            Spacer()
                                .frame(height: 8)

                            // 军团名称
                            Text(corporationInfo.name)
                                .font(.system(size: 20, weight: .semibold))
                                .lineLimit(1)
                                .textSelection(.enabled)

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
                                        .textSelection(.enabled)
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
                        .frame(height: 96)  // 与Logo等高
                    }
                    .padding(.vertical, 4)
                }

                // 军团基本信息
                Section {
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
                    Section(header: Text("\(NSLocalizedString("Description", comment: ""))")) {
                        Text(TextProcessingUtil.processDescription(corporationInfo.description))
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                    }
                }
                Section(header: Text(NSLocalizedString("Standings", comment: ""))) {
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
            Logger.info("开始并发加载军团信息和Logo")
            async let corporationInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: corporationId, forceRefresh: true
            )
            async let logoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: corporationId)

            // 等待所有数据加载完成
            let (info, logo) = try await (corporationInfoTask, logoTask)
            Logger.info("成功加载军团基本信息")

            // 更新状态
            corporationInfo = info
            self.logo = logo

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
