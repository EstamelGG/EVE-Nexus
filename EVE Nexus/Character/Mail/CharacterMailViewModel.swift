import Foundation

@MainActor
class CharacterMailViewModel: ObservableObject {
    @Published var mailList: [Mail] = []
    @Published var mailboxCounts: [MailboxType: Int] = [:]
    @Published var totalMailCount: Int?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var mailLabels: [MailLabel] = []
    @Published var selectedLabelMails: [Mail] = []
    
    // 邮件标签数据结构
    struct MailLabel: Identifiable {
        let id: Int
        let name: String
        let color: String?
        let unreadCount: Int
    }
    
    // 获取邮件标签列表
    func fetchMailLabels(characterId: Int) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // TODO: 实现实际的API调用
            // 这里暂时使用模拟数据
            mailLabels = getMockMailLabels()
        } catch {
            self.error = error
        }
    }
    
    // 获取特定标签下的邮件
    func fetchMailsByLabel(characterId: Int, labelId: Int) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // TODO: 实现实际的API调用
            // 这里暂时使用模拟数据
            selectedLabelMails = getMockMailsByLabel(labelId: labelId)
        } catch {
            self.error = error
        }
    }
    
    // 更新邮箱计数
    private func updateMailboxCounts() {
        // 模拟数据
        mailboxCounts = [
            .inbox: 5,
            .sent: 3,
            .corporation: 2,
            .alliance: 1,
            .spam: 0
        ]
        
        totalMailCount = mailList.count
    }
    
    // 获取模拟邮件标签数据
    private func getMockMailLabels() -> [MailLabel] {
        return [
            MailLabel(id: 1, name: "重要", color: "#FF0000", unreadCount: 3),
            MailLabel(id: 2, name: "军团事务", color: "#0000FF", unreadCount: 2),
            MailLabel(id: 3, name: "市场交易", color: "#00FF00", unreadCount: 0)
        ]
    }
    
    // 获取模拟标签邮件数据
    private func getMockMailsByLabel(labelId: Int) -> [Mail] {
        switch labelId {
        case 1:
            return [
                Mail(id: 1, subject: "重要：舰队集结", from: "舰队指挥官", date: Date(), isRead: false),
                Mail(id: 2, subject: "重要：军团政策更新", from: "军团长", date: Date().addingTimeInterval(-86400), isRead: false)
            ]
        case 2:
            return [
                Mail(id: 3, subject: "军团每周会议", from: "军团秘书", date: Date().addingTimeInterval(-172800), isRead: true)
            ]
        default:
            return []
        }
    }
} 
