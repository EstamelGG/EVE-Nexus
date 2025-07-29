import Foundation

// 日历事件详情数据模型
struct CalendarEventDetail: Codable, Identifiable {
    let date: String
    let duration: Int
    let event_id: Int
    let importance: Int
    let owner_id: Int
    let owner_name: String
    let owner_type: String
    let response: String
    let text: String
    let title: String
    
    var id: Int { event_id }
    
    // 将字符串日期转换为Date对象
    var eventDate: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: date)
    }
    
    // 获取持续时间（分钟）
    var durationInMinutes: Int {
        return duration
    }
    
    // 移除HTML标签的文本内容
    var cleanText: String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
    
    // 根据owner_type获取对应的RecipientType
    var ownerType: MailRecipient.RecipientType {
        switch owner_type.lowercased() {
        case "character":
            return .character
        case "corporation":
            return .corporation
        case "alliance":
            return .alliance
        default:
            return .character
        }
    }
}

class CharacterCalendarDetailAPI {
    static let shared = CharacterCalendarDetailAPI()
    private init() {}

    // 获取角色日历事件详情
    func fetchEventDetail(characterId: Int, eventId: Int) async throws -> CalendarEventDetail {
        let urlString = "https://esi.evetech.net/characters/\(characterId)/calendar/\(eventId)/?datasource=tranquility"
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        // 从网络获取数据
        let data = try await NetworkManager.shared.fetchDataWithToken(
            from: url,
            characterId: characterId
        )

        let eventDetail = try JSONDecoder().decode(CalendarEventDetail.self, from: data)
        Logger.info("成功获取事件详情 - 角色ID: \(characterId), 事件ID: \(eventId)")
        return eventDetail
    }
} 