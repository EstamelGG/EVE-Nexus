import Foundation

// 日历事件数据模型
struct CalendarEvent: Codable, Identifiable {
    let event_date: String
    let event_id: Int
    let event_response: String
    let importance: Int
    let title: String
    
    var id: Int { event_id }
    
    // 将字符串日期转换为Date对象
    var date: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: event_date)
    }
}

class CharacterCalendarAPI {
    static let shared = CharacterCalendarAPI()
    private let databaseManager = CharacterDatabaseManager.shared
    private init() {}

    // 保存日历数据到数据库（仅作为缓存，网络失败时使用）
    private func saveCalendarToDatabase(characterId: Int, events: [CalendarEvent]) -> Bool {
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(events)

            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                Logger.error("日历数据JSON编码失败")
                return false
            }

            let query = """
                    INSERT OR REPLACE INTO calendar_cache (
                        character_id, calendar_data, last_updated
                    ) VALUES (?, ?, datetime('now'))
                """

            if case let .error(error) = databaseManager.executeQuery(
                query,
                parameters: [
                    characterId,
                    jsonString
                ]
            ) {
                Logger.error("保存日历缓存失败: \(error)")
                return false
            }

            Logger.info("成功保存日历缓存到数据库 - 角色ID: \(characterId)")
            return true
        } catch {
            Logger.error("保存日历缓存失败: \(error)")
            return false
        }
    }

    // 从数据库加载日历缓存（仅在网络失败时使用）
    private func loadCalendarFromDatabase(characterId: Int) -> [CalendarEvent]? {
        let query = """
                SELECT calendar_data FROM calendar_cache 
                WHERE character_id = ?
            """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [characterId]),
            rows.count > 0,
            let row = rows.first,
            let jsonString = row["calendar_data"] as? String,
            let jsonData = jsonString.data(using: .utf8)
        {
            do {
                let decoder = JSONDecoder()
                let events = try decoder.decode([CalendarEvent].self, from: jsonData)
                Logger.info("成功从缓存加载日历数据 - 角色ID: \(characterId)")
                return events
            } catch {
                Logger.error("解析日历缓存数据失败: \(error)")
                return nil
            }
        }
        return nil
    }

    // 获取角色日历事件 (支持分页)
    func fetchCharacterCalendar(characterId: Int, fromEventId: Int? = nil) async throws -> [CalendarEvent] {
        var urlString = "https://esi.evetech.net/characters/\(characterId)/calendar/?datasource=tranquility"
        if let fromEventId = fromEventId {
            urlString += "&from_event=\(fromEventId)"
        }
        
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        do {
            // 尝试从网络获取数据
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url,
                characterId: characterId
            )

            let events = try JSONDecoder().decode([CalendarEvent].self, from: data)
            
            // 只有在获取第一页数据时才覆盖缓存，分页数据需要追加
            if fromEventId == nil {
                if saveCalendarToDatabase(characterId: characterId, events: events) {
                    Logger.info("成功缓存日历数据 - 角色ID: \(characterId)")
                }
            }

            Logger.info("成功获取日历数据 - 角色ID: \(characterId), 事件数量: \(events.count), 起始事件ID: \(fromEventId ?? 0)")
            return events
            
        } catch {
            // 网络请求失败，只有在获取第一页时才尝试从缓存加载
            if fromEventId == nil {
                Logger.warning("网络请求失败，尝试从缓存加载日历数据 - 角色ID: \(characterId), 错误: \(error)")
                
                if let cachedEvents = loadCalendarFromDatabase(characterId: characterId) {
                    Logger.info("使用缓存的日历数据 - 角色ID: \(characterId), 事件数量: \(cachedEvents.count)")
                    return cachedEvents
                }
            }
            
            // 缓存也没有数据，抛出原始错误
            Logger.error("无法获取日历数据 - 角色ID: \(characterId), fromEventId: \(fromEventId ?? 0)")
            throw error
        }
    }
} 