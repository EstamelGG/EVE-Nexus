import Foundation

@MainActor
class CharacterMailViewModel: ObservableObject {
    @Published var mailList: [Mail] = []
    @Published var mailboxCounts: [MailboxType: Int] = [:]
    @Published var totalMailCount: Int?
    @Published var isLoading = false
    @Published var error: Error?
    
    // 获取邮件列表
    func fetchMails(characterId: Int) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // TODO: 实现实际的API调用
            // 这里暂时使用模拟数据
            mailList = getMockMails()
            updateMailboxCounts()
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
    
    // 获取模拟数据
    private func getMockMails() -> [Mail] {
        return [
            Mail(id: 1, subject: "欢迎来到EVE", from: "CCP", date: Date(), isRead: true),
            Mail(id: 2, subject: "军团会议通知", from: "军团长", date: Date().addingTimeInterval(-86400), isRead: false),
            Mail(id: 3, subject: "舰队作战报告", from: "舰队指挥官", date: Date().addingTimeInterval(-172800), isRead: true)
        ]
    }
} 
