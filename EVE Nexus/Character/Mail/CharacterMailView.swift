import SwiftUI

struct CharacterMailView: View {
    let characterId: Int
    @StateObject private var viewModel = CharacterMailViewModel()
    @State private var totalUnread: Int?
    @State private var inboxUnread: Int?
    @State private var corpUnread: Int?
    @State private var allianceUnread: Int?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showingComposeView = false
    @State private var hasInitialized = false  // 追踪是否已执行初始化

    // 初始化数据加载方法
    private func loadInitialDataIfNeeded() {
        guard !hasInitialized else { return }

        hasInitialized = true

        Task {
            await loadUnreadCounts()
            await viewModel.fetchMailLabels(characterId: characterId)
        }
    }

    var body: some View {
        List {
            // 全部邮件部分
            Section {
                NavigationLink {
                    CharacterMailListView(characterId: characterId)
                } label: {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.gray)
                            .frame(width: 24, height: 24)
                        Text(NSLocalizedString("Main_EVE_Mail_All", comment: ""))
                        //                        Spacer()
                        //                        if let totalUnread = totalUnread {
                        //                            Text("\(totalUnread)")
                        //                                .foregroundColor(.blue)
                        //                        }
                    }
                }
            }

            // 邮箱列表部分
            Section {
                ForEach(MailboxType.allCases, id: \.self) { mailbox in
                    NavigationLink {
                        CharacterMailListView(
                            characterId: characterId,
                            labelId: mailbox.labelId,
                            title: mailbox.title
                        )
                    } label: {
                        HStack {
                            switch mailbox {
                            case .inbox:
                                Image(systemName: "tray.and.arrow.down.fill")
                                    .foregroundColor(.gray)
                                    .frame(width: 24, height: 24)
                            case .sent:
                                Image(systemName: "tray.and.arrow.up.fill")
                                    .foregroundColor(.gray)
                                    .frame(width: 24, height: 24)
                            case .corporation:
                                Image("corporation")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            case .alliance:
                                Image("alliances")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            // case .spam:
                            //     Image("reprocess")
                            //         .resizable()
                            //         .frame(width: 24, height: 24)
                            }
                            Text(mailbox.title)
                            // Spacer()
                            // 显示未读数
                            //                            switch mailbox {
                            //                            case .inbox:
                            //                                if let unread = inboxUnread {
                            //                                    Text("\(unread)")
                            //                                        .foregroundColor(.blue)
                            //                                }
                            //                            case .corporation:
                            //                                if let unread = corpUnread {
                            //                                    Text("\(unread)")
                            //                                        .foregroundColor(.blue)
                            //                                }
                            //                            case .alliance:
                            //                                if let unread = allianceUnread {
                            //                                    Text("\(unread)")
                            //                                        .foregroundColor(.blue)
                            //                                }
                            //                            default:
                            //                                EmptyView()
                            //                            }
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("Main_EVE_Mail_Mailboxes", comment: ""))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_EVE_Mail_Title", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingComposeView = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingComposeView) {
            NavigationStack {
                CharacterComposeMailView(characterId: characterId)
            }
        }
        .onAppear {
            loadInitialDataIfNeeded()
        }
        .refreshable {
            Logger.info("用户触发刷新，强制更新数据")
            await loadUnreadCounts(forceRefresh: true)
            await viewModel.fetchMailLabels(characterId: characterId)
        }
    }

    private func loadUnreadCounts(forceRefresh: Bool = false) async {
        do {
            isLoading = true
            defer { isLoading = false }

            // 获取总未读数
            totalUnread = try await CharacterMailAPI.shared.getTotalUnreadCount(
                characterId: characterId, forceRefresh: forceRefresh
            )

            // 获取收件箱未读数
            inboxUnread = try await CharacterMailAPI.shared.getUnreadCount(
                characterId: characterId, labelId: 1, forceRefresh: forceRefresh
            )

            // 获取军团邮箱未读数
            corpUnread = try await CharacterMailAPI.shared.getUnreadCount(
                characterId: characterId, labelId: 4, forceRefresh: forceRefresh
            )

            // 获取联盟邮箱未读数
            allianceUnread = try await CharacterMailAPI.shared.getUnreadCount(
                characterId: characterId, labelId: 8, forceRefresh: forceRefresh
            )

            Logger.info(
                """
                邮件未读数统计\(forceRefresh ? "(强制刷新)" : ""):
                总未读: \(totalUnread ?? 0)
                收件箱: \(inboxUnread ?? 0)
                军团邮箱: \(corpUnread ?? 0)
                联盟邮箱: \(allianceUnread ?? 0)
                """)

        } catch {
            Logger.error("获取未读数失败: \(error)")
            self.error = error
        }
    }
}

// 邮箱类型枚举
enum MailboxType: CaseIterable {
    case inbox
    case sent
    case corporation
    case alliance
    // case spam

    var title: String {
        switch self {
        case .inbox: return NSLocalizedString("Main_EVE_Mail_Inbox", comment: "")
        case .sent: return NSLocalizedString("Main_EVE_Mail_Sent", comment: "")
        case .corporation: return NSLocalizedString("Main_EVE_Mail_Corporation", comment: "")
        case .alliance: return NSLocalizedString("Main_EVE_Mail_Alliance", comment: "")
        // case .spam: return NSLocalizedString("Main_EVE_Mail_Spam", comment: "")
        }
    }

    var labelId: Int {
        switch self {
        case .inbox: return 1
        case .sent: return 2
        case .corporation: return 4
        case .alliance: return 8
        // case .spam: return 16
        }
    }
}
