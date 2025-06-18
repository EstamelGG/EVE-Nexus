import SwiftUI

@MainActor
class UniversePortraitLoader: ObservableObject {
    static let shared = UniversePortraitLoader()
    
    @Published private(set) var portraits: [String: UIImage] = [:]
    private var loadingTasks: [String: Task<Void, Never>] = [:]
    
    private init() {}
    
    func loadPortrait(for id: Int, type: MailRecipient.RecipientType, size: Int) {
        let key = "\(type.rawValue)_\(id)_\(size)"
        
        // 如果已经在加载中或已加载完成，直接返回
        if loadingTasks[key] != nil || portraits[key] != nil {
            return
        }
        
        // 创建新的加载任务
        let task = Task {
            do {
                let portrait: UIImage
                switch type {
                case .character:
                    portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                        characterId: id, size: size, catchImage: false
                    )
                case .corporation:
                    portrait = try await CorporationAPI.shared.fetchCorporationLogo(
                        corporationId: id, size: size
                    )
                case .alliance:
                    portrait = try await AllianceAPI.shared.fetchAllianceLogo(
                        allianceID: id
                    )
                case .mailingList:
                    throw NetworkError.invalidURL  // 邮件列表不需要头像
                }
                
                await MainActor.run {
                    self.portraits[key] = portrait
                }
                
                Logger.debug("成功加载\(type.rawValue)头像 - ID: \(id)")
            } catch {
                Logger.error("加载\(type.rawValue)头像失败 - ID: \(id), 错误: \(error)")
            }
        }
        
        loadingTasks[key] = task
    }
    
    func getPortrait(for id: Int, type: MailRecipient.RecipientType, size: Int) -> UIImage? {
        return portraits["\(type.rawValue)_\(id)_\(size)"]
    }
}

struct UniversePortrait: View {
    let id: Int
    let type: MailRecipient.RecipientType
    let size: CGFloat
    let displaySize: CGFloat
    let cornerRadius: CGFloat
    
    @StateObject private var portraitLoader = UniversePortraitLoader.shared
    
    init(
        id: Int, type: MailRecipient.RecipientType, size: CGFloat, displaySize: CGFloat? = nil,
        cornerRadius: CGFloat = 6
    ) {
        self.id = id
        self.type = type
        self.size = size
        self.displaySize = displaySize ?? size
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        ZStack {
            if let image = portraitLoader.getPortrait(for: id, type: type, size: Int(size)) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: displaySize, height: displaySize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                // 根据类型显示不同的占位图标
                if type == .mailingList {
                    Image("grouplist")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displaySize, height: displaySize)
                        .foregroundColor(.gray)
                } else {
                    Image(
                        systemName: type == .character
                            ? "person.circle.fill"
                            : type == .corporation ? "building.2.fill" : "globe"
                    )
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displaySize, height: displaySize)
                    .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            portraitLoader.loadPortrait(for: id, type: type, size: Int(size))
        }
    }
}
