import SwiftUI

struct CharacterMailView: View {
    let characterId: Int
    @StateObject private var viewModel = CharacterMailViewModel()
    @State private var selectedLabelId: Int? = nil
    
    var body: some View {
        List {
            // 全部邮件部分
            Section {
                NavigationLink {
                    Text("全部邮件视图") // 待实现
                } label: {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.gray)
                            .frame(width: 24, height: 24)
                        Text(NSLocalizedString("Main_EVE_Mail_All", comment: ""))
                        Spacer()
                        if let totalCount = viewModel.totalMailCount {
                            Text("\(totalCount)")
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            
            // 邮箱列表部分
            Section {
                ForEach(MailboxType.allCases, id: \.self) { mailbox in
                    NavigationLink {
                        Text("\(mailbox.title)视图") // 待实现
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
                            Spacer()
                            if let count = viewModel.mailboxCounts[mailbox] {
                                Text("\(count)")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("Main_EVE_Mail_Mailboxes", comment: ""))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .textCase(nil)
            }
            
            // 邮件标签部分
            Section {
                if viewModel.isLoading {
                    Text(NSLocalizedString("Main_EVE_Mail_Loading", comment: ""))
                        .foregroundColor(.gray)
                } else if let error = viewModel.error {
                    Text(NSLocalizedString("Main_EVE_Mail_Error", comment: ""))
                        .foregroundColor(.red)
                } else if viewModel.mailLabels.isEmpty {
                    Text(NSLocalizedString("Main_EVE_Mail_No_Labels", comment: ""))
                        .foregroundColor(.gray)
                } else {
                    ForEach(viewModel.mailLabels) { label in
                        NavigationLink {
                            MailLabelDetailView(characterId: characterId, label: label, viewModel: viewModel)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: label.color ?? "#808080"))
                                    .frame(width: 12, height: 12)
                                Text(label.name)
                                Spacer()
                                if label.unreadCount > 0 {
                                    Text("\(label.unreadCount)")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(NSLocalizedString("Main_EVE_Mail_Labels", comment: ""))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Main_EVE_Mail_Title", comment: ""))
        .task {
            await viewModel.fetchMailLabels(characterId: characterId)
        }
        .refreshable {
            await viewModel.fetchMailLabels(characterId: characterId)
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
