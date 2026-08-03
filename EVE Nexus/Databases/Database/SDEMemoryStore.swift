import Foundation

/// 八语本地化文本；查找时按当前数据库语言解析，语言切换无需重扫表。
struct LocalizedText: Equatable {
    let de: String
    let en: String
    let es: String
    let fr: String
    let ja: String
    let ko: String
    let ru: String
    let zh: String

    /// 用同一字符串填充八语（ESI/联盟名等只有单语种时）
    static func filled(with value: String) -> LocalizedText {
        LocalizedText(
            de: value, en: value, es: value, fr: value,
            ja: value, ko: value, ru: value, zh: value
        )
    }

    /// 从行字典读取 `{prefix}de_name`… 或裸 `de_name`（prefix 为空）
    static func from(row: [String: Any], prefix: String = "") -> LocalizedText {
        func v(_ lang: String) -> String {
            let key = prefix.isEmpty ? "\(lang)_name" : "\(prefix)\(lang)_name"
            return (row[key] as? String) ?? ""
        }
        return LocalizedText(
            de: v("de"), en: v("en"), es: v("es"), fr: v("fr"),
            ja: v("ja"), ko: v("ko"), ru: v("ru"), zh: v("zh")
        )
    }

    /// dogma unit 列：`unit_de_name` …
    static func units(from row: [String: Any]) -> LocalizedText {
        func v(_ lang: String) -> String {
            (row["unit_\(lang)_name"] as? String) ?? ""
        }
        return LocalizedText(
            de: v("de"), en: v("en"), es: v("es"), fr: v("fr"),
            ja: v("ja"), ko: v("ko"), ru: v("ru"), zh: v("zh")
        )
    }

    func resolved(_ languageCode: String? = nil) -> String {
        let lang = SDELanguage.columnPrefix(from: languageCode)
        let primary: String
        switch lang {
        case "de": primary = de
        case "es": primary = es
        case "fr": primary = fr
        case "ja": primary = ja
        case "ko": primary = ko
        case "ru": primary = ru
        case "zh": primary = zh
        default: primary = en
        }
        if !primary.isEmpty { return primary }
        if !en.isEmpty { return en }
        return [zh, de, fr, ja, ko, ru, es].first { !$0.isEmpty } ?? ""
    }

    /// resolved() 结果为空时返回 nil（用于可选展示场景）
    func resolvedNonEmpty(_ languageCode: String? = nil) -> String? {
        let s = resolved(languageCode)
        return s.isEmpty ? nil : s
    }

    /// 任意语种名称包含 query（大小写不敏感）即命中
    func matchesSearch(_ query: String) -> Bool {
        let q = query.lowercased()
        guard !q.isEmpty else { return false }
        return allValues.contains {
            !$0.isEmpty && $0.lowercased().contains(q)
        }
    }

    /// 任意语种名称与 query 全等（大小写不敏感）
    func matchesExact(_ query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return allValues.contains {
            !$0.isEmpty && $0.caseInsensitiveCompare(query) == .orderedSame
        }
    }

    var allValues: [String] {
        [de, en, es, fr, ja, ko, ru, zh]
    }

    /// `t.name_search LIKE ?`：name_search 为 TEMP VIEW 中以 char(31) 拼接的全语种名称列
    static let typeLangNameLikeSQL = "(t.name_search LIKE ?)"

    static func typeLangNameLikeParams(_ searchText: String) -> [Any] {
        ["%\(searchText)%"]
    }

    /// 精确匹配：分隔符夹逼 name_search（某语种名称与关键词全等），用于精确匹配优先排序
    static let typeLangNameExactSQL = "(t.name_search LIKE ?)"

    static func typeLangNameExactParams(_ searchText: String) -> [Any] {
        ["%\u{1F}\(searchText)\u{1F}%"]
    }

    static let typeLangNameColumns = [
        "de_name", "en_name", "es_name", "fr_name", "ja_name", "ko_name", "ru_name", "zh_name",
    ]
}

/// SDE 常用小表 / types 瘦字段内存索引。在 `ItemInfoMap.initializeCache`（loadDatabase）时重建。
/// 本地化字段存全语种，`name` / `displayName` 等为按当前语言动态解析。
enum SDEMemoryStore {
    struct TypeInfo {
        let categoryID: Int
        let groupID: Int?
        let metaGroupID: Int?
        let marketGroupID: Int?
        let names: LocalizedText
        let iconFilename: String
        let bpcIconFilename: String?
        let volume: Double
        let capacity: Double
        let mass: Double
        let repackagedVolume: Double?
        let descID: String?
        let variationParentTypeID: Int?

        var name: String {
            names.resolved()
        }

        var enName: String {
            names.en
        }
    }

    struct CategoryInfo {
        let id: Int
        let names: LocalizedText
        let published: Bool
        let iconFilename: String

        var name: String {
            names.resolved()
        }

        var enName: String {
            names.en
        }
    }

    struct GroupInfo {
        let id: Int
        let names: LocalizedText
        let categoryID: Int
        let published: Bool
        let iconFilename: String

        var name: String {
            names.resolved()
        }

        var enName: String {
            names.en
        }
    }

    struct MarketGroupInfo {
        let id: Int
        let names: LocalizedText
        let iconName: String
        let parentGroupID: Int?
        let show: Bool

        var name: String {
            names.resolved()
        }
    }

    struct DogmaAttributeInfo {
        let id: Int
        let categoryID: Int?
        let name: String // attribute_key，语言无关
        let displayNames: LocalizedText
        let iconID: Int
        let iconFilename: String
        let unitID: Int?
        let unitNames: LocalizedText
        let highIsGood: Bool
        let stackable: Bool
        let defaultValue: Double

        var displayName: String? {
            displayNames.resolvedNonEmpty()
        }
    }

    /// 舰载机能力（已按当前语言解析 name/description）
    struct FighterAbilityInfo {
        let slot: Int
        let abilityID: Int
        let name: String
        let description: String
        let cooldownSeconds: Int?
        let chargeCount: Int?
        let rearmTimeSeconds: Int?
        let iconFilename: String
    }

    struct FactionInfo {
        let id: Int
        let names: LocalizedText
        let iconName: String

        var name: String {
            names.resolved()
        }
    }

    struct NPCCorporationInfo {
        let id: Int
        let names: LocalizedText
        let iconFilename: String
        let factionID: Int?
        let militiaFaction: Int?

        var name: String {
            names.resolved()
        }

        var enName: String {
            names.en
        }

        var zhName: String {
            names.zh
        }
    }

    struct StationInfo {
        let id: Int
        let stationTypeID: Int?
        let regionID: Int?
        let solarSystemID: Int?
        let names: LocalizedText
        let security: Double?

        var name: String {
            names.resolved()
        }
    }

    /// 动态物品映射（突变系统）：applicable_type + type_id(突变质体) → resulting_type(突变产物)
    struct DynamicItemMapping {
        let applicableType: Int
        let typeID: Int
        let resultingType: Int
    }

    private(set) static var types: [Int: TypeInfo] = [:]
    private(set) static var categories: [Int: CategoryInfo] = [:]
    private(set) static var groups: [Int: GroupInfo] = [:]
    private(set) static var groupsByCategory: [Int: [GroupInfo]] = [:]
    private(set) static var metaGroupNames: [Int: LocalizedText] = [:]
    private(set) static var marketGroups: [Int: MarketGroupInfo] = [:]
    private(set) static var dogmaAttributes: [Int: DogmaAttributeInfo] = [:]
    private(set) static var regionNames: [Int: LocalizedText] = [:]
    private(set) static var solarSystemNames: [Int: LocalizedText] = [:]
    /// 星系 ID → 星域 ID 映射（从 universe 表加载）
    private(set) static var systemRegionIDs: [Int: Int] = [:]
    private(set) static var constellationNames: [Int: LocalizedText] = [:]
    private(set) static var factions: [Int: FactionInfo] = [:]
    private(set) static var divisionNames: [Int: LocalizedText] = [:]
    private(set) static var oreColors: [Int: String] = [:]
    private(set) static var originToCompressed: [Int: Int] = [:]
    private(set) static var compressedToOrigin: [Int: Int] = [:]
    private(set) static var npcCorporations: [Int: NPCCorporationInfo] = [:]
    private(set) static var stations: [Int: StationInfo] = [:]
    private(set) static var typeEffectIDs: [Int: [Int]] = [:]
    /// 反向索引：parentTypeID → 子变体 typeID 列表（不含 parent 本身）
    private(set) static var variationsByParent: [Int: [Int]] = [:]
    /// 动态物品映射三个维度的索引 + resulting_type 去重集合
    private(set) static var dynamicMappingsByApplicable: [Int: [DynamicItemMapping]] = [:]
    private(set) static var dynamicMappingsByResulting: [Int: [DynamicItemMapping]] = [:]
    private(set) static var dynamicMappingsByTypeID: [Int: [DynamicItemMapping]] = [:]
    private(set) static var dynamicResultingTypeIDs: Set<Int> = []
    /// 舰载机能力：typeID → 按 slot 升序的能力列表
    private(set) static var fighterAbilities: [Int: [FighterAbilityInfo]] = [:]

    static func loadAll(databaseManager: DatabaseManager) {
        loadTypes(databaseManager)
        loadCategories(databaseManager)
        loadGroups(databaseManager)
        loadMetaGroups(databaseManager)
        loadDogmaAttributes(databaseManager)
        loadMarketGroups(databaseManager)
        loadRegions(databaseManager)
        loadSolarSystems(databaseManager)
        loadConstellations(databaseManager)
        loadFactions(databaseManager)
        loadDivisions(databaseManager)
        loadOreColors(databaseManager)
        loadCompressibleTypes(databaseManager)
        loadNPCCorporations(databaseManager)
        loadStations(databaseManager)
        loadTypeEffects(databaseManager)
        loadDynamicItemMappings(databaseManager)
        loadFighterAbilities(databaseManager)

        Logger.info(
            "SDEMemoryStore 已加载 types=\(types.count) categories=\(categories.count) groups=\(groups.count) meta=\(metaGroupNames.count) market=\(marketGroups.count) dogma=\(dogmaAttributes.count) regions=\(regionNames.count) systems=\(solarSystemNames.count) constellations=\(constellationNames.count) factions=\(factions.count) divisions=\(divisionNames.count) ores=\(oreColors.count) compress=\(originToCompressed.count) npcCorps=\(npcCorporations.count) stations=\(stations.count) typeEffects=\(typeEffectIDs.count) dynMappings=\(dynamicResultingTypeIDs.count) fighterAbilities=\(fighterAbilities.count)"
        )
    }

    // MARK: - Lookups

    static func type(for typeID: Int) -> TypeInfo? {
        types[typeID]
    }

    /// 解析变体树顶层父物品 ID（无父物品时返回自身）
    static func resolveVariationParent(for typeID: Int) -> Int {
        var currentID = typeID
        var seen = Set<Int>() // 防御循环引用
        while let info = type(for: currentID),
              let parentID = info.variationParentTypeID,
              !seen.contains(currentID)
        {
            seen.insert(currentID)
            currentID = parentID
        }
        return currentID
    }

    /// 变体数量（含自身），O(1) 字典查找
    static func variationsCount(for typeID: Int) -> Int {
        let parentID = resolveVariationParent(for: typeID)
        let childCount = variationsByParent[parentID]?.count ?? 0
        return childCount + 1
    }

    static func category(for id: Int) -> CategoryInfo? {
        categories[id]
    }

    static func group(for id: Int) -> GroupInfo? {
        groups[id]
    }

    static func groups(inCategory categoryID: Int) -> [GroupInfo] {
        groupsByCategory[categoryID] ?? []
    }

    static func metaGroupName(for id: Int) -> String? {
        metaGroupNames[id]?.resolvedNonEmpty()
    }

    /// Catalog 等需要完整 meta 名字典时按当前语言物化
    static var localizedMetaGroupNames: [Int: String] {
        Dictionary(uniqueKeysWithValues: metaGroupNames.compactMap { id, text in
            let name = text.resolved()
            return name.isEmpty ? nil : (id, name)
        })
    }

    static func marketGroup(for id: Int) -> MarketGroupInfo? {
        marketGroups[id]
    }

    static func dogmaAttribute(for id: Int) -> DogmaAttributeInfo? {
        dogmaAttributes[id]
    }

    static func fighterAbilities(for typeID: Int) -> [FighterAbilityInfo] {
        fighterAbilities[typeID] ?? []
    }

    static func regionName(for id: Int) -> String? {
        regionNames[id]?.resolvedNonEmpty()
    }

    static func solarSystemName(for id: Int) -> String? {
        solarSystemNames[id]?.resolvedNonEmpty()
    }

    static func constellationName(for id: Int) -> String? {
        constellationNames[id]?.resolvedNonEmpty()
    }

    static func faction(for id: Int) -> FactionInfo? {
        factions[id]
    }

    static func oreColor(for typeID: Int) -> String? {
        oreColors[typeID]
    }

    static func npcCorporation(for id: Int) -> NPCCorporationInfo? {
        npcCorporations[id]
    }

    static func station(for id: Int) -> StationInfo? {
        stations[id]
    }

    static func effectIDs(forType typeID: Int) -> [Int] {
        typeEffectIDs[typeID] ?? []
    }

    // MARK: - Dynamic Item Mappings Lookups

    /// applicable_type → 所有映射（用于查询可突变产物、所需突变质体）
    static func dynamicMappings(applicableTo typeID: Int) -> [DynamicItemMapping] {
        dynamicMappingsByApplicable[typeID] ?? []
    }

    /// resulting_type → 所有映射（用于查询突变来源）
    static func dynamicMappings(resultingIn typeID: Int) -> [DynamicItemMapping] {
        dynamicMappingsByResulting[typeID] ?? []
    }

    /// type_id（突变质体）→ 所有映射（用于查询该质体可应用的物品及产物）
    static func dynamicMappings(forTypeID typeID: Int) -> [DynamicItemMapping] {
        dynamicMappingsByTypeID[typeID] ?? []
    }

    /// applicable_type + 突变质体 type_id → 突变产物 resulting_type
    static func dynamicResultingType(applicableType: Int, typeID: Int) -> Int? {
        dynamicMappingsByApplicable[applicableType]?.first { $0.typeID == typeID }?.resultingType
    }

    // MARK: - Loaders（读全语种列，不依赖 TEMP VIEW 的当前 name）

    private static let nameColumns = """
    de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name
    """

    /// 通用 LocalizedText 表加载：`SELECT <idCol>, 八语列 FROM <table>`
    private static func loadLocalizedTable(
        _ db: DatabaseManager, table: String, idColumn: String,
        estimatedCount: Int = 0, into target: inout [Int: LocalizedText]
    ) {
        var cache: [Int: LocalizedText] = [:]
        if estimatedCount > 0 { cache.reserveCapacity(estimatedCount) }
        if case let .success(rows) = db.executeQuery(
            "SELECT \(idColumn), \(nameColumns) FROM \(table)", useCache: false
        ) {
            for row in rows {
                if let id = row[idColumn] as? Int {
                    cache[id] = LocalizedText.from(row: row)
                }
            }
        }
        target = cache
    }

    /// SQLite 可能以 Double 或 Int 返回数值：优先 Double，否则尝试 Int
    private static func doubleOrInt(_ row: [String: Any], _ key: String) -> Double? {
        (row[key] as? Double) ?? (row[key] as? Int).map(Double.init)
    }

    /// 同上，但缺失时回退为 0
    private static func doubleOrIntZero(_ row: [String: Any], _ key: String) -> Double {
        doubleOrInt(row, key) ?? 0
    }

    private static func loadTypes(_ db: DatabaseManager) {
        let query = """
            SELECT type_id, categoryID, groupID, metaGroupID, marketGroupID,
                   icon_filename, bpc_icon_filename, volume, capacity, mass,
                   repackaged_volume, desc_id, variationParentTypeID,
                   \(nameColumns)
            FROM types
        """
        var cache: [Int: TypeInfo] = [:]
        cache.reserveCapacity(65536)
        if case let .success(rows) = db.executeQuery(query, useCache: false) {
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let categoryID = row["categoryID"] as? Int
                else { continue }
                let rawIcon = (row["icon_filename"] as? String) ?? ""
                let rawBpc = (row["bpc_icon_filename"] as? String) ?? ""
                let rawDesc = (row["desc_id"] as? String) ?? ""
                cache[typeID] = TypeInfo(
                    categoryID: categoryID,
                    groupID: row["groupID"] as? Int,
                    metaGroupID: row["metaGroupID"] as? Int,
                    marketGroupID: row["marketGroupID"] as? Int,
                    names: LocalizedText.from(row: row),
                    iconFilename: rawIcon.isEmpty ? IconManager.defaultItemIcon : rawIcon,
                    bpcIconFilename: rawBpc.isEmpty ? nil : rawBpc,
                    volume: doubleOrIntZero(row, "volume"),
                    capacity: doubleOrIntZero(row, "capacity"),
                    mass: doubleOrIntZero(row, "mass"),
                    repackagedVolume: doubleOrInt(row, "repackaged_volume"),
                    descID: rawDesc.isEmpty ? nil : rawDesc,
                    variationParentTypeID: row["variationParentTypeID"] as? Int
                )
            }
        }
        types = cache

        // 构建变体反向索引：parentTypeID → [子 typeID]
        var reverse: [Int: [Int]] = [:]
        reverse.reserveCapacity(cache.count / 4)
        for (typeID, info) in cache {
            if let parentID = info.variationParentTypeID {
                reverse[parentID, default: []].append(typeID)
            }
        }
        variationsByParent = reverse
    }

    private static func loadCategories(_ db: DatabaseManager) {
        let query = """
            SELECT category_id, published, icon_filename, \(nameColumns)
            FROM categories
        """
        var cache: [Int: CategoryInfo] = [:]
        if case let .success(rows) = db.executeQuery(query, useCache: false) {
            for row in rows {
                guard let id = row["category_id"] as? Int else { continue }
                let rawIcon = (row["icon_filename"] as? String) ?? ""
                cache[id] = CategoryInfo(
                    id: id,
                    names: LocalizedText.from(row: row),
                    published: (row["published"] as? Int ?? 0) != 0,
                    iconFilename: rawIcon.isEmpty ? IconManager.defaultIcon : rawIcon
                )
            }
        }
        categories = cache
    }

    private static func loadGroups(_ db: DatabaseManager) {
        let query = """
            SELECT group_id, categoryID, published, icon_filename, \(nameColumns)
            FROM groups
        """
        var cache: [Int: GroupInfo] = [:]
        var byCategory: [Int: [GroupInfo]] = [:]
        if case let .success(rows) = db.executeQuery(query, useCache: false) {
            for row in rows {
                guard let id = row["group_id"] as? Int,
                      let categoryID = row["categoryID"] as? Int
                else { continue }
                let rawIcon = (row["icon_filename"] as? String) ?? ""
                let info = GroupInfo(
                    id: id,
                    names: LocalizedText.from(row: row),
                    categoryID: categoryID,
                    published: (row["published"] as? Int ?? 0) != 0,
                    iconFilename: rawIcon.isEmpty ? IconManager.defaultIcon : rawIcon
                )
                cache[id] = info
                byCategory[categoryID, default: []].append(info)
            }
        }
        for key in byCategory.keys {
            byCategory[key]?.sort { $0.id < $1.id }
        }
        groups = cache
        groupsByCategory = byCategory
    }

    private static func loadMetaGroups(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "metaGroups", idColumn: "metagroup_id", into: &metaGroupNames)
    }

    private static func loadDogmaAttributes(_ db: DatabaseManager) {
        let query = """
            SELECT attribute_id, categoryID, attribute_key, iconID, icon_filename,
                   unitID, highIsGood, stackable, defaultValue,
                   \(nameColumns),
                   unit_de_name, unit_en_name, unit_es_name, unit_fr_name,
                   unit_ja_name, unit_ko_name, unit_ru_name, unit_zh_name
            FROM dogmaAttributes
        """
        var cache: [Int: DogmaAttributeInfo] = [:]
        cache.reserveCapacity(4096)
        if case let .success(rows) = db.executeQuery(query, useCache: false) {
            for row in rows {
                guard let id = row["attribute_id"] as? Int else { continue }
                let rawIcon = (row["icon_filename"] as? String) ?? ""
                cache[id] = DogmaAttributeInfo(
                    id: id,
                    categoryID: row["categoryID"] as? Int,
                    name: (row["attribute_key"] as? String) ?? (row["name"] as? String) ?? "",
                    displayNames: LocalizedText.from(row: row),
                    iconID: (row["iconID"] as? Int) ?? 0,
                    iconFilename: rawIcon,
                    unitID: row["unitID"] as? Int,
                    unitNames: LocalizedText.units(from: row),
                    highIsGood: (row["highIsGood"] as? Int) == 1,
                    stackable: (row["stackable"] as? Int) == 1,
                    defaultValue: (row["defaultValue"] as? Double) ?? 0.0
                )
            }
        }
        dogmaAttributes = cache
    }

    private static func loadMarketGroups(_ db: DatabaseManager) {
        let query = """
            SELECT group_id, icon_name, parentgroup_id, show, \(nameColumns)
            FROM marketGroups
        """
        var cache: [Int: MarketGroupInfo] = [:]
        if case let .success(rows) = db.executeQuery(query, useCache: false) {
            for row in rows {
                guard let id = row["group_id"] as? Int else { continue }
                cache[id] = MarketGroupInfo(
                    id: id,
                    names: LocalizedText.from(row: row),
                    iconName: (row["icon_name"] as? String) ?? "",
                    parentGroupID: row["parentgroup_id"] as? Int,
                    show: (row["show"] as? Int ?? 1) != 0
                )
            }
        }
        marketGroups = cache
    }

    private static func loadRegions(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "regions", idColumn: "regionID", into: &regionNames)
    }

    private static func loadSolarSystems(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "solarsystems", idColumn: "solarSystemID", estimatedCount: 16384, into: &solarSystemNames)

        // 加载星系 → 星域映射（用于市场地点类型判断）
        if case let .success(rows) = db.executeQuery(
            "SELECT solarsystem_id, region_id FROM universe", useCache: false
        ) {
            for row in rows {
                if let systemID = row["solarsystem_id"] as? Int,
                   let regionID = row["region_id"] as? Int
                {
                    systemRegionIDs[systemID] = regionID
                }
            }
        }
    }

    private static func loadConstellations(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "constellations", idColumn: "constellationID", into: &constellationNames)
    }

    private static func loadFactions(_ db: DatabaseManager) {
        var cache: [Int: FactionInfo] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT id, iconName, \(nameColumns) FROM factions", useCache: false
        ) {
            for row in rows {
                guard let id = row["id"] as? Int else { continue }
                cache[id] = FactionInfo(
                    id: id,
                    names: LocalizedText.from(row: row),
                    iconName: (row["iconName"] as? String) ?? ""
                )
            }
        }
        factions = cache
    }

    private static func loadDivisions(_ db: DatabaseManager) {
        loadLocalizedTable(db, table: "divisions", idColumn: "division_id", into: &divisionNames)
    }

    private static func loadOreColors(_ db: DatabaseManager) {
        var cache: [Int: String] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT type_id, hex_color FROM ore_colors", useCache: false
        ) {
            for row in rows {
                if let id = row["type_id"] as? Int, let color = row["hex_color"] as? String {
                    cache[id] = color
                }
            }
        }
        oreColors = cache
    }

    private static func loadCompressibleTypes(_ db: DatabaseManager) {
        var forward: [Int: Int] = [:]
        var reverse: [Int: Int] = [:]
        if case let .success(rows) = db.executeQuery(
            "SELECT origin, compressed FROM compressible_types", useCache: false
        ) {
            for row in rows {
                guard let origin = row["origin"] as? Int,
                      let compressed = row["compressed"] as? Int
                else { continue }
                forward[origin] = compressed
                reverse[compressed] = origin
            }
        }
        originToCompressed = forward
        compressedToOrigin = reverse
    }

    private static func loadNPCCorporations(_ db: DatabaseManager) {
        var cache: [Int: NPCCorporationInfo] = [:]
        if case let .success(rows) = db.executeQuery(
            """
            SELECT corporation_id, icon_filename, faction_id, militia_faction, \(nameColumns)
            FROM npcCorporations
            """,
            useCache: false
        ) {
            for row in rows {
                guard let id = row["corporation_id"] as? Int else { continue }
                let rawIcon = (row["icon_filename"] as? String) ?? ""
                cache[id] = NPCCorporationInfo(
                    id: id,
                    names: LocalizedText.from(row: row),
                    iconFilename: rawIcon.isEmpty ? IconManager.defaultIcon : rawIcon,
                    factionID: row["faction_id"] as? Int,
                    militiaFaction: row["militia_faction"] as? Int
                )
            }
        }
        npcCorporations = cache
    }

    private static func loadStations(_ db: DatabaseManager) {
        var cache: [Int: StationInfo] = [:]
        cache.reserveCapacity(8192)
        if case let .success(rows) = db.executeQuery(
            """
            SELECT stationID, stationTypeID, regionID, solarSystemID, security, \(nameColumns)
            FROM stations
            """,
            useCache: false
        ) {
            for row in rows {
                guard let id = row["stationID"] as? Int else { continue }
                cache[id] = StationInfo(
                    id: id,
                    stationTypeID: row["stationTypeID"] as? Int,
                    regionID: row["regionID"] as? Int,
                    solarSystemID: row["solarSystemID"] as? Int,
                    names: LocalizedText.from(row: row),
                    security: doubleOrInt(row, "security")
                )
            }
        }
        stations = cache
    }

    private static func loadTypeEffects(_ db: DatabaseManager) {
        var cache: [Int: [Int]] = [:]
        cache.reserveCapacity(32768)
        if case let .success(rows) = db.executeQuery(
            "SELECT type_id, effect_id FROM typeEffects", useCache: false
        ) {
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let effectID = row["effect_id"] as? Int
                else { continue }
                cache[typeID, default: []].append(effectID)
            }
        }
        typeEffectIDs = cache
    }

    private static func loadFighterAbilities(_ db: DatabaseManager) {
        var cache: [Int: [FighterAbilityInfo]] = [:]
        if case let .success(rows) = db.executeQuery(
            """
            SELECT type_id, slot, ability_id, name, description,
                   cooldown_seconds, charge_count, rearm_time_seconds, icon_filename
            FROM fighterAbilities
            ORDER BY type_id, slot
            """,
            useCache: false
        ) {
            for row in rows {
                guard let typeID = row["type_id"] as? Int,
                      let slot = row["slot"] as? Int,
                      let abilityID = row["ability_id"] as? Int
                else { continue }
                cache[typeID, default: []].append(
                    FighterAbilityInfo(
                        slot: slot,
                        abilityID: abilityID,
                        name: (row["name"] as? String) ?? "",
                        description: (row["description"] as? String) ?? "",
                        cooldownSeconds: row["cooldown_seconds"] as? Int,
                        chargeCount: row["charge_count"] as? Int,
                        rearmTimeSeconds: row["rearm_time_seconds"] as? Int,
                        iconFilename: (row["icon_filename"] as? String) ?? ""
                    )
                )
            }
        }
        fighterAbilities = cache
    }

    private static func loadDynamicItemMappings(_ db: DatabaseManager) {
        var byApplicable: [Int: [DynamicItemMapping]] = [:]
        var byResulting: [Int: [DynamicItemMapping]] = [:]
        var byTypeID: [Int: [DynamicItemMapping]] = [:]
        var resultingIDs = Set<Int>()

        if case let .success(rows) = db.executeQuery(
            "SELECT applicable_type, type_id, resulting_type FROM dynamic_item_mappings",
            useCache: false
        ) {
            for row in rows {
                guard let applicableType = row["applicable_type"] as? Int,
                      let typeID = row["type_id"] as? Int,
                      let resultingType = row["resulting_type"] as? Int
                else { continue }
                let mapping = DynamicItemMapping(
                    applicableType: applicableType,
                    typeID: typeID,
                    resultingType: resultingType
                )
                byApplicable[applicableType, default: []].append(mapping)
                byResulting[resultingType, default: []].append(mapping)
                byTypeID[typeID, default: []].append(mapping)
                resultingIDs.insert(resultingType)
            }
        }
        dynamicMappingsByApplicable = byApplicable
        dynamicMappingsByResulting = byResulting
        dynamicMappingsByTypeID = byTypeID
        dynamicResultingTypeIDs = resultingIDs
    }
}
