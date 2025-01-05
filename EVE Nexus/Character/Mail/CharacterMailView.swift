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
                            case .spam:
                                Image("reprocess")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                            }
                            Text(mailbox.title)
                            //Spacer()
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
                    .font(.system(size: 18, weight: .bold))
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
            NavigationView {
                CharacterComposeMailView(characterId: characterId)
            }
        }
        .task {
            await loadUnreadCounts()
            await viewModel.fetchMailLabels(characterId: characterId)
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
            totalUnread = try await CharacterMailAPI.shared.getTotalUnreadCount(characterId: characterId, forceRefresh: forceRefresh)
            
            // 获取收件箱未读数
            inboxUnread = try await CharacterMailAPI.shared.getUnreadCount(characterId: characterId, labelId: 1, forceRefresh: forceRefresh)
            
            // 获取军团邮箱未读数
            corpUnread = try await CharacterMailAPI.shared.getUnreadCount(characterId: characterId, labelId: 4, forceRefresh: forceRefresh)
            
            // 获取联盟邮箱未读数
            allianceUnread = try await CharacterMailAPI.shared.getUnreadCount(characterId: characterId, labelId: 8, forceRefresh: forceRefresh)
            
            Logger.info("""
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

// 邮件标签详情视图
struct MailLabelDetailView: View {
    let characterId: Int
    let label: CharacterMailViewModel.MailLabel
    @ObservedObject var viewModel: CharacterMailViewModel
    
    var body: some View {
        List {
            if viewModel.isLoading {
                Text(NSLocalizedString("Main_EVE_Mail_Loading", comment: ""))
                    .foregroundColor(.gray)
            } else if viewModel.error != nil {
                Text(NSLocalizedString("Main_EVE_Mail_Error", comment: ""))
                    .foregroundColor(.red)
            } else if viewModel.selectedLabelMails.isEmpty {
                Text(NSLocalizedString("Main_EVE_Mail_No_Mail", comment: ""))
                    .foregroundColor(.gray)
            } else {
                ForEach(viewModel.selectedLabelMails) { mail in
                    NavigationLink {
                        Text("邮件详情视图") // 待实现
                    } label: {
                        MailRowView(mail: mail)
                    }
                }
            }
        }
        .navigationTitle(label.name)
        .task {
            await viewModel.fetchMailsByLabel(characterId: characterId, labelId: label.id)
        }
        .refreshable {
            await viewModel.fetchMailsByLabel(characterId: characterId, labelId: label.id)
        }
    }
}

// 邮箱类型枚举
enum MailboxType: CaseIterable {
    case inbox
    case sent
    case corporation
    case alliance
    case spam
    
    var title: String {
        switch self {
        case .inbox: return NSLocalizedString("Main_EVE_Mail_Inbox", comment: "")
        case .sent: return NSLocalizedString("Main_EVE_Mail_Sent", comment: "")
        case .corporation: return NSLocalizedString("Main_EVE_Mail_Corporation", comment: "")
        case .alliance: return NSLocalizedString("Main_EVE_Mail_Alliance", comment: "")
        case .spam: return NSLocalizedString("Main_EVE_Mail_Spam", comment: "")
        }
    }
    
    var labelId: Int {
        switch self {
        case .inbox: return 1
        case .sent: return 2
        case .corporation: return 4
        case .alliance: return 8
        case .spam: return 16
        }
    }
}

// 邮件行视图
struct MailRowView: View {
    let mail: Mail
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(mail.subject)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(mail.formattedDate)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            HStack {
                Text(mail.from)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                
                if !mail.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// 邮件数据模型
struct Mail: Identifiable {
    let id: Int
    let subject: String
    let from: String
    let date: Date
    let isRead: Bool
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// Color扩展，用于解析十六进制颜色
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// 预览
#Preview {
    NavigationView {
        CharacterMailView(characterId: 123456)
    }
} 
