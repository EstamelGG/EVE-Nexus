import SwiftUI

@MainActor
class UniversePortraitViewModel: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var error: Error?
    
    let id: Int
    let type: MailRecipient.RecipientType
    let size: Int
    
    init(id: Int, type: MailRecipient.RecipientType, size: Int) {
        self.id = id
        self.type = type
        self.size = size
    }
    
    func loadImage() async {
        // 先检查缓存
        if let cachedImage = await CharacterPortraitCache.shared.image(for: id, size: size) {
            self.image = cachedImage
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let portrait: UIImage
            switch type {
            case .character:
                portrait = try await CharacterAPI.shared.fetchCharacterPortrait(characterId: id, size: size, catchImage: false)
            case .corporation:
                portrait = try await CorporationAPI.shared.fetchCorporationLogo(corporationId: id, size: size)
            case .alliance:
                portrait = try await UniverseIconAPI.shared.fetchIcon(id: id, category: "alliance")
            case .mailingList:
                throw NetworkError.invalidURL // 邮件列表不需要头像
            }
            
            // 保存到缓存
            await CharacterPortraitCache.shared.setImage(portrait, for: id, size: size)
            self.image = portrait
            Logger.debug("成功加载\(type.rawValue)头像 - ID: \(id)")
            
        } catch {
            Logger.error("加载\(type.rawValue)头像失败 - ID: \(id), 错误: \(error)")
            self.error = error
        }
    }
}

struct UniversePortrait: View {
    let id: Int
    let type: MailRecipient.RecipientType
    let size: CGFloat
    let displaySize: CGFloat
    let cornerRadius: CGFloat
    
    @StateObject private var viewModel: UniversePortraitViewModel
    
    init(id: Int, type: MailRecipient.RecipientType, size: CGFloat, displaySize: CGFloat? = nil, cornerRadius: CGFloat = 6) {
        self.id = id
        self.type = type
        self.size = size
        self.displaySize = displaySize ?? size
        self.cornerRadius = cornerRadius
        self._viewModel = StateObject(wrappedValue: UniversePortraitViewModel(id: id, type: type, size: Int(size)))
    }
    
    var body: some View {
        ZStack {
            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: displaySize, height: displaySize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(width: displaySize, height: displaySize)
            } else {
                // 根据类型显示不同的占位图标
                if type == .mailingList {
                    Image("grouplist")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displaySize, height: displaySize)
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: type == .character ? "person.circle.fill" :
                          type == .corporation ? "building.2.fill" : "globe")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displaySize, height: displaySize)
                        .foregroundColor(.gray)
                }
            }
        }
        .task {
            await viewModel.loadImage()
        }
    }
} 
