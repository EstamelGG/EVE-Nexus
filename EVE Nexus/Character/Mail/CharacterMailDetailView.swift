import SwiftUI

/// 完整的邮件详情数据结构
struct MailDetailData {
    let content: EVEMailContent
    let senderName: String
    let recipientNames: [Int: String]
    let senderCategory: String
    let recipientCategories: [Int: String]
}

struct CharacterMailDetailView: View {
    let characterId: Int
    let mail: EVEMail

    @StateObject private var viewModel = CharacterMailDetailViewModel()
    @State private var showingComposeView = false
    @State private var composeType: ComposeType?
    @ObservedObject var databaseManager = DatabaseManager.shared
    @State private var hasInitialized = false // 追踪是否已执行初始化
    @State private var showingSenderDetail = false // 控制显示发件人详情的sheet
    @State private var isRecipientsExpanded = false // 控制收件人列表展开/折叠

    enum ComposeType {
        case reply, replyAll, forward
    }

    /// 初始化数据加载方法
    private func loadInitialDataIfNeeded() {
        guard !hasInitialized else { return }

        hasInitialized = true

        Task {
            await viewModel.loadMailContent(characterId: characterId, mailId: mail.mail_id)
        }
    }

    /// 添加新的方法来处理按钮点击
    private func handleComposeButton(type: ComposeType) {
        composeType = type
        showingComposeView = true
    }

    /// 导航辅助方法：根据类型返回对应的详情视图
    @ViewBuilder
    private func navigationDestination(for id: Int, category: String) -> some View {
        if let characterAuth = EVELogin.shared.getCharacterByID(characterId) {
            switch category {
            case "character":
                CharacterDetailView(characterId: id, character: characterAuth.character)
            case "corporation":
                CorporationDetailView(corporationId: id, character: characterAuth.character)
            case "alliance":
                AllianceDetailView(allianceId: id, character: characterAuth.character)
            default:
                // 默认尝试作为人物处理
                CharacterDetailView(characterId: id, character: characterAuth.character)
            }
        }
    }

    /// 底部操作栏：回复 / 回复全部 / 转发
    private var bottomActionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                actionButton(
                    icon: "arrowshape.turn.up.left.fill",
                    title: NSLocalizedString("Main_EVE_Mail_Reply", comment: ""),
                    action: { handleComposeButton(type: .reply) }
                )
                actionButton(
                    icon: "arrowshape.turn.up.left.2.fill",
                    title: NSLocalizedString("Main_EVE_Mail_Reply_All", comment: ""),
                    action: { handleComposeButton(type: .replyAll) }
                )
                actionButton(
                    icon: "arrowshape.turn.up.forward.fill",
                    title: NSLocalizedString("Main_EVE_Mail_Forward", comment: ""),
                    action: { handleComposeButton(type: .forward) }
                )
            }
        }
        .background(.bar)
    }

    /// 单个操作按钮：图标 + 文字，等宽分布
    private func actionButton(
        icon: String, title: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.mailDetail == nil)
    }

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail = viewModel.mailDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 主题
                        Text(detail.content.subject)
                            .font(.headline)
                            .padding(.bottom, 4)

                        // 发件人信息
                        VStack(alignment: .leading, spacing: 8) {
                            // 发件人和时间信息
                            HStack {
                                // 根据类型显示对应的头像
                                if viewModel.senderCategory == "corporation" {
                                    UniversePortrait(id: detail.content.from, type: .corporation, size: 32, displaySize: 32)
                                } else if viewModel.senderCategory == "alliance" {
                                    UniversePortrait(id: detail.content.from, type: .alliance, size: 32, displaySize: 32)
                                } else {
                                    CharacterPortrait(characterId: detail.content.from, size: 32)
                                }
                                VStack(alignment: .leading) {
                                    Text(detail.senderName)
                                        .font(.subheadline)
                                    Text(mail.timestamp.formatDate())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()

                                // 信息图标按钮
                                Button {
                                    showingSenderDetail = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 18))
                                }
                            }
                        }

                        // 收件人信息（单独一行，支持折叠）
                        if !detail.content.recipients.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                // 第一个收件人（始终显示）
                                if let firstRecipient = detail.content.recipients.first {
                                    HStack {
                                        Text(NSLocalizedString("Main_EVE_Mail_To", comment: ""))
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                        Text(detail.recipientNames[firstRecipient.recipient_id]
                                            ?? NSLocalizedString(
                                                "Main_EVE_Mail_Unknown_Recipient", comment: ""
                                            ))
                                            .font(.subheadline)
                                        Spacer()

                                        // 如果有多个收件人，显示展开/折叠按钮
                                        if detail.content.recipients.count > 1 {
                                            Button {
                                                withAnimation {
                                                    isRecipientsExpanded.toggle()
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    if isRecipientsExpanded {
                                                        Text(NSLocalizedString("Misc_Collapse", comment: "收起"))
                                                            .font(.caption)
                                                            .foregroundColor(.blue)
                                                    } else {
                                                        let moreCount = detail.content.recipients.count - 1
                                                        Text(moreCount > 1
                                                            ? String(format: NSLocalizedString("Misc_Show_More_Count", comment: "+%d more"), moreCount)
                                                            : NSLocalizedString("Misc_Show_More", comment: "显示更多"))
                                                            .font(.caption)
                                                            .foregroundColor(.blue)
                                                    }
                                                    Image(systemName: isRecipientsExpanded ? "chevron.up" : "chevron.down")
                                                        .font(.caption2)
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                        }
                                    }
                                }

                                // 其他收件人（折叠时隐藏）
                                if isRecipientsExpanded && detail.content.recipients.count > 1 {
                                    ForEach(Array(detail.content.recipients.enumerated()), id: \.offset) { index, recipient in
                                        if index > 0 {
                                            HStack {
                                                Text(NSLocalizedString("Main_EVE_Mail_To", comment: ""))
                                                    .foregroundColor(.secondary)
                                                    .font(.subheadline)
                                                    .opacity(0) // 占位，保持对齐
                                                Text(detail.recipientNames[recipient.recipient_id]
                                                    ?? NSLocalizedString(
                                                        "Main_EVE_Mail_Unknown_Recipient", comment: ""
                                                    ))
                                                    .font(.subheadline)
                                                Spacer()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Divider()
                            .padding(.vertical, 8)

                        RichTextView(text: detail.content.body, databaseManager: databaseManager)
                            .font(.body)
                    }
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActionBar
        }
        .sheet(isPresented: $showingComposeView) {
            if let detail = viewModel.mailDetail, let type = composeType {
                NavigationStack {
                    CharacterComposeMailView(
                        characterId: characterId,
                        initialRecipients: getInitialRecipients(type: type, detail: detail),
                        initialSubject: getInitialSubject(type: type, detail: detail),
                        initialBody: "",
                        appendContent: getAppendContent(type: type, detail: detail)
                    )
                }
                .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: $showingSenderDetail) {
            if let detail = viewModel.mailDetail {
                NavigationStack {
                    navigationDestination(
                        for: detail.content.from,
                        category: viewModel.senderCategory
                    )
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(NSLocalizedString("Common_Done", comment: "完成")) {
                                showingSenderDetail = false
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            loadInitialDataIfNeeded()
        }
        .onChange(of: showingComposeView) { _, newValue in
            if !newValue {
                composeType = nil
            }
        }
    }

    private func getInitialRecipients(type: ComposeType, detail: MailDetailData) -> [MailRecipient] {
        /// 辅助方法：根据 category 获取 MailRecipient.RecipientType
        func getRecipientTypeFromCategory(_ category: String) -> MailRecipient.RecipientType {
            switch category {
            case "character": return .character
            case "corporation": return .corporation
            case "alliance": return .alliance
            default: return .character
            }
        }

        switch type {
        case .reply:
            // 只回复给原发件人
            return [
                MailRecipient(
                    id: detail.content.from,
                    name: detail.senderName,
                    type: getRecipientTypeFromCategory(detail.senderCategory)
                ),
            ]
        case .replyAll:
            // 回复给原发件人和所有收件人
            var recipients = [
                MailRecipient(
                    id: detail.content.from,
                    name: detail.senderName,
                    type: getRecipientTypeFromCategory(detail.senderCategory)
                ),
            ]
            recipients.append(
                contentsOf: detail.content.recipients.map { recipient in
                    // 优先使用 category，如果没有则使用 recipient_type
                    let category = detail.recipientCategories[recipient.recipient_id] ?? recipient.recipient_type
                    return MailRecipient(
                        id: recipient.recipient_id,
                        name: detail.recipientNames[recipient.recipient_id]
                            ?? NSLocalizedString("Unknown", comment: ""),
                        type: category == "mailing_list"
                            ? .mailingList
                            : getRecipientTypeFromCategory(category)
                    )
                }
            )
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

    private func getAppendContent(type: ComposeType, detail: MailDetailData) -> String {
        let dateString = mail.timestamp.formatDate()

        switch type {
        case .reply, .replyAll:
            let header = String.localizedStringWithFormat(NSLocalizedString("Main_EVE_Mail_Wrote", comment: ""))
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
}

@MainActor
class CharacterMailDetailViewModel: ObservableObject {
    @Published var mailDetail: MailDetailData?
    @Published var isLoading = true
    @Published var error: Error?

    /// 发件人类型（直接从 mailDetail 读取，无需参数）
    var senderCategory: String {
        mailDetail?.senderCategory ?? "character"
    }

    func loadMailContent(characterId: Int, mailId: Int) async {
        isLoading = true
        error = nil

        do {
            // 1. 获取邮件内容
            let content = try await CharacterMailAPI.shared.fetchMailContent(
                characterId: characterId, mailId: mailId
            )

            // 2. 收集需要从API获取名称的实体ID（发件人 + character/corporation/alliance 类型的收件人）
            var entityIds: Set<Int> = [content.from]
            var entityRecipients: [EVEMailRecipient] = []

            for recipient in content.recipients {
                switch recipient.recipient_type {
                case "character", "corporation", "alliance":
                    entityIds.insert(recipient.recipient_id)
                    entityRecipients.append(recipient)
                default:
                    break
                }
            }

            // 批量获取所有实体名称（一次性API调用）
            // UniverseAPI内部已处理批量请求失败时的并发回退策略
            let namesMap: [Int: (name: String, category: String)]
            do {
                namesMap = try await UniverseAPI.shared.getNamesWithFallback(ids: Array(entityIds))
            } catch {
                Logger.warning("批量获取实体名称失败，使用并发回退策略: \(error)")
                namesMap = await UniverseAPI.shared.fetchNamesWithConcurrentFallback(ids: Array(entityIds))
            }

            // 获取发件人名称和类型
            var senderName = NSLocalizedString("Unknown", comment: "")
            var senderCategory = "character"
            if let nameInfo = namesMap[content.from] {
                senderName = nameInfo.name
                senderCategory = nameInfo.category
            }

            // 3. 仅在存在邮件列表收件人时，预加载数据库中的邮件列表
            let hasMailingList = content.recipients.contains { $0.recipient_type == "mailing_list" }
            let mailLists = hasMailingList
                ? (try? await CharacterMailAPI.shared.loadMailListsFromDatabase(characterId: characterId)) ?? []
                : []

            // 4. 单次遍历处理所有收件人
            var recipientNames: [Int: String] = [:]
            var recipientCategories: [Int: String] = [:]

            for recipient in content.recipients {
                switch recipient.recipient_type {
                case "character", "corporation", "alliance":
                    if let nameInfo = namesMap[recipient.recipient_id] {
                        recipientNames[recipient.recipient_id] = nameInfo.name
                        recipientCategories[recipient.recipient_id] = nameInfo.category
                    } else {
                        recipientNames[recipient.recipient_id] =
                            "\(NSLocalizedString("Unknown", comment: "")) \(getRecipientTypeText(recipient.recipient_type))"
                        recipientCategories[recipient.recipient_id] = recipient.recipient_type
                    }
                case "mailing_list":
                    if let listName = mailLists.first(where: { $0.mailing_list_id == recipient.recipient_id })?.name {
                        recipientNames[recipient.recipient_id] = "[\(listName)]"
                    } else {
                        recipientNames[recipient.recipient_id] =
                            "[\(NSLocalizedString("Main_EVE_Mail_List", comment: ""))#\(recipient.recipient_id)]"
                    }
                default:
                    recipientNames[recipient.recipient_id] = NSLocalizedString("Unknown", comment: "")
                }
            }

            // 5. 创建完整的邮件详情数据
            let mailDetailData = MailDetailData(
                content: content,
                senderName: senderName,
                recipientNames: recipientNames,
                senderCategory: senderCategory,
                recipientCategories: recipientCategories
            )

            // 6. 更新视图数据
            mailDetail = mailDetailData

        } catch {
            Logger.error("加载邮件内容失败: \(error)")
            self.error = error
        }

        isLoading = false
    }

    private func getRecipientTypeText(_ type: String) -> String {
        switch type {
        case "character": return NSLocalizedString("Recipient_Type_Character", comment: "")
        case "corporation": return NSLocalizedString("Recipient_Type_Corporation", comment: "")
        case "alliance": return NSLocalizedString("Recipient_Type_Alliance", comment: "")
        case "mailing_list": return NSLocalizedString("Recipient_Type_Mailing_List", comment: "")
        default: return NSLocalizedString("Unknown", comment: "")
        }
    }
}
