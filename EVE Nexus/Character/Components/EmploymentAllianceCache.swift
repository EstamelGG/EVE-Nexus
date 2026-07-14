import SwiftUI

@MainActor
final class EmploymentAllianceCache: ObservableObject {
    /// 军团ID -> 联盟历史
    private var corpAllianceHistories: [Int: [CorporationAllianceHistory]] = [:]
    /// 联盟ID -> 名称
    @Published var allianceNames: [Int: String] = [:]
    /// 联盟ID -> 图标
    @Published var allianceIcons: [Int: UIImage] = [:]
    /// 军团ID -> 图标
    @Published var corporationIcons: [Int: UIImage] = [:]

    /// 获取军团在指定时间的联盟信息
    /// - Returns: name 为 nil 表示联盟名称加载失败（网络错误等），调用方可重试或显示占位
    func getCorpAlliance(corporationId: Int, date: Date) async -> (id: Int, name: String?, icon: UIImage?)? {
        let allianceHistory = await getCorpAllianceHistory(corporationId: corporationId)

        guard let allianceId = findAllianceAtDate(allianceHistory: allianceHistory, date: date) else {
            return nil
        }

        let name = await getAllianceName(allianceId: allianceId)
        let icon = await getAllianceIcon(allianceId: allianceId)

        return (id: allianceId, name: name, icon: icon)
    }

    /// 获取军团的联盟历史（带缓存）
    private func getCorpAllianceHistory(corporationId: Int) async -> [CorporationAllianceHistory] {
        if let cached = corpAllianceHistories[corporationId] {
            return cached
        }

        if let history = try? await CorporationAPI.shared.fetchAllianceHistory(corporationId: corporationId) {
            corpAllianceHistories[corporationId] = history
            Logger.debug("缓存军团 \(corporationId) 的联盟历史，记录数: \(history.count)")
            return history
        }

        return []
    }

    /// 根据时间找到对应的联盟ID
    private func findAllianceAtDate(allianceHistory: [CorporationAllianceHistory], date: Date) -> Int? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        for record in allianceHistory {
            guard let recordDate = dateFormatter.date(from: record.start_date) else { continue }

            if recordDate <= date {
                return record.alliance_id
            }
        }

        return nil
    }

    /// 获取联盟名称（带缓存，失败时不缓存，返回 nil 以便下次重试）
    private func getAllianceName(allianceId: Int) async -> String? {
        if let cached = allianceNames[allianceId] {
            return cached
        }

        if let namesMap = try? await UniverseAPI.shared.getNamesWithFallback(ids: [allianceId]),
           let name = namesMap[allianceId]?.name
        {
            allianceNames[allianceId] = name
            Logger.debug("缓存联盟 \(allianceId) 的名称: \(name)")
            return name
        }

        return nil
    }

    /// 获取联盟图标（带缓存）
    private func getAllianceIcon(allianceId: Int) async -> UIImage? {
        if let cached = allianceIcons[allianceId] {
            return cached
        }

        if let icon = try? await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId) {
            allianceIcons[allianceId] = icon
            Logger.debug("缓存联盟 \(allianceId) 的图标")
            return icon
        }

        return nil
    }

    /// 获取军团图标（带缓存）
    func getCorporationIcon(corporationId: Int) async -> UIImage? {
        if let cached = corporationIcons[corporationId] {
            return cached
        }

        if let icon = try? await CorporationAPI.shared.fetchCorporationLogo(corporationId: corporationId) {
            corporationIcons[corporationId] = icon
            Logger.debug("缓存军团 \(corporationId) 的图标")
            return icon
        }

        return nil
    }
}
