import SwiftUI

// 全局头像缓存
actor CharacterPortraitCache {
    static let shared = CharacterPortraitCache()
    private var cache: [String: UIImage] = [:]
    
    private init() {}
    
    func image(for characterId: Int, size: Int) -> UIImage? {
        return cache["\(characterId)_\(size)"]
    }
    
    func setImage(_ image: UIImage, for characterId: Int, size: Int) {
        cache["\(characterId)_\(size)"] = image
    }
}

@MainActor
class CharacterPortraitViewModel: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var isCorporation = false
    
    let characterId: Int
    let size: Int
    
    init(characterId: Int, size: Int) {
        self.characterId = characterId
        self.size = size
    }
    
    func loadImage() async {
        // 先检查缓存
        if let cachedImage = await CharacterPortraitCache.shared.image(for: characterId, size: size) {
            self.image = cachedImage
            return
        }
        
        // 如果缓存中没有，则开始加载
        isLoading = true
        defer { isLoading = false }
        
        // 先尝试获取角色头像
        do {
            let portrait = try await CharacterAPI.shared.fetchCharacterPortrait(characterId: characterId, size: size)
            // 保存到缓存
            await CharacterPortraitCache.shared.setImage(portrait, for: characterId, size: size)
            self.image = portrait
            Logger.info("成功获取并缓存角色头像 - 角色ID: \(characterId), 大小: \(size), 数据大小: \(portrait.jpegData(compressionQuality: 1.0)?.count ?? 0) bytes")
            return
        } catch {
            Logger.info("获取角色头像失败，尝试获取军团头像 - ID: \(characterId)")
            // 如果获取角色头像失败，尝试获取军团头像
            do {
                let corpLogo = try await CorporationAPI.shared.fetchCorporationLogo(corporationId: characterId, size: size)
                // 保存到缓存
                await CharacterPortraitCache.shared.setImage(corpLogo, for: characterId, size: size)
                self.image = corpLogo
                self.isCorporation = true
                Logger.info("成功获取并缓存军团头像 - 军团ID: \(characterId), 大小: \(size)")
            } catch {
                Logger.error("加载头像失败（角色和军团都失败）: \(error)")
            }
        }
    }
}

struct CharacterPortrait: View {
    let characterId: Int
    let size: CGFloat
    let cornerRadius: CGFloat
    @StateObject private var viewModel: CharacterPortraitViewModel
    
    init(characterId: Int, size: CGFloat, cornerRadius: CGFloat = 6) {
        self.characterId = characterId
        self.size = size
        self.cornerRadius = cornerRadius
        // 始终使用64尺寸的图片
        self._viewModel = StateObject(wrappedValue: CharacterPortraitViewModel(characterId: characterId, size: 64))
    }
    
    var body: some View {
        ZStack {
            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        viewModel.isCorporation ?
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        : nil
                    )
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .foregroundColor(.gray)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
        .task {
            await viewModel.loadImage()
        }
    }
}

enum MailDatabaseError: Error {
    case fetchError(String)
}

class CharacterMailListViewModel: ObservableObject {
    @Published var mails: [EVEMail] = []
    @Published var senderNames: [Int: String] = [:]
    @Published var senderCategories: [Int: String] = [:]
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: Error?
    @Published var isRefreshing = false
    @Published var hasMoreMails = true
    
    private let mailAPI = CharacterMailAPI.shared
    private let characterAPI = CharacterAPI.shared
    
    @MainActor
    func fetchMails(characterId: Int, labelId: Int? = nil, forceRefresh: Bool = false) async {
        if forceRefresh {
            isRefreshing = true
        } else {
            isLoading = true
        }
        
        defer {
            isLoading = false
            isRefreshing = false
        }
        
        do {
            // 获取一批邮件
            let newMails = try await mailAPI.fetchLatestMails(characterId: characterId, labelId: labelId)
            self.mails = newMails
            await loadSenderNames(for: newMails)
            // 只要获取到了邮件，就假设可能还有更多
            hasMoreMails = !newMails.isEmpty
            
        } catch {
            Logger.error("获取邮件失败: \(error)")
            self.error = error
        }
    }
    
    @MainActor
    func loadMoreMails(characterId: Int, labelId: Int? = nil) async {
        guard !isLoadingMore, hasMoreMails, let lastMail = mails.last else { return }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            // 使用最后一封邮件的ID获取更老的邮件
            let olderMails = try await mailAPI.fetchLatestMails(
                characterId: characterId,
                labelId: labelId,
                lastMailId: lastMail.mail_id
            )
            
            if !olderMails.isEmpty {
                self.mails.append(contentsOf: olderMails)
                await loadSenderNames(for: olderMails)
                // 只要获取到了邮件，就假设可能还有更多
                hasMoreMails = true
                Logger.info("成功加载 \(olderMails.count) 封更老的邮件")
            } else {
                // 只有当真的获取不到邮件时，才标记没有更多
                hasMoreMails = false
                Logger.info("没有更多邮件了")
            }
            
        } catch {
            Logger.error("加载更多邮件失败: \(error)")
            self.error = error
        }
    }
    
    func getSenderCategory(_ id: Int) -> String {
        return senderCategories[id] ?? "character"
    }
    
    private func loadSenderNames(for mails: [EVEMail]) async {
        // 收集所有发件人ID并去重
        let senderIds = Set(mails.map { $0.from })
        
        do {
            // 先尝试从数据库获取已有的名称信息
            let existingNames = try await UniverseAPI.shared.getNamesFromDatabase(ids: Array(senderIds))
            
            // 更新已有的名称信息
            await MainActor.run {
                for (id, info) in existingNames {
                    self.senderNames[id] = info.name
                    self.senderCategories[id] = info.category
                }
            }
            
            // 找出需要从API获取的ID
            let missingIds = senderIds.filter { !existingNames.keys.contains($0) }
            if !missingIds.isEmpty {
                // 从API获取并保存缺失的名称信息
                _ = try await UniverseAPI.shared.fetchAndSaveNames(ids: Array(missingIds))
                
                // 从数据库获取新保存的名称信息
                let newNames = try await UniverseAPI.shared.getNamesFromDatabase(ids: Array(missingIds))
                
                // 更新新获取的名称信息
                await MainActor.run {
                    for (id, info) in newNames {
                        self.senderNames[id] = info.name
                        self.senderCategories[id] = info.category
                    }
                }
            }
            
            Logger.debug("成功获取 \(senderIds.count) 个发件人的信息")
        } catch {
            Logger.error("获取发件人信息失败: \(error)")
        }
    }
    
    func getSenderName(_ characterId: Int) -> String {
        return senderNames[characterId] ?? "未知发件人"
    }
}

struct CharacterMailListView: View {
    let characterId: Int
    let labelId: Int?
    let title: String
    
    @StateObject private var viewModel = CharacterMailListViewModel()
    
    init(characterId: Int, labelId: Int? = nil, title: String? = nil) {
        self.characterId = characterId
        self.labelId = labelId
        self.title = title ?? "全部邮件"
    }
    
    var body: some View {
        if viewModel.isLoading && viewModel.mails.isEmpty {
            ProgressView()
                .navigationTitle(title)
                .task {
                    await viewModel.fetchMails(characterId: characterId, labelId: labelId)
                }
        } else {
            List {
                ForEach(viewModel.mails, id: \.mail_id) { mail in
                    NavigationLink(destination: CharacterMailDetailView(characterId: characterId, mail: mail)) {
                        HStack(spacing: 12) {
                            // 发件人头像
                            CharacterPortrait(characterId: mail.from, size: 40)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                // 发件人名称
                                Text(viewModel.getSenderName(mail.from))
                                    .font(.subheadline)
                                    .foregroundColor(mail.is_read == true ? .secondary : .primary)
                                
                                // 邮件主题
                                Text(mail.subject)
                                    .font(.headline)
                                    .foregroundColor(mail.is_read == true ? .secondary : .primary)
                                    .lineLimit(1)
                                
                                // 时间
                                Text(mail.timestamp.formatDate())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // 未读标记
                            if mail.is_read != true {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // 加载更多指示器
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .onAppear {
                        Task {
                            await viewModel.loadMoreMails(characterId: characterId, labelId: labelId)
                        }
                    }
                }
            }
            .refreshable {
                await viewModel.fetchMails(characterId: characterId, labelId: labelId, forceRefresh: true)
            }
            .navigationTitle(title)
            .task {
                await viewModel.fetchMails(characterId: characterId, labelId: labelId)
            }
        }
    }
}

// 通用头像组件
struct UniversePortrait: View {
    let id: Int
    let category: String
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundColor(.gray)
            }
        }
        .task {
            do {
                isLoading = true
                image = try await UniverseIconAPI.shared.fetchIcon(id: id, category: category)
                isLoading = false
            } catch {
                Logger.error("加载头像失败: \(error)")
                self.error = error
                isLoading = false
            }
        }
    }
}

// 日期格式化扩展
extension String {
    func formatDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let date = dateFormatter.date(from: self) else { return self }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        outputFormatter.timeZone = TimeZone.current
        outputFormatter.locale = Locale.current
        
        return outputFormatter.string(from: date)
    }
} 
