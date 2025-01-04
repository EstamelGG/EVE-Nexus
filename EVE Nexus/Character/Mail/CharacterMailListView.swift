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
    @Published var isLoading = false
    @Published var error: Error?
    @Published var isRefreshing = false
    
    private let mailAPI = CharacterMailAPI.shared
    private let characterAPI = CharacterAPI.shared
    
    @MainActor
    func fetchMails(characterId: Int, labelId: Int? = nil, forceRefresh: Bool = false) async {
        if !forceRefresh {
            isLoading = true
        } else {
            isRefreshing = true
        }
        
        defer {
            isLoading = false
            isRefreshing = false
        }
        
        do {
            // 1. 先从数据库加载
            if !forceRefresh {
                Logger.info("从数据库加载邮件 - 角色ID: \(characterId), 标签ID: \(labelId ?? 0)")
                let localMails = try await mailAPI.loadMailsFromDatabase(characterId: characterId, labelId: labelId)
                if !localMails.isEmpty {
                    self.mails = localMails
                    await loadSenderNames(for: localMails)
                }
            }
            
            // 2. 从网络获取最新数据
            Logger.info("检查新邮件 - 角色ID: \(characterId), 标签ID: \(labelId ?? 0)")
            let hasNewMails = try await mailAPI.fetchLatestMails(characterId: characterId, labelId: labelId)
            
            // 3. 如果有新邮件，重新从数据库加载
            if hasNewMails || forceRefresh {
                Logger.info("发现新邮件，重新加载")
                let updatedMails = try await mailAPI.loadMailsFromDatabase(characterId: characterId, labelId: labelId)
                self.mails = updatedMails
                await loadSenderNames(for: updatedMails)
            }
            
        } catch {
            Logger.error("获取邮件过程失败: \(error)")
            self.error = error
        }
    }
    
    private func loadSenderNames(for mails: [EVEMail]) async {
        var newSenderNames: [Int: String] = [:]
        
        for mail in mails {
            if senderNames[mail.from] == nil {
                do {
                    let info = try await characterAPI.fetchCharacterPublicInfo(characterId: mail.from)
                    newSenderNames[mail.from] = info.name
                    Logger.debug("获取发件人信息成功: ID=\(mail.from), 名称=\(info.name)")
                } catch let error as NetworkError {
                    // 如果是404错误（角色不存在），尝试获取军团信息
                    if case .httpError(404, let responseBody) = error,
                       let body = responseBody,
                       body.contains("Character not found") {
                        do {
                            let corpInfo = try await CorporationAPI.shared.fetchCorporationInfo(corporationId: mail.from)
                            newSenderNames[mail.from] = corpInfo.name
                            Logger.debug("获取军团信息成功: ID=\(mail.from), 名称=\(corpInfo.name)")
                        } catch {
                            Logger.error("获取军团信息失败: \(error)")
                        }
                    } else {
                        Logger.error("获取角色信息失败: \(error)")
                    }
                } catch {
                    Logger.error("获取发件人信息失败: \(error)")
                }
            }
        }
        
        if !newSenderNames.isEmpty {
            await MainActor.run {
                self.senderNames.merge(newSenderNames) { _, new in new }
            }
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
        ZStack {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.error {
                VStack {
                    if error is CancellationError {
                        // 忽略取消错误的显示
                        EmptyView()
                    } else {
                        Text(error.localizedDescription)
                            .foregroundColor(.red)
                        Text("错误详情：\(String(describing: error))")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            } else if viewModel.mails.isEmpty {
                Text("没有邮件")
                    .foregroundColor(.gray)
            } else {
                List(viewModel.mails, id: \.mail_id) { mail in
                    HStack(alignment: .center, spacing: 12) {
                        // 发件人头像
                        CharacterPortrait(characterId: mail.from, size: 48)
                        
                        // 右侧内容
                        VStack(alignment: .leading, spacing: 2) {
                            // 第一行：主题
                            Text(mail.subject)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(mail.is_read == true ? .secondary : .primary)
                                .lineLimit(1)
                            
                            // 第二行：发件人
                            HStack(spacing: 4) {
                                Text("From:")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                Text(viewModel.getSenderName(mail.from))
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            
                            // 第三行：时间
                            Text(mail.timestamp.formatDate())
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // 未读标记
                        if mail.is_read != true {
                            Circle()
                                .fill(.blue)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(height: 50)
                }
            }
        }
        .navigationBarTitle("\(title)(\(viewModel.mails.count))", displayMode: .inline)
        .onAppear {
            Logger.info("CharacterMailListView appeared")
            Task {
                await viewModel.fetchMails(characterId: characterId, labelId: labelId)
            }
        }
        .refreshable {
            Logger.info("用户触发下拉刷新，强制更新数据")
            await viewModel.fetchMails(characterId: characterId, labelId: labelId, forceRefresh: true)
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
