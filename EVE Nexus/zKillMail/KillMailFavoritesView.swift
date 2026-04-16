import SwiftUI

// MARK: - UserDefaults 收藏存储

struct FavoriteKillMailRecord: Codable, Equatable {
    let killmailId: Int
    let hash: String
}

final class KillMailFavoritesStore: ObservableObject {
    static let shared = KillMailFavoritesStore()

    private let defaultsKey = "KillMailFavoriteKMRecords"

    @Published private(set) var records: [FavoriteKillMailRecord] = []

    private init() {
        records = Self.loadFromDefaults(key: defaultsKey)
    }

    private static func loadFromDefaults(key: String) -> [FavoriteKillMailRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FavoriteKillMailRecord].self, from: data)
        else { return [] }
        return decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func isFavorite(killmailId: Int) -> Bool {
        records.contains { $0.killmailId == killmailId }
    }

    func add(killmailId: Int, hash: String) {
        guard !isFavorite(killmailId: killmailId) else { return }
        var next = records
        next.insert(FavoriteKillMailRecord(killmailId: killmailId, hash: hash), at: 0)
        records = next
        persist()
    }

    func remove(killmailId: Int) {
        records.removeAll { $0.killmailId == killmailId }
        persist()
    }

    func toggle(killmailId: Int, hash: String) {
        if isFavorite(killmailId: killmailId) {
            remove(killmailId: killmailId)
        } else {
            add(killmailId: killmailId, hash: hash)
        }
    }
}

// MARK: - 收藏夹列表

@MainActor
private final class KillMailFavoritesListModel: ObservableObject {
    @Published private(set) var entries: [KillMailEntry] = []
    @Published private(set) var shipInfoMap: [Int: (name: String, iconFileName: String)] = [:]
    @Published private(set) var allianceIconMap: [Int: UIImage] = [:]
    @Published private(set) var corporationIconMap: [Int: UIImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let databaseManager = DatabaseManager.shared

    func reload(records: [FavoriteKillMailRecord]) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard !records.isEmpty else {
            entries = []
            shipInfoMap = [:]
            allianceIconMap = [:]
            corporationIconMap = [:]
            return
        }

        var idToEntry: [Int: ZKBKillMailEntry] = [:]
        await withTaskGroup(of: (Int, ZKBKillMailEntry?).self) { group in
            for rec in records {
                group.addTask {
                    do {
                        let e = try await zKbToolAPI.shared.fetchZKBKillMailByID(killmailId: rec.killmailId)
                        return (rec.killmailId, e)
                    } catch {
                        Logger.error("收藏夹: 拉取 zkill 失败 killmail_id=\(rec.killmailId) \(error)")
                        return (rec.killmailId, nil)
                    }
                }
            }
            for await (id, zkb) in group {
                if let zkb { idToEntry[id] = zkb }
            }
        }

        let orderedZKB: [ZKBKillMailEntry] = records.compactMap { idToEntry[$0.killmailId] }
        guard !orderedZKB.isEmpty else {
            entries = []
            shipInfoMap = [:]
            allianceIconMap = [:]
            corporationIconMap = [:]
            return
        }

        do {
            let entities = try await KillMailDataConverter.shared.fetchKillMailListEntities(zkbEntries: orderedZKB)
            // 按战报发生时间降序：越接近现在越靠前
            let orderedEntities = entities.sorted {
                if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
                return $0.killmailId > $1.killmailId
            }

            var idx = 0
            let newEntries: [KillMailEntry] = orderedEntities.map { entity in
                defer { idx += 1 }
                return KillMailEntry(id: idx, entity: entity)
            }

            let shipIds = orderedEntities.map(\.shipTypeId)
            let shipInfo = getShipInfo(for: shipIds)
            let (allianceIcons, corporationIcons) = await loadOrganizationIcons(for: orderedEntities)

            entries = newEntries
            shipInfoMap = shipInfo
            allianceIconMap = allianceIcons
            corporationIconMap = corporationIcons
        } catch {
            errorMessage = error.localizedDescription
            entries = []
        }
    }

    private func getShipInfo(for typeIds: [Int]) -> [Int: (name: String, iconFileName: String)] {
        guard !typeIds.isEmpty else { return [:] }
        let placeholders = String(repeating: "?,", count: typeIds.count).dropLast()
        let query = """
            SELECT type_id, name, icon_filename
            FROM types
            WHERE type_id IN (\(placeholders))
        """
        let result = databaseManager.executeQuery(query, parameters: typeIds)
        var infoMap: [Int: (name: String, iconFileName: String)] = [:]
        if case let .success(rows) = result {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String
                {
                    infoMap[typeId] = (name: name, iconFileName: iconFileName)
                }
            }
        }
        return infoMap
    }

    private func loadOrganizationIcons(for entities: [KillMailListEntity]) async -> (
        [Int: UIImage], [Int: UIImage]
    ) {
        var allianceIcons: [Int: UIImage] = [:]
        var corporationIcons: [Int: UIImage] = [:]

        for entity in entities {
            if let allyId = entity.allianceId, allyId > 0 {
                if allianceIcons[allyId] == nil,
                   let icon = await loadSingleOrganizationIcon(type: "alliance", id: allyId)
                {
                    allianceIcons[allyId] = icon
                }
            } else if entity.corporationId > 0 {
                let corpId = entity.corporationId
                if corporationIcons[corpId] == nil,
                   let icon = await loadSingleOrganizationIcon(type: "corporation", id: corpId)
                {
                    corporationIcons[corpId] = icon
                }
            }
        }

        return (allianceIcons, corporationIcons)
    }

    private func loadSingleOrganizationIcon(type: String, id: Int) async -> UIImage? {
        do {
            switch type {
            case "alliance":
                return try await AllianceAPI.shared.fetchAllianceLogo(allianceID: id, size: 64)
            case "corporation":
                return try await CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: id, size: 64
                )
            default:
                return nil
            }
        } catch {
            Logger.error("收藏夹: 加载\(type)图标失败 ID=\(id) \(error)")
            return nil
        }
    }
}

struct BRKillMailFavoritesView: View {
    let characterId: Int
    let eveCharacter: EVECharacterInfo?

    @ObservedObject private var favoritesStore = KillMailFavoritesStore.shared
    @StateObject private var listModel = KillMailFavoritesListModel()
    /// 与「我的战斗记录」一致：仅首次进入本页时拉取列表，从详情返回不重复请求
    @State private var hasLoadedFavoritesList = false

    var body: some View {
        List {
            if listModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if let err = listModel.errorMessage {
                Text(err)
                    .foregroundColor(.red)
            } else if favoritesStore.records.isEmpty {
                Text(NSLocalizedString("KillMail_Favorites_Empty", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else if listModel.entries.isEmpty {
                Text(NSLocalizedString("KillMail_Favorites_Load_Failed", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(listModel.entries) { entry in
                    let entity = entry.entity
                    let shipInfo = listModel.shipInfoMap[entity.shipTypeId] ?? (
                        name: String(
                            format: NSLocalizedString("KillMail_Unknown_Item", comment: ""),
                            entity.shipTypeId
                        ),
                        iconFileName: DatabaseConfig.defaultItemIcon
                    )
                    BRKillMailCell(
                        entity: entity,
                        shipInfo: shipInfo,
                        allianceIcon: entity.allianceId.flatMap { listModel.allianceIconMap[$0] },
                        corporationIcon: listModel.corporationIconMap[entity.corporationId],
                        characterId: characterId,
                        searchResult: nil,
                        character: eveCharacter
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("KillMail_Favorites_Title", comment: ""))
        .refreshable {
            await listModel.reload(records: favoritesStore.records)
        }
        .onAppear {
            guard !hasLoadedFavoritesList else { return }
            hasLoadedFavoritesList = true
            Task {
                await listModel.reload(records: favoritesStore.records)
            }
        }
        .onChange(of: favoritesStore.records) { _, newRecords in
            Task {
                await listModel.reload(records: newRecords)
            }
        }
    }
}
