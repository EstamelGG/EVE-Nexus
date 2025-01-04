import SwiftUI

// 完整的邮件详情数据结构
struct MailDetailData {
    let content: EVEMailContent
    let senderName: String
    let recipientNames: [Int: String]
    let processedBody: Text
}

struct CharacterMailDetailView: View {
    let characterId: Int
    let mail: EVEMail
    @StateObject private var viewModel = CharacterMailDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView()
                    .navigationBarTitleDisplayMode(.inline)
            } else if let error = viewModel.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("加载失败")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .navigationBarTitleDisplayMode(.inline)
            } else if let detail = viewModel.mailDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 主题
                        Text(detail.content.subject)
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        // 发件人和时间信息
                        HStack {
                            CharacterPortrait(characterId: detail.content.from, size: 32)
                            VStack(alignment: .leading) {
                                Text(detail.senderName)
                                    .font(.subheadline)
                                Text(mail.timestamp.formatDate())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // 收件人信息
                        if !detail.content.recipients.isEmpty {
                            Text("收件人：")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            ForEach(detail.content.recipients, id: \.recipient_id) { recipient in
                                Text(detail.recipientNames[recipient.recipient_id] ?? "未知收件人")
                                    .font(.subheadline)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        // 邮件正文
                        detail.processedBody
                            .font(.body)
                    }
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            await viewModel.loadMailContent(characterId: characterId, mailId: mail.mail_id)
        }
    }
}

@MainActor
class CharacterMailDetailViewModel: ObservableObject {
    @Published var mailDetail: MailDetailData?
    @Published var isLoading = true
    @Published var error: Error?
    
    func loadMailContent(characterId: Int, mailId: Int) async {
        isLoading = true
        error = nil
        
        do {
            // 1. 获取邮件内容
            let content = try await CharacterMailAPI.shared.fetchMailContent(characterId: characterId, mailId: mailId)
            
            // 2. 获取发件人名称（优先从数据库获取）
            var senderName = "未知发件人"
            if let nameInfo = try await UniverseAPI.shared.getNameFromDatabase(id: content.from) {
                senderName = nameInfo.name
            } else {
                // 如果数据库中没有，再从API获取
                let senderResult = try await UniverseAPI.shared.fetchAndSaveNames(ids: [content.from])
                if senderResult > 0 {
                    if let nameInfo = try await UniverseAPI.shared.getNameFromDatabase(id: content.from) {
                        senderName = nameInfo.name
                    }
                }
            }
            
            // 3. 获取所有收件人名称
            var recipientNames: [Int: String] = [:]
            for recipient in content.recipients {
                switch recipient.recipient_type {
                case "mailing_list":
                    if let listName = try await CharacterMailAPI.shared.loadMailListsFromDatabase(characterId: characterId)
                        .first(where: { $0.mailing_list_id == recipient.recipient_id })?.name {
                        recipientNames[recipient.recipient_id] = "[\(listName)]"
                    } else {
                        recipientNames[recipient.recipient_id] = "[邮件列表#\(recipient.recipient_id)]"
                    }
                case "character", "corporation", "alliance":
                    // 优先从数据库获取名称
                    if let nameInfo = try await UniverseAPI.shared.getNameFromDatabase(id: recipient.recipient_id) {
                        recipientNames[recipient.recipient_id] = nameInfo.name
                    } else {
                        // 如果数据库中没有，再从API获取
                        let recipientResult = try await UniverseAPI.shared.fetchAndSaveNames(ids: [recipient.recipient_id])
                        if recipientResult > 0 {
                            if let nameInfo = try await UniverseAPI.shared.getNameFromDatabase(id: recipient.recipient_id) {
                                recipientNames[recipient.recipient_id] = nameInfo.name
                            } else {
                                recipientNames[recipient.recipient_id] = "未知\(getRecipientTypeText(recipient.recipient_type))"
                            }
                        }
                    }
                default:
                    recipientNames[recipient.recipient_id] = "未知收件人"
                }
            }
            
            // 4. 处理邮件正文
            let processedBody = RichTextProcessor.processRichText(content.body)
            
            // 5. 创建完整的邮件详情数据
            let mailDetailData = MailDetailData(
                content: content,
                senderName: senderName,
                recipientNames: recipientNames,
                processedBody: processedBody
            )
            
            // 6. 一次性更新视图数据
            self.mailDetail = mailDetailData
            
        } catch {
            Logger.error("加载邮件内容失败: \(error)")
            self.error = error
        }
        
        isLoading = false
    }
    
    private func getRecipientTypeText(_ type: String) -> String {
        switch type {
            case "character": return "角色"
            case "corporation": return "军团"
            case "alliance": return "联盟"
            case "mailing_list": return "邮件列表"
            default: return "收件人"
        }
    }
} 
