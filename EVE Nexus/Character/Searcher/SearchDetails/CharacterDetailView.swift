import SwiftUI

// 移除HTML标签的扩展
fileprivate extension String {
    func removeHTMLTags() -> String {
        // 移除所有HTML标签
        let text = self.replacingOccurrences(
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
    @State private var selectedTab = 0 // 添加选项卡状态
    
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
                                .lineLimit(1)
                            
                            // 人物头衔
                            if let title = characterInfo.title, !title.isEmpty {
                                Text(title.removeHTMLTags())
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .padding(.top, 2)
                            } else {
                                Text("[No title]")
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
                        .frame(height: 96) // 与头像等高
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
                            allianceInfo: allianceInfo
                        )
                    } else if selectedTab == 1 {
                        Text("雇佣记录将在这里显示")
                            .foregroundColor(.secondary)
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
        isLoading = true
        error = nil
        
        do {
            // 并发加载所有需要的数据
            async let characterInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(characterId: characterId, forceRefresh: true)
            async let portraitTask = CharacterAPI.shared.fetchCharacterPortrait(characterId: characterId)
            async let historyTask = CharacterAPI.shared.fetchEmploymentHistory(characterId: characterId)
            
            // 等待所有数据加载完成
            let (info, portrait, history) = try await (characterInfoTask, portraitTask, historyTask)
            
            // 更新状态
            self.characterInfo = info
            self.portrait = portrait
            self.employmentHistory = history
            
            // 加载军团信息
            if let corpInfo = try? await CorporationAPI.shared.fetchCorporationInfo(corporationId: info.corporation_id) {
                let corpIcon = try? await CorporationAPI.shared.fetchCorporationLogo(corporationId: info.corporation_id)
                self.corporationInfo = (name: corpInfo.name, icon: corpIcon)
            }
            
            // 加载联盟信息
            if let allianceId = info.alliance_id {
                let allianceNames = try? await UniverseAPI.shared.getNamesWithFallback(ids: [allianceId])
                if let allianceName = allianceNames?[allianceId]?.name {
                    let allianceIcon = try? await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                    self.allianceInfo = (name: allianceName, icon: allianceIcon)
                }
            }
            
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    private func formatDuration(since dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        
        guard let startDate = dateFormatter.date(from: dateString) else {
            return "Unknown duration"
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: startDate, to: Date())
        
        if let years = components.year, years > 0 {
            return "\(years) year\(years > 1 ? "s" : "")"
        } else if let months = components.month, months > 0 {
            return "\(months) month\(months > 1 ? "s" : "")"
        } else {
            return "Less than a month"
        }
    }
    
    // 声望行视图
    struct StandingRowView: View {
        let leftPortrait: (id: Int, type: MailRecipient.RecipientType)
        let rightPortrait: (id: Int, type: MailRecipient.RecipientType)
        let leftName: String
        let rightName: String
        let standing: Double?
        
        var body: some View {
            HStack {
                // 左侧头像和名称
                HStack(spacing: 8) {
                    UniversePortrait(id: leftPortrait.id, type: leftPortrait.type, size: 32)
                        .frame(width: 32, height: 32)
                        .cornerRadius(4)
                    Text(leftName)
                        .font(.system(size: 14))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // 中间声望值
                if let standing = standing {
                    Text(String(format: "%.0f", standing))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(getStandingColor(standing: standing))
                        .frame(width: 60)
                } else {
                    Text("0")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 60)
                }
                
                // 右侧头像和名称
                HStack(spacing: 8) {
                    UniversePortrait(id: rightPortrait.id, type: rightPortrait.type, size: 32)
                        .frame(width: 32, height: 32)
                        .cornerRadius(4)
                    Text(rightName)
                        .font(.system(size: 14))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 4)
        }
        
        private func getStandingColor(standing: Double) -> Color {
            switch standing {
                case 10.0:
                    return Color.blue  // 深蓝
                case 5.0..<10.0:
                    return Color(red: 0.3, green: 0.7, blue: 1.0)  // 浅蓝
                case 0.1..<5.0:
                    return Color(red: 0.3, green: 0.7, blue: 1.0)  // 浅蓝
                case 0.0:
                    return Color.secondary  // 次要颜色
                case (-5.0)..<0.0:
                    return Color(red: 1.0, green: 0.5, blue: 0.0)  // 橙红
                case (-10.0)...(-5.0):
                    return Color(red: 1.0, green: 0.5, blue: 0.0)  // 橙红
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
        @State private var personalStandings: [Int: Double] = [:]
        @State private var corpStandings: [Int: Double] = [:]
        @State private var allianceStandings: [Int: Double] = [:]
        @State private var isLoading = true
        
        var body: some View {
            VStack(spacing: 16) {
                if isLoading {
                    ProgressView()
                } else if let targetCharacter = targetCharacter {
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
                                leftName: corporationInfo?.name ?? "[Unknown]",
                                rightName: targetCharacter.name,
                                standing: corpStandings[characterId]
                            )
                        }
                        
                        // 我联盟对目标角色
                        if let allianceId = character.allianceId {
                            StandingRowView(
                                leftPortrait: (id: allianceId, type: .alliance),
                                rightPortrait: (id: characterId, type: .character),
                                leftName: allianceInfo?.name ?? "[Unknown]",
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
                            rightPortrait: (id: targetCharacter.corporation_id, type: .corporation),
                            leftName: character.CharacterName,
                            rightName: corporationInfo?.name ?? "[Unknown]",
                            standing: personalStandings[targetCharacter.corporation_id]
                        )
                        
                        // 我军团对目标军团
                        if let corpId = character.corporationId {
                            StandingRowView(
                                leftPortrait: (id: corpId, type: .corporation),
                                rightPortrait: (id: targetCharacter.corporation_id, type: .corporation),
                                leftName: corporationInfo?.name ?? "[Unknown]",
                                rightName: corporationInfo?.name ?? "[Unknown]",
                                standing: corpStandings[targetCharacter.corporation_id]
                            )
                        }
                        
                        // 我联盟对目标军团
                        if let allianceId = character.allianceId {
                            StandingRowView(
                                leftPortrait: (id: allianceId, type: .alliance),
                                rightPortrait: (id: targetCharacter.corporation_id, type: .corporation),
                                leftName: allianceInfo?.name ?? "[Unknown]",
                                rightName: corporationInfo?.name ?? "[Unknown]",
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
                                rightName: allianceInfo?.name ?? "[Unknown]",
                                standing: personalStandings[targetAllianceId]
                            )
                            
                            // 我军团对目标联盟
                            if let corpId = character.corporationId {
                                StandingRowView(
                                    leftPortrait: (id: corpId, type: .corporation),
                                    rightPortrait: (id: targetAllianceId, type: .alliance),
                                    leftName: corporationInfo?.name ?? "[Unknown]",
                                    rightName: allianceInfo?.name ?? "[Unknown]",
                                    standing: corpStandings[targetAllianceId]
                                )
                            }
                            
                            // 我联盟对目标联盟
                            if let allianceId = character.allianceId {
                                StandingRowView(
                                    leftPortrait: (id: allianceId, type: .alliance),
                                    rightPortrait: (id: targetAllianceId, type: .alliance),
                                    leftName: allianceInfo?.name ?? "[Unknown]",
                                    rightName: allianceInfo?.name ?? "[Unknown]",
                                    standing: allianceStandings[targetAllianceId]
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .task {
                await loadStandings()
            }
        }
        
        private func loadStandings() async {
            isLoading = true
            
            // 加载个人声望
            if let contacts = try? await GetCharContacts.shared.fetchContacts(characterId: character.CharacterID) {
                for contact in contacts {
                    // 如果是负面声望，直接覆盖
                    if contact.standing < 0 {
                        personalStandings[contact.contact_id] = contact.standing
                    } else {
                        // 如果是正面声望，且没有已存在的负面声望，才设置
                        if personalStandings[contact.contact_id] == nil || personalStandings[contact.contact_id]! >= 0 {
                            personalStandings[contact.contact_id] = contact.standing
                        }
                    }
                }
            }
            
            // 加载军团声望
            if let corpId = character.corporationId,
               let contacts = try? await GetCorpContacts.shared.fetchContacts(characterId: character.CharacterID, corporationId: corpId) {
                for contact in contacts {
                    // 如果是负面声望，直接覆盖
                    if contact.standing < 0 {
                        corpStandings[contact.contact_id] = contact.standing
                    } else {
                        // 如果是正面声望，且没有已存在的负面声望，才设置
                        if corpStandings[contact.contact_id] == nil || corpStandings[contact.contact_id]! >= 0 {
                            corpStandings[contact.contact_id] = contact.standing
                        }
                    }
                }
            }
            
            // 加载联盟声望
            if let allianceId = character.allianceId,
               let contacts = try? await GetAllianceContacts.shared.fetchContacts(characterId: character.CharacterID, allianceId: allianceId) {
                for contact in contacts {
                    // 如果是负面声望，直接覆盖
                    if contact.standing < 0 {
                        allianceStandings[contact.contact_id] = contact.standing
                    } else {
                        // 如果是正面声望，且没有已存在的负面声望，才设置
                        if allianceStandings[contact.contact_id] == nil || allianceStandings[contact.contact_id]! >= 0 {
                            allianceStandings[contact.contact_id] = contact.standing
                        }
                    }
                }
            }
            
            // 处理声望继承
            if let targetCharacter = targetCharacter {
                // 如果对军团有声望设置，继承给角色
                if let corpStanding = personalStandings[targetCharacter.corporation_id] {
                    if corpStanding < 0 || personalStandings[characterId] == nil {
                        personalStandings[characterId] = corpStanding
                    }
                }
                
                // 如果对联盟有声望设置，继承给角色和军团
                if let allianceId = targetCharacter.alliance_id,
                   let allianceStanding = personalStandings[allianceId] {
                    if allianceStanding < 0 {
                        personalStandings[characterId] = allianceStanding
                        personalStandings[targetCharacter.corporation_id] = allianceStanding
                    } else {
                        if personalStandings[characterId] == nil {
                            personalStandings[characterId] = allianceStanding
                        }
                        if personalStandings[targetCharacter.corporation_id] == nil {
                            personalStandings[targetCharacter.corporation_id] = allianceStanding
                        }
                    }
                }
            }
            
            isLoading = false
        }
    }
} 
