import SwiftUI

struct CharacterPortrait: View {
    let characterId: Int
    let size: CGFloat
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if isLoading {
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
        .onAppear {
            Task {
                await loadImage()
            }
        }
    }
    
    private func loadImage() async {
        guard image == nil else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            let portrait = try await CharacterAPI.shared.fetchCharacterPortrait(characterId: characterId, size: Int(size))
            await MainActor.run {
                self.image = portrait
            }
        } catch {
            Logger.error("加载角色头像失败: \(error)")
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
                    guard let mailId = row["mail_id"] as? Int,
                          let fromId = row["from_id"] as? Int,
                          let isRead = row["is_read"] as? Int,
                          let subject = row["subject"] as? String,
                          let timestamp = row["timestamp"] as? String,
                          let recipientsString = row["recipients"] as? String,
                          let recipientsData = recipientsString.data(using: .utf8) else {
                        Logger.error("邮件数据格式错误: \(row)")
                        continue
                    }
                    
                    // 解析收件人数据
                    let recipients = (try? JSONDecoder().decode([EVEMailRecipient].self, from: recipientsData)) ?? []
                    
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
                // 在主线程更新UI
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