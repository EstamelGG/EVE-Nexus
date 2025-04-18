import Foundation

@MainActor
class CharacterMailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var mailLabels: [MailLabel] = []
    @Published var mailLists: [EVEMailList] = []

    // 邮件标签数据结构
    struct MailLabel: Identifiable {
        let id: Int
        let name: String
        let color: String?
        let unreadCount: Int

        init(apiLabel: EVE_Nexus.MailLabel) {
            id = apiLabel.label_id
            name = apiLabel.name
            color = apiLabel.color
            unreadCount = apiLabel.unread_count ?? 0
        }
    }

    // 获取邮件标签列表
    func fetchMailLabels(characterId: Int) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 获取邮件标签
            let response = try await CharacterMailAPI.shared.fetchMailLabels(
                characterId: characterId)
            mailLabels = response.labels.map { MailLabel(apiLabel: $0) }

            // 获取邮件订阅列表
            let lists = try await CharacterMailAPI.shared.fetchMailLists(characterId: characterId)
            mailLists = lists

            Logger.info("成功获取 \(lists.count) 个邮件订阅列表")
        } catch {
            Logger.error("获取邮件标签和订阅列表失败: \(error)")
            self.error = error
        }
    }
}
