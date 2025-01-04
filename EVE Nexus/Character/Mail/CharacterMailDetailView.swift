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
    
    func loadMailContent(characterId: Int, mailId: Int) async {
        do {
            // 获取邮件内容
            mailContent = try await CharacterMailAPI.shared.fetchMailContent(characterId: characterId, mailId: mailId)
            
            if let content = mailContent {
                // 获取发件人名称
                let senderResult = try await UniverseAPI.shared.fetchAndSaveNames(ids: [content.from])
                if senderResult > 0 {
                    if let nameInfo = try await UniverseAPI.shared.getNameFromDatabase(id: content.from) {
                        senderName = nameInfo.name
                    }
                }
                
                // 获取收件人名称
                // 分类处理不同类型的收件人
                for recipient in content.recipients {
                    switch recipient.recipient_type {
                    case "mailing_list":
                        // 从数据库中查找邮件列表名称
                        if let listName = try await CharacterMailAPI.shared.loadMailListsFromDatabase(characterId: characterId)
                            .first(where: { $0.mailing_list_id == recipient.recipient_id })?.name {
                            recipientNames[recipient.recipient_id] = listName
                        } else {
                            recipientNames[recipient.recipient_id] = "邮件列表#\(recipient.recipient_id)"
                        }
                    case "character", "corporation", "alliance":
                        // 获取角色、军团、联盟的名称
                        let recipientResult = try await UniverseAPI.shared.fetchAndSaveNames(ids: [recipient.recipient_id])
                        if recipientResult > 0 {
                            if let nameInfo = try await UniverseAPI.shared.getNameFromDatabase(id: recipient.recipient_id) {
                                recipientNames[recipient.recipient_id] = nameInfo.name
                            } else {
                                recipientNames[recipient.recipient_id] = "未知\(getRecipientTypeText(recipient.recipient_type))"
                            }
                        }
                    default:
                        recipientNames[recipient.recipient_id] = "未知收件人"
                    }
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
