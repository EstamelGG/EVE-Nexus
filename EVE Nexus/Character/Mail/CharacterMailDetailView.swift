import SwiftUI

// 完整的邮件详情数据结构
struct MailDetailData {
    let content: EVEMailContent
    let senderName: String
    let recipientNames: [Int: String]
}

struct CharacterMailDetailView: View {
    let characterId: Int
    let mail: EVEMail
    @StateObject private var viewModel = CharacterMailDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingComposeView = false
    @State private var composeType: ComposeType?
    @ObservedObject var databaseManager = DatabaseManager.shared

    enum ComposeType {
        case reply, replyAll, forward

        var title: String {
            switch self {
            case .reply:
                return NSLocalizedString("Main_EVE_Mail_Reply", comment: "")
            case .replyAll:
                return NSLocalizedString("Main_EVE_Mail_Reply_All", comment: "")
            case .forward:
                return NSLocalizedString("Main_EVE_Mail_Forward", comment: "")
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
                    Text(NSLocalizedString("Main_EVE_Mail_Load_Failed", comment: ""))
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
                                    .textSelection(.enabled)
                                Text(mail.timestamp.formatDate())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // 收件人信息
                        if !detail.content.recipients.isEmpty {
                            (Text(NSLocalizedString("Main_EVE_Mail_To", comment: ""))
                                .foregroundColor(.secondary)
                                + Text(
                                    detail.content.recipients.compactMap {
                                        detail.recipientNames[$0.recipient_id]
                                            ?? NSLocalizedString(
                                                "Main_EVE_Mail_Unknown_Recipient", comment: ""
                                            )
                                    }.joined(separator: ", ")))
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }

                        Divider()
                            .padding(.vertical, 8)

                        // 使用 RichTextView 替换原来的 Text
                        RichTextView(text: detail.content.body, databaseManager: databaseManager)
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
                        Text(NSLocalizedString("Main_EVE_Mail_Reply", comment: ""))
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
                        Text(NSLocalizedString("Main_EVE_Mail_Reply_All", comment: ""))
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
                        Text(NSLocalizedString("Main_EVE_Mail_Forward", comment: ""))
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
                NavigationStack {
                    CharacterComposeMailView(
                        characterId: characterId,
                        initialRecipients: getInitialRecipients(type: type, detail: detail),
                        initialSubject: getInitialSubject(type: type, detail: detail),
                        initialBody: getInitialBody(type: type, detail: detail)
                    )
                }
                .interactiveDismissDisabled()
            }
        }
        .task {
            await viewModel.loadMailContent(characterId: characterId, mailId: mail.mail_id)
        }
    }

    private func getInitialRecipients(type: ComposeType, detail: MailDetailData) -> [MailRecipient]
    {
        switch type {
        case .reply:
            // 只回复给原发件人
            return [
                MailRecipient(id: detail.content.from, name: detail.senderName, type: .character)
            ]
        case .replyAll:
            // 回复给原发件人和所有收件人
            var recipients = [
                MailRecipient(id: detail.content.from, name: detail.senderName, type: .character)
            ]
            recipients.append(
                contentsOf: detail.content.recipients.map { recipient in
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
        let dateString = mail.timestamp.formatDate()

        switch type {
        case .reply, .replyAll:
            let header = String(format: NSLocalizedString("Main_EVE_Mail_Wrote", comment: ""))
            return formatMailContent("\n\n\(header)\n\n\(detail.content.body)")
        case .forward:
            let forwardHeader = NSLocalizedString("Main_EVE_Mail_Forward_Header", comment: "")
            let from = String(
                format: NSLocalizedString("Main_EVE_Mail_Forward_From", comment: ""),
                detail.senderName
            )
            let date = String(
                format: NSLocalizedString("Main_EVE_Mail_Forward_Date", comment: ""), dateString
            )
            let subject = String(
                format: NSLocalizedString("Main_EVE_Mail_Forward_Subject", comment: ""),
                detail.content.subject
            )
            let to = String(
                format: NSLocalizedString("Main_EVE_Mail_Forward_To", comment: ""),
                detail.content.recipients.map {
                    detail.recipientNames[$0.recipient_id]
                        ?? NSLocalizedString("Main_EVE_Mail_Unknown_Recipient", comment: "")
                }.joined(separator: ", ")
            )

            return formatMailContent(
                "\n\n\(forwardHeader)\n\(from)\n\(date)\n\(subject)\n\(to)\n\n\(detail.content.body)"
            )
        }
    }

    private func formatMailContent(_ content: String) -> String {
        return content.components(separatedBy: .newlines)
            .map { line in
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                if trimmedLine.isEmpty {
                    return ""
                }
                // 检查是否已经包含HTML标签
                let lowercasedLine = trimmedLine.lowercased()
                if lowercasedLine.contains("<font") && lowercasedLine.contains("</font>") {
                    // 如果已经有font标签，直接返回原内容
                    return trimmedLine
                }
                if lowercasedLine.contains("<br") && lowercasedLine.contains(">") {
                    // 如果已经有br标签，直接返回原内容
                    return trimmedLine
                }
                return "<font size=\"15\" color=\"#bfffffff\">\(trimmedLine)</font>"
            }
            .joined(separator: "\n")
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
            let content = try await CharacterMailAPI.shared.fetchMailContent(
                characterId: characterId, mailId: mailId
            )

            // 2. 获取发件人名称
            var senderName = "未知发件人"
            if let nameInfo = try await UniverseAPI.shared.getNamesWithFallback(ids: [content.from]
            )[content.from] {
                senderName = nameInfo.name
            }

            // 3. 获取所有收件人名称
            var recipientNames: [Int: String] = [:]
            for recipient in content.recipients {
                switch recipient.recipient_type {
                case "mailing_list":
                    if let listName = try await CharacterMailAPI.shared.loadMailListsFromDatabase(
                        characterId: characterId
                    )
                    .first(where: { $0.mailing_list_id == recipient.recipient_id })?.name {
                        recipientNames[recipient.recipient_id] = "[\(listName)]"
                    } else {
                        recipientNames[recipient.recipient_id] = "[邮件列表#\(recipient.recipient_id)]"
                    }
                case "character", "corporation", "alliance":
                    if let nameInfo = try await UniverseAPI.shared.getNamesWithFallback(ids: [
                        recipient.recipient_id
                    ])[recipient.recipient_id] {
                        recipientNames[recipient.recipient_id] = nameInfo.name
                    } else {
                        recipientNames[recipient.recipient_id] =
                            "未知\(getRecipientTypeText(recipient.recipient_type))"
                    }
                default:
                    recipientNames[recipient.recipient_id] = "未知收件人"
                }
            }

            // 4. 创建完整的邮件详情数据（不再需要处理邮件正文）
            let mailDetailData = MailDetailData(
                content: content,
                senderName: senderName,
                recipientNames: recipientNames
            )

            // 5. 更新视图数据
            mailDetail = mailDetailData

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
