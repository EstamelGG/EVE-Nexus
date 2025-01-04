import SwiftUI

struct CharacterMailDetailView: View {
    let characterId: Int
    let mail: EVEMail
    @StateObject private var viewModel = CharacterMailDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        if let content = viewModel.mailContent {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 主题
                    Text(content.subject)
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    // 发件人和时间信息
                    HStack {
                        CharacterPortrait(characterId: content.from, size: 32)
                        VStack(alignment: .leading) {
                            Text(viewModel.senderName ?? "未知发件人")
                                .font(.subheadline)
                            Text(mail.timestamp.formatDate())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // 收件人信息
                    if !content.recipients.isEmpty {
                        Text("收件人：")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ForEach(content.recipients, id: \.recipient_id) { recipient in
                            Text(viewModel.recipientNames[recipient.recipient_id] ?? "未知收件人")
                                .font(.subheadline)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // 邮件正文
                    RichTextProcessor.processRichText(content.body)
                        .font(.body)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadMailContent(characterId: characterId, mailId: mail.mail_id)
            }
        } else {
            ProgressView()
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    await viewModel.loadMailContent(characterId: characterId, mailId: mail.mail_id)
                }
        }
    }
}

@MainActor
class CharacterMailDetailViewModel: ObservableObject {
    @Published var mailContent: EVEMailContent?
    @Published var senderName: String?
    @Published var recipientNames: [Int: String] = [:]
    
    private let mailAPI = CharacterMailAPI.shared
    private let universeAPI = UniverseAPI.shared
    
    func loadMailContent(characterId: Int, mailId: Int) async {
        do {
            // 获取邮件内容
            mailContent = try await mailAPI.fetchMailContent(characterId: characterId, mailId: mailId)
            
            if let content = mailContent {
                // 获取发件人名称
                let senderResult = try await universeAPI.fetchAndSaveNames(ids: [content.from])
                if senderResult > 0 {
                    if let nameInfo = try await universeAPI.getNameFromDatabase(id: content.from) {
                        senderName = nameInfo.name
                    }
                }
                
                // 获取收件人名称
                // 只获取角色、军团、联盟类型的收件人名称
                let validRecipients = content.recipients.filter { recipient in
                    let type = recipient.recipient_type
                    return type == "character" || type == "corporation" || type == "alliance"
                }
                
                if !validRecipients.isEmpty {
                    let recipientIds = validRecipients.map { $0.recipient_id }
                    let recipientResult = try await universeAPI.fetchAndSaveNames(ids: recipientIds)
                    if recipientResult > 0 {
                        for recipient in validRecipients {
                            if let nameInfo = try await universeAPI.getNameFromDatabase(id: recipient.recipient_id) {
                                recipientNames[recipient.recipient_id] = nameInfo.name
                            } else {
                                // 如果获取不到名称，使用默认名称
                                recipientNames[recipient.recipient_id] = "未知\(getRecipientTypeText(recipient.recipient_type))"
                            }
                        }
                    }
                }
                
                // 为邮件列表类型的收件人设置默认名称
                for recipient in content.recipients where recipient.recipient_type == "mailing_list" {
                    recipientNames[recipient.recipient_id] = "邮件列表#\(recipient.recipient_id)"
                }
            }
        } catch {
            Logger.error("加载邮件内容失败: \(error)")
        }
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
