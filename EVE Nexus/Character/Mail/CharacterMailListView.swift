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
        
        do {
            let portrait = try await CharacterAPI.shared.fetchCharacterPortrait(characterId: characterId, size: size)
            // 保存到缓存
            await CharacterPortraitCache.shared.setImage(portrait, for: characterId, size: size)
            self.image = portrait
            Logger.info("成功获取并缓存角色头像 - 角色ID: \(characterId), 大小: \(size), 数据大小: \(portrait.jpegData(compressionQuality: 1.0)?.count ?? 0) bytes")
        } catch {
            Logger.error("加载角色头像失败: \(error)")
        }
    }
}

struct CharacterPortrait: View {
    let characterId: Int
    let size: CGFloat
    @StateObject private var viewModel: CharacterPortraitViewModel
    
    init(characterId: Int, size: CGFloat) {
        self.characterId = characterId
        self.size = size
        self._viewModel = StateObject(wrappedValue: CharacterPortraitViewModel(characterId: characterId, size: Int(size)))
    }
    
    var body: some View {
        ZStack {
            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .foregroundColor(.gray)
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
    
    private let mailAPI = CharacterMailAPI.shared
    private let characterAPI = CharacterAPI.shared
    
    @MainActor
    func fetchMails(characterId: Int) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            Logger.info("开始获取邮件 - 角色ID: \(characterId)")
            // 获取邮件
            try await mailAPI.fetchMails(characterId: characterId)
            
            // 从数据库读取邮件
            let query = """
                SELECT * FROM mailbox 
                WHERE character_id = ? 
                ORDER BY timestamp DESC
            """
            
            let result = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId])
            switch result {
            case .success(let rows):
                Logger.info("从数据库读取到 \(rows.count) 条邮件记录")
                var fetchedMails: [EVEMail] = []
                var newSenderNames: [Int: String] = [:]
                
                for row in rows {
                    Logger.debug("处理邮件记录: \(row)")
                    
                    // 转换数据类型
                    let mailId = (row["mail_id"] as? Int64).map(Int.init) ?? (row["mail_id"] as? Int) ?? 0
                    let fromId = (row["from_id"] as? Int64).map(Int.init) ?? (row["from_id"] as? Int) ?? 0
                    let isRead = (row["is_read"] as? Int64).map(Int.init) ?? (row["is_read"] as? Int) ?? 0
                    
                    guard mailId > 0,
                          fromId > 0,
                          let subject = row["subject"] as? String,
                          let timestamp = row["timestamp"] as? String,
                          let recipientsString = row["recipients"] as? String,
                          let recipientsData = recipientsString.data(using: .utf8) else {
                        Logger.error("邮件数据格式错误: \(row)")
                        continue
                    }
                    
                    // 解析收件人数据
                    guard let recipients = try? JSONDecoder().decode([EVEMailRecipient].self, from: recipientsData) else {
                        Logger.error("解析收件人数据失败: \(recipientsString)")
                        continue
                    }
                    
                    let mail = EVEMail(
                        from: fromId,
                        is_read: isRead == 1,
                        labels: [], // 暂时不处理标签
                        mail_id: mailId,
                        recipients: recipients,
                        subject: subject,
                        timestamp: timestamp
                    )
                    fetchedMails.append(mail)
                    Logger.debug("成功解析邮件: ID=\(mailId), 主题=\(subject)")
                    
                    // 获取发件人名称
                    if senderNames[fromId] == nil {
                        do {
                            let info = try await characterAPI.fetchCharacterPublicInfo(characterId: fromId)
                            newSenderNames[fromId] = info.name
                            Logger.debug("获取发件人信息成功: ID=\(fromId), 名称=\(info.name)")
                        } catch {
                            Logger.error("获取角色信息失败: \(error)")
                        }
                    }
                }
                
                Logger.info("成功处理 \(fetchedMails.count) 封邮件")
                self.mails = fetchedMails
                self.senderNames.merge(newSenderNames) { _, new in new }
                Logger.info("UI更新完成，当前显示 \(self.mails.count) 封邮件")
                
            case .error(let error):
                Logger.error("数据库查询失败: \(error)")
                self.error = MailDatabaseError.fetchError(error)
            }
        } catch {
            Logger.error("获取邮件过程失败: \(error)")
            self.error = error
        }
    }
    
    func getSenderName(_ characterId: Int) -> String {
        return senderNames[characterId] ?? "未知发件人"
    }
}

struct CharacterMailListView: View {
    let characterId: Int
    @StateObject private var viewModel = CharacterMailListViewModel()
    
    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView()
            } else if let error = viewModel.error {
                VStack {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                    Text("错误详情：\(String(describing: error))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else if viewModel.mails.isEmpty {
                Text("没有邮件")
                    .foregroundColor(.gray)
            } else {
                List(viewModel.mails, id: \.mail_id) { mail in
                    HStack(alignment: .top, spacing: 12) {
                        // 发件人头像
                        CharacterPortrait(characterId: mail.from, size: 64)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            // 邮件主题
                            Text(mail.subject)
                                .font(.headline)
                                .lineLimit(1)
                            
                            // 发件人名称
                            Text(viewModel.getSenderName(mail.from))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            // 时间戳
                            Text(mail.timestamp.formatDate())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // 未读标记
                        if let isRead = mail.is_read, !isRead {
                            Circle()
                                .fill(.blue)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationBarTitle("全部邮件(\(viewModel.mails.count))", displayMode: .inline)
        .onAppear {
            Logger.info("CharacterMailListView appeared")
            Task {
                await viewModel.fetchMails(characterId: characterId)
            }
        }
        .refreshable {
            Logger.info("用户触发刷新")
            await viewModel.fetchMails(characterId: characterId)
        }
    }
}

// 日期格式化扩展
extension String {
    func formatDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        
        guard let date = dateFormatter.date(from: self) else { return self }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        outputFormatter.timeZone = TimeZone.current
        
        return outputFormatter.string(from: date)
    }
} 
