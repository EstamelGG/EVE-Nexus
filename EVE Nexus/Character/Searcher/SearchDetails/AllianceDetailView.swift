import SwiftUI

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
    }

    private func getStandingColor(standing: Double) -> Color {
        switch standing {
        case 5.0...10.0:
            return Color.blue  // 蓝色
        case 0.01...4.99:
            return Color(red: 0.0, green: 0.5, blue: 1.0)  // 浅蓝
        case -4.99 ... -0.01:
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

// 声望视图
private struct AllianceStandingsView: View {
    let allianceId: Int
    let allianceName: String
    let character: EVECharacterInfo
    let personalStandings: [Int: Double]
    let corpStandings: [Int: Double]
    let allianceStandings: [Int: Double]
    let myCorpInfo: (name: String, icon: UIImage?)?
    let myAllianceInfo: (name: String, icon: UIImage?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Alliance Standings", comment: ""))
                .font(.headline)
                .padding(.bottom, 4)

            // 我对目标联盟
            StandingRowView(
                leftPortrait: (id: character.CharacterID, type: .character),
                rightPortrait: (id: allianceId, type: .alliance),
                leftName: character.CharacterName,
                rightName: allianceName,
                standing: personalStandings[allianceId]
            )

            // 我军团对目标联盟
            if let corpId = character.corporationId {
                StandingRowView(
                    leftPortrait: (id: corpId, type: .corporation),
                    rightPortrait: (id: allianceId, type: .alliance),
                    leftName: myCorpInfo?.name
                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                    rightName: allianceName,
                    standing: corpStandings[allianceId]
                )
            }

            // 我联盟对目标联盟
            if let myAllianceId = character.allianceId {
                StandingRowView(
                    leftPortrait: (id: myAllianceId, type: .alliance),
                    rightPortrait: (id: allianceId, type: .alliance),
                    leftName: myAllianceInfo?.name
                        ?? NSLocalizedString("Standing_Unknown", comment: ""),
                    rightName: allianceName,
                    standing: allianceStandings[allianceId]
                )
            }
        }
    }
}

struct AllianceDetailView: View {
    let allianceId: Int
    let character: EVECharacterInfo

    @State private var allianceInfo: AllianceInfo?
    @State private var allianceLogo: UIImage?
    @State private var creatorCorpInfo: (name: String, icon: UIImage?)?
    @State private var executorCorpInfo: (name: String, icon: UIImage?)?
    @State private var creatorInfo: (name: String, icon: UIImage?)?
    @State private var factionInfo: (name: String, iconName: String)?
    
    @State private var personalStandings: [Int: Double] = [:]
    @State private var corpStandings: [Int: Double] = [:]
    @State private var allianceStandings: [Int: Double] = [:]

    @State private var myCorpInfo: (name: String, icon: UIImage?)?
    @State private var myAllianceInfo: (name: String, icon: UIImage?)?

    @State private var error: Error?
    @State private var isLoading = true
    @State private var standingsLoaded = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(.circular)
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
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            } else if let allianceInfo = allianceInfo {
                // 联盟基本信息
                Section {
                    HStack(spacing: 16) {
                        // 联盟图标
                        if let logo = allianceLogo {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.primary, lineWidth: 1)
                                        .opacity(0.3)
                                )
                        } else {
                            Image(systemName: "square.dashed")
                                .resizable()
                                .frame(width: 96, height: 96)
                                .foregroundColor(.gray)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            // 联盟名称和代号
                            VStack(alignment: .leading, spacing: 4) {
                                Text(allianceInfo.name)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text("[\(allianceInfo.ticker)]")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            

                            // 执行军团
                            if let executorInfo = executorCorpInfo {
                                HStack(spacing: 4) {
                                    if let icon = executorInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text("\(executorInfo.name)")
                                        .font(.system(size: 14))
                                        .lineLimit(1)
                                }
                            }

                            // 创建者军团
                            if let creatorCorpInfo = creatorCorpInfo {
                                HStack(spacing: 4) {
                                    if let icon = creatorCorpInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(
                                        "\(NSLocalizedString("Creator Corp", comment: "")): \(creatorCorpInfo.name)"
                                    )
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                }
                            }

                            // 创建者
                            if let creatorInfo = creatorInfo {
                                HStack(spacing: 4) {
                                    if let icon = creatorInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(
                                        "\(NSLocalizedString("Creator", comment: "")): \(creatorInfo.name)"
                                    )
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = allianceInfo.name
                        } label: {
                            Label(NSLocalizedString("Misc_Copy_Alliance", comment: ""), systemImage: "doc.on.doc")
                        }
                        if let executorInfo = executorCorpInfo {
                            Button {
                                UIPasteboard.general.string = executorInfo.name
                            } label: {
                                Label("\(NSLocalizedString("Misc_Copy", comment: "")) \(NSLocalizedString("Executor Corp", comment: ""))", systemImage: "doc.on.doc")
                            }
                        }
                        if let creatorCorpInfo = creatorCorpInfo {
                            Button {
                                UIPasteboard.general.string = creatorCorpInfo.name
                            } label: {
                                Label("\(NSLocalizedString("Misc_Copy", comment: "")) \(NSLocalizedString("Creator Corp", comment: ""))", systemImage: "doc.on.doc")
                            }
                        }
                        if let creatorInfo = creatorInfo {
                            Button {
                                UIPasteboard.general.string = creatorInfo.name
                            } label: {
                                Label("\(NSLocalizedString("Misc_Copy", comment: "")) \(NSLocalizedString("Creator", comment: ""))", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }

                // 联盟基本信息
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
                    // 成立时间
                    if let date = ISO8601DateFormatter().date(from: allianceInfo.date_founded) {
                        HStack {
                            Text("\(NSLocalizedString("Main_Founded", comment: ""))")
                            Spacer()
                            Text(date, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 声望信息
                Section {
                    AllianceStandingsView(
                        allianceId: allianceId,
                        allianceName: allianceInfo.name,
                        character: character,
                        personalStandings: personalStandings,
                        corpStandings: corpStandings,
                        allianceStandings: allianceStandings,
                        myCorpInfo: myCorpInfo,
                        myAllianceInfo: myAllianceInfo
                    )
                } header: {
                    Text(NSLocalizedString("Standings", comment: ""))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAllianceDetails()

            if !standingsLoaded {
                await loadStandings()
                standingsLoaded = true
            }
        }
    }

    private func loadAllianceDetails() async {
        isLoading = true

        do {
            // 加载联盟基本信息和图标
            async let allianceInfoTask = AllianceAPI.shared.fetchAllianceInfo(
                allianceId: allianceId)
            async let allianceLogoTask = AllianceAPI.shared.fetchAllianceLogo(
                allianceID: allianceId, size: 128
            )

            let (info, logo) = try await (allianceInfoTask, allianceLogoTask)

            // 加载执行军团信息
            async let executorCorpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: info.executor_corporation_id)
            async let executorCorpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: info.executor_corporation_id)

            // 加载创建者军团信息
            async let creatorCorpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                corporationId: info.creator_corporation_id)
            async let creatorCorpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
                corporationId: info.creator_corporation_id)

            // 加载创建者信息
            let creatorNames = try await UniverseAPI.shared.getNamesWithFallback(ids: [
                info.creator_id
            ])
            let creatorName =
                creatorNames[info.creator_id]?.name ?? NSLocalizedString("Unknown", comment: "")
            let creatorIcon = try? await CharacterAPI.shared.fetchCharacterPortrait(
                characterId: info.creator_id, catchImage: false
            )

            // 等待所有信息加载完成
            let (executorCorpInfo, executorCorpLogo) = try await (
                executorCorpInfoTask, executorCorpLogoTask
            )
            let (creatorCorpInfo, creatorCorpLogo) = try await (
                creatorCorpInfoTask, creatorCorpLogoTask
            )

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
            
            // 更新UI
            await MainActor.run {
                self.allianceInfo = info
                self.allianceLogo = logo
                self.executorCorpInfo = (name: executorCorpInfo.name, icon: executorCorpLogo)
                self.creatorCorpInfo = (name: creatorCorpInfo.name, icon: creatorCorpLogo)
                self.creatorInfo = (name: creatorName, icon: creatorIcon)
            }

        } catch {
            Logger.error("加载联盟详细信息失败: \(error)")
            self.error = error
        }

        isLoading = false
        Logger.info("联盟详细信息加载完成")
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
}
