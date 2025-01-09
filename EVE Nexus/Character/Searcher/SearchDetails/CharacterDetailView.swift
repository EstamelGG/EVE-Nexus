import SwiftUI

struct CharacterDetailView: View {
    let characterId: Int
    @State private var portrait: UIImage?
    @State private var characterInfo: CharacterPublicInfo?
    @State private var employmentHistory: [CharacterEmploymentHistory] = []
    @State private var corporationInfo: (name: String, icon: UIImage?)?
    @State private var allianceInfo: (name: String, icon: UIImage?)?
    @State private var isLoading = true
    @State private var error: Error?
    
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
                        VStack(alignment: .leading, spacing: 8) {
                            // 人物名称
                            Text(characterInfo.name)
                                .font(.title3)
                                .bold()
                            
                            // 人物头衔
                            if let title = characterInfo.title, !title.isEmpty {
                                Text(title)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            // 军团信息
                            if let corpInfo = corporationInfo {
                                HStack(spacing: 8) {
                                    if let icon = corpInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(corpInfo.name)
                                        .font(.subheadline)
                                }
                            }
                            
                            // 联盟信息
                            if let allianceInfo = allianceInfo {
                                HStack(spacing: 8) {
                                    if let icon = allianceInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Text(allianceInfo.name)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
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
} 
