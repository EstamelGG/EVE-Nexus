import Foundation

@MainActor
class CharacterMailViewModel: ObservableObject {
    @Published var mailboxCounts: [MailboxType: Int] = [:]
    @Published var isLoading = false
    @Published var error: Error?
    @Published var mailLabels: [MailLabel] = []
    @Published var selectedLabelMails: [Mail] = []
    @Published var mailLists: [EVEMailList] = []
    
    // 邮件标签数据结构
    struct MailLabel: Identifiable {
        let id: Int
        let name: String
        let color: String?
        let unreadCount: Int
        
        init(apiLabel: EVE_Nexus.MailLabel) {
            self.id = apiLabel.label_id
            self.name = apiLabel.name
            self.color = apiLabel.color
            self.unreadCount = apiLabel.unread_count ?? 0
        }
    }
    
    // 获取邮件标签列表
    func fetchMailLabels(characterId: Int) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 获取邮件标签
            let response = try await CharacterMailAPI.shared.fetchMailLabels(characterId: characterId)
            self.mailLabels = response.labels.map { MailLabel(apiLabel: $0) }
            
            // 获取邮件订阅列表
            let lists = try await CharacterMailAPI.shared.fetchMailLists(characterId: characterId)
            self.mailLists = lists
            
            Logger.info("成功获取 \(lists.count) 个邮件订阅列表")
        } catch {
            Logger.error("获取邮件标签和订阅列表失败: \(error)")
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
        }
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
