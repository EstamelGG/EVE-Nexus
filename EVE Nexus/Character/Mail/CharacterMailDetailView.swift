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
    @State private var showingComposeView = false
    @State private var composeType: ComposeType?
    
    enum ComposeType {
        case reply, replyAll, forward
        
        var title: String {
            switch self {
            case .reply: return "回复"
            case .replyAll: return "回复全体"
            case .forward: return "转发"
            }
        }
    }
    
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
                            (Text("收件人：")
                                .foregroundColor(.secondary) +
                            Text(detail.content.recipients.compactMap { detail.recipientNames[$0.recipient_id] ?? "未知收件人" }.joined(separator: ", ")))
                                .font(.subheadline)
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
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button {
                    composeType = .reply
                    showingComposeView = true
                } label: {
                    VStack {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                        Text("回复")
                            .font(.caption)
                    }
                }
                .disabled(viewModel.mailDetail == nil)
                
                Spacer()
                Button {
                    composeType = .replyAll
                    showingComposeView = true
                } label: {
                    VStack {
                        Image(systemName: "arrowshape.turn.up.left.2.fill")
                        Text("回复全体")
                            .font(.caption)
                    }
                }
                .disabled(viewModel.mailDetail == nil)
                
                Spacer()
                Button {
                    composeType = .forward
                    showingComposeView = true
                } label: {
                    VStack {
                        Image(systemName: "arrowshape.turn.up.forward.fill")
                        Text("转发")
                            .font(.caption)
                    }
                }
                .disabled(viewModel.mailDetail == nil)
                Spacer()
            }
        }
        .toolbarBackground(.visible, for: .bottomBar)
        .sheet(isPresented: $showingComposeView) {
            if let detail = viewModel.mailDetail, let type = composeType {
                NavigationView {
                    CharacterComposeMailView(
                        characterId: characterId,
                        initialRecipients: getInitialRecipients(type: type, detail: detail),
                        initialSubject: getInitialSubject(type: type, detail: detail),
                        initialBody: getInitialBody(type: type, detail: detail)
                    )
                }
            }
        }
        .task {
            await viewModel.loadMailContent(characterId: characterId, mailId: mail.mail_id)
        }
    }
    
    private func getInitialRecipients(type: ComposeType, detail: MailDetailData) -> [MailRecipient] {
        switch type {
        case .reply:
            // 只回复给原发件人
            return [MailRecipient(id: detail.content.from, name: detail.senderName, type: .character)]
        case .replyAll:
            // 回复给原发件人和所有收件人
            var recipients = [MailRecipient(id: detail.content.from, name: detail.senderName, type: .character)]
            recipients.append(contentsOf: detail.content.recipients.map { recipient in
                MailRecipient(
                    id: recipient.recipient_id,
                    name: detail.recipientNames[recipient.recipient_id] ?? "未知收件人",
                    type: getRecipientType(from: recipient.recipient_type)
                )
            })
            return recipients
        case .forward:
            // 转发时没有初始收件人
            return []
        }
    }
    
    private func getInitialSubject(type: ComposeType, detail: MailDetailData) -> String {
        switch type {
        case .reply, .replyAll:
            return "Re: \(detail.content.subject)"
        case .forward:
            return "Fwd: \(detail.content.subject)"
        }
    }
    
    private func getInitialBody(type: ComposeType, detail: MailDetailData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        let dateString = mail.timestamp.formatDate()
        
        switch type {
        case .reply, .replyAll:
            return "\n\n在 \(dateString)，\(detail.senderName) 写道：\n\n\(detail.content.body)"
        case .forward:
            return "\n\n-------- 转发的邮件 --------\n" +
                   "发件人：\(detail.senderName)\n" +
                   "日期：\(dateString)\n" +
                   "主题：\(detail.content.subject)\n" +
                   "收件人：\(detail.content.recipients.map { detail.recipientNames[$0.recipient_id] ?? "未知收件人" }.joined(separator: ", "))\n\n" +
                   detail.content.body
        }
    }
    
    private func getRecipientType(from typeString: String) -> MailRecipient.RecipientType {
        switch typeString {
        case "character": return .character
        case "corporation": return .corporation
        case "alliance": return .alliance
        case "mailing_list": return .mailingList
        default: return .character
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
            
            // 2. 获取发件人名称
            var senderName = "未知发件人"
            if let nameInfo = try await UniverseAPI.shared.getNamesWithFallback(ids: [content.from])[content.from] {
                senderName = nameInfo.name
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
                    if let nameInfo = try await UniverseAPI.shared.getNamesWithFallback(ids: [recipient.recipient_id])[recipient.recipient_id] {
                        recipientNames[recipient.recipient_id] = nameInfo.name
                    } else {
                        recipientNames[recipient.recipient_id] = "未知\(getRecipientTypeText(recipient.recipient_type))"
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
