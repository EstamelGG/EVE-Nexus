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
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding()
            } else if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if let characterInfo = characterInfo {
                VStack(spacing: 16) {
                    // 基本信息部分
                    HStack(alignment: .top, spacing: 16) {
                        // 左侧头像
                        if let portrait = portrait {
                            Image(uiImage: portrait)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 128, height: 128)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 128, height: 128)
                        }
                        
                        // 右侧信息
                        VStack(alignment: .leading, spacing: 8) {
                            // 人物名称
                            Text(characterInfo.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            // 人物头衔（暂时留空，后续可以添加）
                            Text("Character")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // 军团信息
                            if let corpInfo = corporationInfo {
                                HStack(spacing: 8) {
                                    if let icon = corpInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(corpInfo.name)
                                            .font(.subheadline)
                                        if let firstEmployment = employmentHistory.first {
                                            Text(formatDuration(since: firstEmployment.start_date))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                            
                            // 联盟信息
                            if let allianceInfo = allianceInfo {
                                HStack(spacing: 8) {
                                    if let icon = allianceInfo.icon {
                                        Image(uiImage: icon)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                    }
                                    Text(allianceInfo.name)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.primary.opacity(0.1), radius: 5, x: 0, y: 2)
                }
                .padding()
            }
        }
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
            async let characterInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(characterId: characterId)
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
