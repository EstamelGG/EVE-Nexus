import SwiftUI

// 全局头像加载器
@MainActor
class CharacterPortraitLoader: ObservableObject {
    static let shared = CharacterPortraitLoader()
    
    @Published private(set) var portraits: [String: UIImage] = [:]
    @Published private(set) var isCorporation: [String: Bool] = [:]
    private var loadingTasks: [String: Task<Void, Never>] = [:]
    
    private init() {}
    
    func loadPortrait(for characterId: Int, size: Int) {
        let key = "\(characterId)_\(size)"
        
        // 如果已经在加载中或已加载完成，直接返回
        if loadingTasks[key] != nil || portraits[key] != nil {
            return
        }
        
        // 创建新的加载任务
        let task = Task {
            do {
                // 尝试获取角色头像
                let portrait = try await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: characterId,
                    size: size,
                    catchImage: false
                )
                
                await MainActor.run {
                    self.portraits[key] = portrait
                    self.isCorporation[key] = false
                }
                
                Logger.info("成功加载角色头像 - ID: \(characterId), 大小: \(size)")
            } catch {
                // 如果获取角色头像失败，尝试获取军团头像
                do {
                    let corpLogo = try await CorporationAPI.shared.fetchCorporationLogo(
                        corporationId: characterId,
                        size: size
                    )
                    
                    await MainActor.run {
                        self.portraits[key] = corpLogo
                        self.isCorporation[key] = true
                    }
                    
                    Logger.info("成功加载军团头像 - ID: \(characterId), 大小: \(size)")
                } catch {
                    Logger.error("加载头像失败（角色和军团都失败）: \(error)")
                }
            }
        }
        
        loadingTasks[key] = task
    }
    
    func cancelAllTasks() {
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
    }
    
    func getPortrait(for characterId: Int, size: Int) -> UIImage? {
        return portraits["\(characterId)_\(size)"]
    }
    
    func isCorporationPortrait(for characterId: Int, size: Int) -> Bool {
        return isCorporation["\(characterId)_\(size)"] ?? false
    }
}

// 头像视图
struct CharacterPortrait: View {
    let characterId: Int
    let size: CGFloat
    let displaySize: CGFloat
    let cornerRadius: CGFloat
    @StateObject private var portraitLoader = CharacterPortraitLoader.shared
    
    init(characterId: Int, size: CGFloat, displaySize: CGFloat? = nil, cornerRadius: CGFloat = 6) {
        self.characterId = characterId
        self.size = size
        self.displaySize = displaySize ?? size
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        ZStack {
            if let image = portraitLoader.getPortrait(for: characterId, size: Int(size)) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: displaySize, height: displaySize)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .overlay(
                        portraitLoader.isCorporationPortrait(for: characterId, size: Int(size))
                            ? RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            : nil
                    )
            } else {
                ProgressView()
                    .frame(width: displaySize, height: displaySize)
            }
        }
        .onAppear {
            portraitLoader.loadPortrait(for: characterId, size: Int(size))
        }
    }
}

@MainActor
class CharacterMailListViewModel: ObservableObject {
    @Published var mails: [EVEMail] = []
    @Published var senderNames: [Int: String] = [:]
    @Published var senderCategories: [Int: String] = [:]
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: Error?
    @Published var isRefreshing = false
    @Published var hasMoreMails = true
    @Published var initialLoadDone = false

    func fetchMails(characterId: Int, labelId: Int? = nil, forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone && !forceRefresh {
            return
        }

        if forceRefresh {
            isRefreshing = true
        } else {
            isLoading = true
        }

        defer {
            isLoading = false
            isRefreshing = false
        }

        do {
            let newMails: [EVEMail]
            if let listId = labelId, isMailingList(listId) {
                // 如果是邮件列表，获取全量邮件并过滤
                newMails = try await CharacterMailAPI.shared.fetchLatestMails(
                    characterId: characterId)
                let filteredMails = newMails.filter { mail in
                    mail.recipients.contains { recipient in
                        recipient.recipient_id == listId
                            && recipient.recipient_type == "mailing_list"
                    }
                }
                // 先加载发件人信息
                await loadSenderNames(for: filteredMails)
                // 然后一次性更新UI数据
                mails = filteredMails
            } else {
                // 其他情况（收件箱等）使用原有逻辑
                newMails = try await CharacterMailAPI.shared.fetchLatestMails(
                    characterId: characterId, labelId: labelId
                )
                // 先加载发件人信息
                await loadSenderNames(for: newMails)
                // 然后一次性更新UI数据
                mails = newMails
            }

            hasMoreMails = !mails.isEmpty
            initialLoadDone = true

        } catch {
            Logger.error("获取邮件失败: \(error)")
            self.error = error
        }
    }

    func loadMoreMails(characterId: Int, labelId: Int? = nil) async {
        guard !isLoadingMore, hasMoreMails, let lastMail = mails.last else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let olderMails: [EVEMail]
            if let listId = labelId, isMailingList(listId) {
                // 如果是邮件列表，获取全量邮件并过滤
                olderMails = try await CharacterMailAPI.shared.fetchLatestMails(
                    characterId: characterId,
                    lastMailId: lastMail.mail_id
                )
                let filteredMails = olderMails.filter { mail in
                    mail.recipients.contains { recipient in
                        recipient.recipient_id == listId
                            && recipient.recipient_type == "mailing_list"
                    }
                }

                if !filteredMails.isEmpty {
                    // 先加载发件人信息
                    await loadSenderNames(for: filteredMails)
                    // 然后一次性更新UI数据
                    mails.append(contentsOf: filteredMails)
                    hasMoreMails = true
                    Logger.info("成功加载 \(filteredMails.count) 封更老的邮件")
                } else {
                    hasMoreMails = false
                    Logger.info("没有更多邮件了")
                }
            } else {
                // 其他情况（收件箱等）使用原有逻辑
                olderMails = try await CharacterMailAPI.shared.fetchLatestMails(
                    characterId: characterId,
                    labelId: labelId,
                    lastMailId: lastMail.mail_id
                )

                if !olderMails.isEmpty {
                    // 先加载发件人信息
                    await loadSenderNames(for: olderMails)
                    // 然后一次性更新UI数据
                    mails.append(contentsOf: olderMails)
                    hasMoreMails = true
                    Logger.info("成功加载 \(olderMails.count) 封更老的邮件")
                } else {
                    hasMoreMails = false
                    Logger.info("没有更多邮件了")
                }
            }

        } catch {
            Logger.error("加载更多邮件失败: \(error)")
            self.error = error
        }
    }

    // 判断是否是邮件列表ID
    private func isMailingList(_ id: Int) -> Bool {
        // 系统预定义的标签ID都很小，邮件列表ID通常很大
        return id > 100_000
    }

    func getSenderCategory(_ id: Int) -> String {
        return senderCategories[id] ?? "character"
    }

    private func loadSenderNames(for mails: [EVEMail]) async {
        // 收集所有发件人ID并去重
        let senderIds = Set(mails.map { $0.from })

        do {
            // 使用getNamesWithFallback一次性获取所有名称信息
            let names = try await UniverseAPI.shared.getNamesWithFallback(ids: Array(senderIds))

            // 更新视图数据
            for (id, info) in names {
                senderNames[id] = info.name
                senderCategories[id] = info.category
            }

            Logger.debug("成功获取 \(names.count) 个发件人的信息")
        } catch {
            Logger.error("获取发件人信息失败: \(error)")
        }
    }

    func getSenderName(_ characterId: Int) -> String {
        return senderNames[characterId] ?? NSLocalizedString("Unknown", comment: "")
    }
}

// 邮件列表项视图
private struct MailListItemView: View {
    let characterId: Int
    let mail: EVEMail
    let viewModel: CharacterMailListViewModel

    var body: some View {
        HStack(spacing: 12) {
            // 发件人头像
            if viewModel.getSenderCategory(mail.from) == "corporation" {
                UniversePortrait(id: mail.from, type: .corporation, size: 64, displaySize: 48)
            } else if viewModel.getSenderCategory(mail.from) == "alliance" {
                UniversePortrait(id: mail.from, type: .alliance, size: 64, displaySize: 48)
            } else {
                CharacterPortrait(characterId: mail.from, size: 64, displaySize: 48)
            }

            VStack(alignment: .leading, spacing: 2) {
                // 邮件主题
                Text(mail.subject)
                    .font(.headline)
                    // .foregroundColor(mail.is_read == true ? .secondary : .primary)
                    .lineLimit(1)

                // 发件人名称
                Text(NSLocalizedString("Main_EVE_Mail_From", comment: ""))
                    + Text(viewModel.getSenderName(mail.from))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 时间
                Text(mail.timestamp.formatDate())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 未读标记
            //            if mail.is_read != true {
            //                Circle()
            //                    .fill(Color.blue)
            //                    .frame(width: 8, height: 8)
            //            }
        }
        .padding(.vertical, 2)
    }
}

// 加载指示器视图
private struct LoadingIndicatorView: View {
    var body: some View {
        HStack {
            Spacer()
            VStack {
                ProgressView()
                Text(NSLocalizedString("Main_EVE_Mail_Loading", comment: ""))
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .padding(.top, 8)
            }
            Spacer()
        }
    }
}

// 加载更多指示器视图
private struct LoadMoreIndicatorView: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Text(NSLocalizedString("Main_EVE_Mail_Loading", comment: ""))
                .foregroundColor(.secondary)
                .font(.subheadline)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct CharacterMailListView: View {
    let characterId: Int
    let labelId: Int?
    let title: String

    @StateObject private var viewModel = CharacterMailListViewModel()
    @State private var scrollPosition: Int?
    @State private var composeMailData: ComposeMailData?
    @State private var hasInitialized = false  // 追踪是否已执行初始化

    struct ComposeMailData: Identifiable {
        let id = UUID()
        let recipients: [MailRecipient]
    }

    init(characterId: Int, labelId: Int? = nil, title: String? = nil) {
        self.characterId = characterId
        self.labelId = labelId
        self.title = title ?? NSLocalizedString("Main_EVE_Mail_All", comment: "")
    }

    // 初始化数据加载方法
    private func loadInitialDataIfNeeded() {
        guard !hasInitialized else { return }

        hasInitialized = true

        Task {
            await viewModel.fetchMails(characterId: characterId, labelId: labelId)
        }
    }

    var body: some View {
        ScrollViewReader { _ in
            List {
                if viewModel.isLoading && viewModel.mails.isEmpty {
                    LoadingIndicatorView()
                }

                ForEach(viewModel.mails, id: \.mail_id) { mail in
                    NavigationLink(
                        destination: CharacterMailDetailView(characterId: characterId, mail: mail)
                    ) {
                        MailListItemView(characterId: characterId, mail: mail, viewModel: viewModel)
                            .id(mail.mail_id)
                    }
                    .onAppear {
                        if mail.mail_id == viewModel.mails.last?.mail_id {
                            Task {
                                await viewModel.loadMoreMails(
                                    characterId: characterId, labelId: labelId
                                )
                            }
                        }
                        // 记录当前滚动位置
                        scrollPosition = mail.mail_id
                    }
                }

                if viewModel.isLoadingMore {
                    LoadMoreIndicatorView()
                }
            }
            .refreshable {
                await viewModel.fetchMails(
                    characterId: characterId, labelId: labelId, forceRefresh: true
                )
            }
            .navigationTitle(title)
            .toolbar {
                // 只在军团邮箱页面显示编辑按钮
                if labelId == MailboxType.corporation.labelId {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            // 先获取军团信息，再显示编辑页面
                            getCorpInfoAndShowCompose()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            }
            .sheet(item: $composeMailData) { data in
                NavigationStack {
                    CharacterComposeMailView(
                        characterId: characterId,
                        initialRecipients: data.recipients
                    )
                }
            }
            .onAppear {
                loadInitialDataIfNeeded()
            }
        }
    }

    private func getCorpInfoAndShowCompose() {
        Task {
            do {
                // 获取当前角色所在的军团
                guard
                    let corporationId = try await CharacterDatabaseManager.shared
                        .getCharacterCorporationId(characterId: characterId)
                else {
                    Logger.error("无法获取军团ID")
                    return
                }

                // 获取军团名称
                let corpNames = try await UniverseAPI.shared.getNamesWithFallback(ids: [
                    corporationId
                ])
                guard let corpInfo = corpNames[corporationId] else {
                    Logger.error("无法获取军团名称")
                    return
                }

                Logger.debug("获取到军团信息 - ID: \(corporationId), 名称: \(corpInfo.name)")

                // 创建收件人并更新状态
                let recipient = MailRecipient(
                    id: corporationId,
                    name: corpInfo.name,
                    type: .corporation
                )
                composeMailData = ComposeMailData(recipients: [recipient])

            } catch {
                Logger.error("获取军团信息失败: \(error)")
            }
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
        outputFormatter.locale = Locale(identifier: "en_US_POSIX")

        return outputFormatter.string(from: date)
    }
}
