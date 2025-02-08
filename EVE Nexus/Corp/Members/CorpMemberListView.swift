import SwiftUI
import Kingfisher

struct MemberDetailInfo {
    let member: MemberTrackingInfo
    var characterInfo: CharacterPublicInfo?
    var portrait: UIImage?
    var shipName: String?
    var locationInfo: LocationInfoDetail?
}

class CorpMemberListViewModel: ObservableObject {
    @Published var members: [MemberDetailInfo] = []
    @Published var isLoading = true
    @Published var error: Error?
    private let characterId: Int
    private let databaseManager: DatabaseManager
    
    init(characterId: Int, databaseManager: DatabaseManager) {
        self.characterId = characterId
        self.databaseManager = databaseManager
    }
    
    @MainActor
    func loadMembers() async {
        isLoading = true
        error = nil
        
        do {
            // 1. 获取成员基本信息
            let memberList = try await CorpMembersAPI.shared.fetchMemberTracking(characterId: characterId)
            
            // 2. 初始化成员列表（按ID排序）
            members = memberList.sorted { $0.character_id < $1.character_id }
                .map { MemberDetailInfo(member: $0) }
            
            // 3. 异步加载每个成员的详细信息
            await withTaskGroup(of: Void.self) { group in
                for index in members.indices {
                    group.addTask { [weak self] in
                        await self?.loadMemberDetails(at: index)
                    }
                }
            }
            
        } catch {
            self.error = error
            Logger.error("加载军团成员列表失败: \(error)")
        }
        
        isLoading = false
    }
    
    @MainActor
    private func loadMemberDetails(at index: Int) async {
        guard index < members.count else { return }
        let member = members[index]
        
        // 创建位置信息加载器
        let locationLoader = LocationInfoLoader(
            databaseManager: databaseManager,
            characterId: Int64(characterId)
        )
        
        async let characterInfoTask = CharacterAPI.shared.fetchCharacterPublicInfo(
            characterId: member.member.character_id
        )
        async let portraitTask = CharacterAPI.shared.fetchCharacterPortrait(
            characterId: member.member.character_id,
            size: 32
        )
        
        // 加载位置信息
        if let locationId = member.member.location_id {
            let locationInfo = await locationLoader.loadLocationInfo(
                locationIds: Set([Int64(locationId)])
            )[Int64(locationId)]
            
            if let locationInfo = locationInfo {
                members[index].locationInfo = locationInfo
            }
        }
        
        // 加载飞船信息
        if let shipTypeId = member.member.ship_type_id {
            let query = "SELECT name FROM types WHERE type_id = ?"
            if case .success(let rows) = databaseManager.executeQuery(query, parameters: [shipTypeId]),
               let row = rows.first,
               let shipName = row["name"] as? String {
                members[index].shipName = shipName
            }
        }
        
        // 等待并更新角色信息和头像
        do {
            let (characterInfo, portrait) = try await (characterInfoTask, portraitTask)
            members[index].characterInfo = characterInfo
            members[index].portrait = portrait
        } catch {
            Logger.error("加载成员详细信息失败 - 角色ID: \(member.member.character_id), 错误: \(error)")
        }
    }
}

struct CorpMemberListView: View {
    let characterId: Int
    @StateObject private var viewModel: CorpMemberListViewModel
    @State private var showingFavorites = false
    
    init(characterId: Int) {
        self.characterId = characterId
        self._viewModel = StateObject(wrappedValue: CorpMemberListViewModel(
            characterId: characterId,
            databaseManager: DatabaseManager.shared
        ))
    }
    
    var body: some View {
        List {
            // 特别关注部分
            if !viewModel.isLoading && viewModel.error == nil {
                Section {
                    Button(action: {
                        showingFavorites.toggle()
                    }) {
                        Text(NSLocalizedString("Main_Corporation_Members_Favorites", comment: ""))
                    }
                }
            }
            
            // 成员列表部分
            Section {
                if viewModel.isLoading {
                    ProgressView(NSLocalizedString("Main_Corporation_Members_Loading", comment: ""))
                } else if let error = viewModel.error {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                } else {
                    ForEach(viewModel.members, id: \.member.character_id) { member in
                        MemberRowView(member: member)
                    }
                }
            } header: {
                if !viewModel.isLoading && viewModel.error == nil {
                    Text(String(format: NSLocalizedString("Main_Corporation_Members_Total", comment: ""), viewModel.members.count))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Corporation_Members_Title", comment: ""))
        .refreshable {
            await viewModel.loadMembers()
        }
        .task {
            await viewModel.loadMembers()
        }
    }
}

struct MemberRowView: View {
    let member: MemberDetailInfo
    
    var body: some View {
        HStack(spacing: 12) {
            // 头像
            if let portrait = member.portrait {
                Image(uiImage: portrait)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.gray)
            }
            
            // 成员信息
            VStack(alignment: .leading, spacing: 2) {
                // 名称和称号
                HStack {
                    Text(member.characterInfo?.name ?? String(member.member.character_id))
                        .font(.headline)
                    if let title = member.characterInfo?.title {
                        Text(title)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                // 飞船和位置信息
                if let shipName = member.shipName {
                    Text(shipName)
                        .font(.caption)
                }
                
                if let location = member.locationInfo {
                    HStack {
                        Text(String(format: "%.1f", location.security))
                            .font(.caption)
                            .foregroundColor(securityColor(location.security))
                        Text(location.solarSystemName)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func securityColor(_ security: Double) -> Color {
        if security >= 0.5 {
            return .green
        } else if security > 0.0 {
            return .orange
        } else {
            return .red
        }
    }
}

#Preview {
    CorpMemberListView(characterId: 90000000)
} 
