import SwiftUI

@MainActor
final class EmploymentAllianceCache: ObservableObject {
    /// record_id → 当时联盟ID（nil 表示当时无联盟）
    @Published private(set) var recordAlliance: [Int: Int?] = [:]
    /// 联盟ID → 名称（不可解析的以 "Alliance {id}" 兜底）
    @Published private(set) var allianceNames: [Int: String] = [:]
    /// 军团/联盟ID → 图标
    @Published private(set) var icons: [Int: UIImage] = [:]
    /// 联盟史加载失败的记录（行显示重试态）
    @Published private(set) var failedRecordIds: Set<Int> = []

    private var isLoaded = false
    private var lastHistory: [CharacterEmploymentHistory] = []

    /// 行状态
    enum RowAllianceState {
        case loading
        case failed
        case none
        case alliance(Int)
    }

    func state(recordId: Int) -> RowAllianceState {
        if let allianceId = recordAlliance[recordId] {
            return allianceId.map { .alliance($0) } ?? .none
        }
        if failedRecordIds.contains(recordId) { return .failed }
        return .loading
    }

    /// 页面加载入口：只跑一次；force 供重试
    func loadIfNeeded(history: [CharacterEmploymentHistory], force: Bool = false) async {
        guard force || !isLoaded else { return }
        isLoaded = true
        lastHistory = history

        let records = Self.records(from: history)
        guard !records.isEmpty else { return }

        let uniqueCorpIds = Array(Set(records.map(\.corporationId)))

        // 军团图标与联盟史并行启动，互不依赖
        async let corpIconsTask: Void = fetchCorpIcons(uniqueCorpIds)

        // 1. 联盟史：到一份解析一份发布（快的行先显示，不被慢请求拖住）
        var resolved: [Int: Int?] = [:]
        var failed: Set<Int> = []
        await withTaskGroup(of: (Int, [CorporationAllianceHistory]?).self) { group in
            for corpId in uniqueCorpIds {
                group.addTask {
                    (
                        corpId,
                        try? await CorporationAPI.shared.fetchAllianceHistory(corporationId: corpId)
                    )
                }
            }
            for await (corpId, history) in group {
                let corpRecords = records.filter { $0.corporationId == corpId }
                guard let history else {
                    failed.formUnion(corpRecords.map(\.recordId))
                    failedRecordIds = failed
                    continue
                }
                for record in corpRecords {
                    resolved[record.recordId] = Self.findAlliance(
                        at: record.endDate ?? Date(), in: history
                    )
                }
                recordAlliance = resolved
            }
        }
        recordAlliance = resolved
        failedRecordIds = failed
        if !failed.isEmpty {
            // 有失败则允许下次进入/重试时重跑
            isLoaded = false
        }

        let allianceIds = Array(Set(resolved.values.compactMap { $0 }))
        guard !allianceIds.isEmpty else {
            await corpIconsTask
            return
        }

        // 2. 名称批量（限速关键，保持整批）与联盟图标并行
        async let namesTask: Void = fetchAllianceNames(allianceIds)
        async let allianceIconsTask: Void = fetchAllianceIcons(allianceIds)
        await namesTask
        await allianceIconsTask
        await corpIconsTask
    }

    /// 并发拉军团图标，到一张发一张（CDN）
    private func fetchCorpIcons(_ corpIds: [Int]) async {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for corpId in corpIds where icons[corpId] == nil {
                group.addTask {
                    (
                        corpId,
                        try? await CorporationAPI.shared.fetchCorporationLogo(corporationId: corpId)
                    )
                }
            }
            for await (corpId, image) in group {
                if let image {
                    icons[corpId] = image
                }
            }
        }
    }

    /// 联盟名称一次批量解析（避免逐行请求触发 ESI 限速；不可解析以 ID 兜底）
    private func fetchAllianceNames(_ allianceIds: [Int]) async {
        guard let namesMap = try? await UniverseAPI.shared.getNamesWithFallback(ids: allianceIds)
        else { return }

        var names = allianceNames
        for id in allianceIds {
            names[id] = namesMap[id]?.name ?? "Alliance \(id)"
        }
        allianceNames = names
    }

    /// 并发拉联盟图标，到一张发一张（CDN）
    private func fetchAllianceIcons(_ allianceIds: [Int]) async {
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for allianceId in allianceIds where icons[allianceId] == nil {
                group.addTask {
                    (
                        allianceId,
                        try? await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId)
                    )
                }
            }
            for await (allianceId, image) in group {
                if let image {
                    icons[allianceId] = image
                }
            }
        }
    }

    /// 重试（失败行点击触发），重跑上次的历史
    func retry() async {
        failedRecordIds.removeAll()
        await loadIfNeeded(history: lastHistory, force: true)
    }

    // MARK: - 工具

    /// 由雇佣记录构建查询需求（结束时间 = 更新一条记录的开始时间，与行视图一致）
    static func records(from history: [CharacterEmploymentHistory]) -> [(
        recordId: Int, corporationId: Int, endDate: Date?
    )] {
        history.enumerated().compactMap { index, record in
            guard parseDate(record.start_date) != nil else { return nil }
            let endDate = index > 0 ? parseDate(history[index - 1].start_date) : nil
            return (recordId: record.record_id, corporationId: record.corporation_id, endDate: endDate)
        }
    }

    /// 按时间点在联盟史中回溯当时的联盟（记录按开始时间倒序）
    private static func findAlliance(at date: Date, in history: [CorporationAllianceHistory]) -> Int? {
        for record in history {
            guard let recordDate = parseDate(record.start_date) else { continue }
            if recordDate <= date {
                return record.alliance_id
            }
        }
        return nil
    }

    static func parseDate(_ dateString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        return dateFormatter.date(from: dateString)
    }
}
