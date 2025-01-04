import SwiftUI

struct CharacterMailDetailView: View {
    let characterId: Int
    let mail: EVEMail
    @StateObject private var viewModel = CharacterMailDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if let content = viewModel.mailContent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 主题
                        Text(content.subject)
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        // 发件人和时间信息
                        HStack {
                            CharacterPortrait(id: content.from, size: 32)
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
                        Text(LocalizedStringKey(content.body))
                            .textSelection(.enabled)
                    }
                    .padding()
                }
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMailContent(characterId: characterId, mailId: mail.mail_id)
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
                    senderName = try await universeAPI.getNameFromDatabase(id: content.from)
                }
                
                // 获取收件人名称
                let recipientIds = content.recipients.map { $0.recipient_id }
                let recipientResult = try await universeAPI.fetchAndSaveNames(ids: recipientIds)
                if recipientResult > 0 {
                    for id in recipientIds {
                        if let name = try await universeAPI.getNameFromDatabase(id: id) {
                            recipientNames[id] = name
                        }
                    }
                }
            }
        } catch {
            Logger.error("加载邮件内容失败: \(error)")
        }
    }
} 