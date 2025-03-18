import SwiftUI

struct LanguageMapView: View {
    // State 属性
    @State private var exactMatchResults: [(id: Int, names: [String: String])] = []  // 完全匹配结果
    @State private var prefixMatchResults: [(id: Int, names: [String: String])] = []  // 前缀匹配结果
    @State private var fuzzyMatchResults: [(id: Int, names: [String: String])] = []  // 模糊匹配结果
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearchActive = false
    @State private var hasTypeIdMatch = false

    let availableLanguages = [
        "de": "Deutsch:",
        "en": "English:",
        "es": "Español:",
        "fr": "Français:",
        "ja": "日本語:",
        "ko": "한国語:",
        "ru": "Русский:",
        "zh": "中文:",
    ]

    var body: some View {
        VStack {
            // 搜索结果或提示信息
            if exactMatchResults.isEmpty && prefixMatchResults.isEmpty && fuzzyMatchResults.isEmpty
            {
                // 显示提示信息
                VStack(spacing: 16) {
                    Text(
                        NSLocalizedString(
                            "Main_Language_Map_Supported_Search_Objects", comment: "支持的搜索对象：")
                    )
                    .font(.headline)
                    .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_1", comment: "1. 物品（舰船、装备、空间实体等）")
                        )
                        .foregroundColor(.secondary)
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_2", comment: "2. 星系、星座、星域名")
                        )
                        .foregroundColor(.secondary)
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_3", comment: "3. NPC势力名、军团名")
                        )
                        .foregroundColor(.secondary)
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_4", comment: "4. 物品 TypeID")
                        )
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // 搜索结果列表
                List {
                    // 完全匹配结果
                    if !exactMatchResults.isEmpty {
                        Section(
                            header: Text(
                                NSLocalizedString("Main_Language_Map_Exact_Match", comment: "完全匹配")
                            )
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(nil)
                        ) {
                            ForEach(exactMatchResults, id: \.id) { result in
                                ResultRow(result: result, availableLanguages: availableLanguages)
                            }
                        }
                    }

                    // 前缀匹配结果
                    if !prefixMatchResults.isEmpty {
                        Section(
                            header: Text(
                                NSLocalizedString("Main_Language_Map_Prefix_Match", comment: "前缀匹配")
                            )
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(nil)
                        ) {
                            ForEach(prefixMatchResults, id: \.id) { result in
                                ResultRow(result: result, availableLanguages: availableLanguages)
                            }
                        }
                    }

                    // 模糊匹配结果
                    if !fuzzyMatchResults.isEmpty {
                        Section(
                            header: Text(
                                NSLocalizedString("Main_Language_Map_Fuzzy_Match", comment: "模糊匹配")
                            )
                            .fontWeight(.bold)
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .textCase(nil)
                        ) {
                            ForEach(fuzzyMatchResults, id: \.id) { result in
                                ResultRow(result: result, availableLanguages: availableLanguages)
                            }
                        }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
        .onChange(of: searchText) { _, newValue in
            // 取消之前的搜索任务
            searchTask?.cancel()

            if newValue.isEmpty {
                exactMatchResults = []
                prefixMatchResults = []
                fuzzyMatchResults = []
                hasTypeIdMatch = false
                return
            }

            // 创建新的搜索任务
            searchTask = Task {
                // 延迟500毫秒
                try? await Task.sleep(nanoseconds: 500_000_000)

                // 如果任务被取消，直接返回
                if Task.isCancelled { return }

                // 在主线程执行搜索
                await MainActor.run {
                    performSearch()
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Language_Map", comment: ""))
    }

    // 提取结果行视图为单独的组件
    private struct ResultRow: View {
        let result: (id: Int, names: [String: String])
        let availableLanguages: [String: String]

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(availableLanguages.keys).sorted(), id: \.self) { langCode in
                    if let name = result.names[langCode] {
                        HStack {
                            Text(availableLanguages[langCode] ?? langCode)
                                .foregroundColor(.gray)
                                .frame(width: 80, alignment: .trailing)
                            Text(name).textSelection(.enabled)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func createQueryParameters(
        searchText: String, startPattern: String, searchPattern: String
    ) -> [Any] {
        // 第一部分：完全匹配参数 (优先级 1)
        let exactMatchParams = Array(repeating: searchText, count: 8)
        // 第二部分：前缀匹配参数 (优先级 2)
        let prefixMatchParams = Array(repeating: startPattern, count: 8)
        // 第三部分：完全匹配参数 (用于 NOT IN 子句)
        let exactMatchParamsForNotIn = Array(repeating: searchText, count: 8)
        // 第四部分：模糊匹配参数 (优先级 3)
        let fuzzyMatchParams = Array(repeating: searchPattern, count: 8)
        // 第五部分：完全匹配参数 (用于第二个 NOT IN 子句)
        let exactMatchParamsForSecondNotIn = Array(repeating: searchText, count: 8)
        // 第六部分：前缀匹配参数 (用于第二个 NOT IN 子句)
        let prefixMatchParamsForNotIn = Array(repeating: startPattern, count: 8)

        // 按照 SQL 查询中的参数顺序组合
        let allParams =
            exactMatchParams  // WHERE 子句的完全匹配
            + prefixMatchParams  // 第一个 UNION ALL 的前缀匹配
            + exactMatchParamsForNotIn  // 第一个 NOT IN 子句的完全匹配
            + fuzzyMatchParams  // 第二个 UNION ALL 的模糊匹配
            + exactMatchParamsForSecondNotIn  // 第二个 NOT IN 子句的完全匹配
            + prefixMatchParamsForNotIn  // 第二个 NOT IN 子句的前缀匹配
        return allParams
    }

    private func performSearch() {
        guard !searchText.isEmpty else {
            exactMatchResults = []
            prefixMatchResults = []
            fuzzyMatchResults = []
            hasTypeIdMatch = false
            return
        }

        let searchPattern = "%\(searchText)%"
        let startPattern = "\(searchText)%"
        var exact: [(id: Int, names: [String: String])] = []
        var prefix: [(id: Int, names: [String: String])] = []
        var fuzzy: [(id: Int, names: [String: String])] = []

        // 重置hasTypeIdMatch
        hasTypeIdMatch = false

        // 检查searchText是否可以转换为整数（用于type_id搜索）
        let typeIdToSearch = Int(searchText)

        // 创建查询参数
        let queryParams = createQueryParameters(
            searchText: searchText, startPattern: startPattern, searchPattern: searchPattern
        )

        // 搜索物品 - 使用单一SQL语句，通过CASE WHEN实现条件逻辑
        let typesQuery = """
                SELECT DISTINCT type_id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name, 
                       CASE 
                           WHEN type_id = \(typeIdToSearch ?? -1) THEN 0
                           WHEN de_name = ? COLLATE NOCASE OR en_name = ? COLLATE NOCASE OR es_name = ? COLLATE NOCASE 
                                OR fr_name = ? COLLATE NOCASE OR ja_name = ? COLLATE NOCASE OR ko_name = ? COLLATE NOCASE 
                                OR ru_name = ? COLLATE NOCASE OR zh_name = ? COLLATE NOCASE THEN 1
                           WHEN de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                                OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ? THEN 2
                           ELSE 3
                       END as priority,
                       LENGTH(en_name) as name_length
                FROM types
                WHERE (
                      -- type_id精确匹配（如果searchText是数字）
                      (\(typeIdToSearch != nil ? "type_id = \(typeIdToSearch!)" : "0=1"))
                      -- 名称完全匹配
                      OR de_name = ? COLLATE NOCASE OR en_name = ? COLLATE NOCASE OR es_name = ? COLLATE NOCASE 
                      OR fr_name = ? COLLATE NOCASE OR ja_name = ? COLLATE NOCASE OR ko_name = ? COLLATE NOCASE 
                      OR ru_name = ? COLLATE NOCASE OR zh_name = ? COLLATE NOCASE
                      -- 名称前缀匹配
                      OR de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                      OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?
                      -- 名称模糊匹配
                      OR de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                      OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?
                )
                ORDER BY priority, name_length, en_name
            """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            typesQuery, parameters: queryParams, useCache: false
        ) {
            for row in rows {
                var names: [String: String] = [:]
                if let deName = row["de_name"] as? String { names["de"] = deName }
                if let enName = row["en_name"] as? String { names["en"] = enName }
                if let esName = row["es_name"] as? String { names["es"] = esName }
                if let frName = row["fr_name"] as? String { names["fr"] = frName }
                if let jaName = row["ja_name"] as? String { names["ja"] = jaName }
                if let koName = row["ko_name"] as? String { names["ko"] = koName }
                if let ruName = row["ru_name"] as? String { names["ru"] = ruName }
                if let zhName = row["zh_name"] as? String { names["zh"] = zhName }
                if let typeId = row["type_id"] as? Int {
                    let priority = row["priority"] as? Int ?? 3
                    let result = (id: typeId, names: names)

                    // 如果是通过type_id搜索到的结果（priority为0），标记hasTypeIdMatch为true
                    if priority == 0 {
                        hasTypeIdMatch = true
                    }

                    switch priority {
                    case 0: exact.append(result)  // type_id精确匹配的结果归类于"完全匹配"
                    case 1: exact.append(result)
                    case 2: prefix.append(result)
                    case 3: fuzzy.append(result)
                    default: break
                    }
                }
            }
        }

        // 搜索星系
        let systemsQuery = """
                SELECT DISTINCT solarSystemID, solarSystemName_de, solarSystemName_en, solarSystemName_es, solarSystemName_fr,
                       solarSystemName_ja, solarSystemName_ko, solarSystemName_ru, solarSystemName_zh, 1 as priority,
                       LENGTH(solarSystemName_en) as name_length
                FROM solarsystems
                WHERE solarSystemName_de = ? COLLATE NOCASE OR solarSystemName_en = ? COLLATE NOCASE 
                OR solarSystemName_es = ? COLLATE NOCASE OR solarSystemName_fr = ? COLLATE NOCASE 
                OR solarSystemName_ja = ? COLLATE NOCASE OR solarSystemName_ko = ? COLLATE NOCASE 
                OR solarSystemName_ru = ? COLLATE NOCASE OR solarSystemName_zh = ? COLLATE NOCASE
                UNION ALL
                SELECT DISTINCT solarSystemID, solarSystemName_de, solarSystemName_en, solarSystemName_es, solarSystemName_fr,
                       solarSystemName_ja, solarSystemName_ko, solarSystemName_ru, solarSystemName_zh, 2 as priority,
                       LENGTH(solarSystemName_en) as name_length
                FROM solarsystems
                WHERE (solarSystemName_de LIKE ? OR solarSystemName_en LIKE ? OR solarSystemName_es LIKE ?
                OR solarSystemName_fr LIKE ? OR solarSystemName_ja LIKE ? OR solarSystemName_ko LIKE ?
                OR solarSystemName_ru LIKE ? OR solarSystemName_zh LIKE ?)
                AND solarSystemID NOT IN (
                    SELECT solarSystemID FROM solarsystems
                    WHERE solarSystemName_de = ? COLLATE NOCASE OR solarSystemName_en = ? COLLATE NOCASE 
                    OR solarSystemName_es = ? COLLATE NOCASE OR solarSystemName_fr = ? COLLATE NOCASE 
                    OR solarSystemName_ja = ? COLLATE NOCASE OR solarSystemName_ko = ? COLLATE NOCASE 
                    OR solarSystemName_ru = ? COLLATE NOCASE OR solarSystemName_zh = ? COLLATE NOCASE
                )
                UNION ALL
                SELECT DISTINCT solarSystemID, solarSystemName_de, solarSystemName_en, solarSystemName_es, solarSystemName_fr,
                       solarSystemName_ja, solarSystemName_ko, solarSystemName_ru, solarSystemName_zh, 3 as priority,
                       LENGTH(solarSystemName_en) as name_length
                FROM solarsystems
                WHERE (solarSystemName_de LIKE ? OR solarSystemName_en LIKE ? OR solarSystemName_es LIKE ?
                OR solarSystemName_fr LIKE ? OR solarSystemName_ja LIKE ? OR solarSystemName_ko LIKE ?
                OR solarSystemName_ru LIKE ? OR solarSystemName_zh LIKE ?)
                AND solarSystemID NOT IN (
                    SELECT solarSystemID FROM solarsystems
                    WHERE solarSystemName_de = ? COLLATE NOCASE OR solarSystemName_en = ? COLLATE NOCASE 
                    OR solarSystemName_es = ? COLLATE NOCASE OR solarSystemName_fr = ? COLLATE NOCASE 
                    OR solarSystemName_ja = ? COLLATE NOCASE OR solarSystemName_ko = ? COLLATE NOCASE 
                    OR solarSystemName_ru = ? COLLATE NOCASE OR solarSystemName_zh = ? COLLATE NOCASE
                    OR solarSystemName_de LIKE ? OR solarSystemName_en LIKE ? OR solarSystemName_es LIKE ?
                    OR solarSystemName_fr LIKE ? OR solarSystemName_ja LIKE ? OR solarSystemName_ko LIKE ?
                    OR solarSystemName_ru LIKE ? OR solarSystemName_zh LIKE ?
                )
                ORDER BY priority, name_length, solarSystemName_en
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            systemsQuery, parameters: queryParams, useCache: false
        ) {
            for row in rows {
                var names: [String: String] = [:]
                if let deName = row["solarSystemName_de"] as? String { names["de"] = deName }
                if let enName = row["solarSystemName_en"] as? String { names["en"] = enName }
                if let esName = row["solarSystemName_es"] as? String { names["es"] = esName }
                if let frName = row["solarSystemName_fr"] as? String { names["fr"] = frName }
                if let jaName = row["solarSystemName_ja"] as? String { names["ja"] = jaName }
                if let koName = row["solarSystemName_ko"] as? String { names["ko"] = koName }
                if let ruName = row["solarSystemName_ru"] as? String { names["ru"] = ruName }
                if let zhName = row["solarSystemName_zh"] as? String { names["zh"] = zhName }
                if let systemId = row["solarSystemID"] as? Int {
                    let priority = row["priority"] as? Int ?? 3
                    let result = (id: systemId, names: names)
                    switch priority {
                    case 1: exact.append(result)
                    case 2: prefix.append(result)
                    case 3: fuzzy.append(result)
                    default: break
                    }
                }
            }
        }

        // 搜索星座
        let constellationsQuery = """
                SELECT DISTINCT constellationID, constellationName_de, constellationName_en, constellationName_es, constellationName_fr,
                       constellationName_ja, constellationName_ko, constellationName_ru, constellationName_zh, 1 as priority,
                       LENGTH(constellationName_en) as name_length
                FROM constellations
                WHERE constellationName_de = ? COLLATE NOCASE OR constellationName_en = ? COLLATE NOCASE 
                OR constellationName_es = ? COLLATE NOCASE OR constellationName_fr = ? COLLATE NOCASE 
                OR constellationName_ja = ? COLLATE NOCASE OR constellationName_ko = ? COLLATE NOCASE 
                OR constellationName_ru = ? COLLATE NOCASE OR constellationName_zh = ? COLLATE NOCASE
                UNION ALL
                SELECT DISTINCT constellationID, constellationName_de, constellationName_en, constellationName_es, constellationName_fr,
                       constellationName_ja, constellationName_ko, constellationName_ru, constellationName_zh, 2 as priority,
                       LENGTH(constellationName_en) as name_length
                FROM constellations
                WHERE (constellationName_de LIKE ? OR constellationName_en LIKE ? OR constellationName_es LIKE ?
                OR constellationName_fr LIKE ? OR constellationName_ja LIKE ? OR constellationName_ko LIKE ?
                OR constellationName_ru LIKE ? OR constellationName_zh LIKE ?)
                AND constellationID NOT IN (
                    SELECT constellationID FROM constellations
                    WHERE constellationName_de = ? COLLATE NOCASE OR constellationName_en = ? COLLATE NOCASE 
                    OR constellationName_es = ? COLLATE NOCASE OR constellationName_fr = ? COLLATE NOCASE 
                    OR constellationName_ja = ? COLLATE NOCASE OR constellationName_ko = ? COLLATE NOCASE 
                    OR constellationName_ru = ? COLLATE NOCASE OR constellationName_zh = ? COLLATE NOCASE
                )
                UNION ALL
                SELECT DISTINCT constellationID, constellationName_de, constellationName_en, constellationName_es, constellationName_fr,
                       constellationName_ja, constellationName_ko, constellationName_ru, constellationName_zh, 3 as priority,
                       LENGTH(constellationName_en) as name_length
                FROM constellations
                WHERE (constellationName_de LIKE ? OR constellationName_en LIKE ? OR constellationName_es LIKE ?
                OR constellationName_fr LIKE ? OR constellationName_ja LIKE ? OR constellationName_ko LIKE ?
                OR constellationName_ru LIKE ? OR constellationName_zh LIKE ?)
                AND constellationID NOT IN (
                    SELECT constellationID FROM constellations
                    WHERE constellationName_de = ? COLLATE NOCASE OR constellationName_en = ? COLLATE NOCASE 
                    OR constellationName_es = ? COLLATE NOCASE OR constellationName_fr = ? COLLATE NOCASE 
                    OR constellationName_ja = ? COLLATE NOCASE OR constellationName_ko = ? COLLATE NOCASE 
                    OR constellationName_ru = ? COLLATE NOCASE OR constellationName_zh = ? COLLATE NOCASE
                    OR constellationName_de LIKE ? OR constellationName_en LIKE ? OR constellationName_es LIKE ?
                    OR constellationName_fr LIKE ? OR constellationName_ja LIKE ? OR constellationName_ko LIKE ?
                    OR constellationName_ru LIKE ? OR constellationName_zh LIKE ?
                )
                ORDER BY priority, name_length, constellationName_en
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            constellationsQuery, parameters: queryParams, useCache: false
        ) {
            for row in rows {
                var names: [String: String] = [:]
                if let deName = row["constellationName_de"] as? String { names["de"] = deName }
                if let enName = row["constellationName_en"] as? String { names["en"] = enName }
                if let esName = row["constellationName_es"] as? String { names["es"] = esName }
                if let frName = row["constellationName_fr"] as? String { names["fr"] = frName }
                if let jaName = row["constellationName_ja"] as? String { names["ja"] = jaName }
                if let koName = row["constellationName_ko"] as? String { names["ko"] = koName }
                if let ruName = row["constellationName_ru"] as? String { names["ru"] = ruName }
                if let zhName = row["constellationName_zh"] as? String { names["zh"] = zhName }
                if let constellationId = row["constellationID"] as? Int {
                    let priority = row["priority"] as? Int ?? 3
                    let result = (id: constellationId, names: names)
                    switch priority {
                    case 1: exact.append(result)
                    case 2: prefix.append(result)
                    case 3: fuzzy.append(result)
                    default: break
                    }
                }
            }
        }

        // 搜索星域
        let regionsQuery = """
                SELECT DISTINCT regionID, regionName_de, regionName_en, regionName_es, regionName_fr,
                       regionName_ja, regionName_ko, regionName_ru, regionName_zh, 1 as priority,
                       LENGTH(regionName_en) as name_length
                FROM regions
                WHERE regionName_de = ? COLLATE NOCASE OR regionName_en = ? COLLATE NOCASE 
                OR regionName_es = ? COLLATE NOCASE OR regionName_fr = ? COLLATE NOCASE 
                OR regionName_ja = ? COLLATE NOCASE OR regionName_ko = ? COLLATE NOCASE 
                OR regionName_ru = ? COLLATE NOCASE OR regionName_zh = ? COLLATE NOCASE
                UNION ALL
                SELECT DISTINCT regionID, regionName_de, regionName_en, regionName_es, regionName_fr,
                       regionName_ja, regionName_ko, regionName_ru, regionName_zh, 2 as priority,
                       LENGTH(regionName_en) as name_length
                FROM regions
                WHERE (regionName_de LIKE ? OR regionName_en LIKE ? OR regionName_es LIKE ?
                OR regionName_fr LIKE ? OR regionName_ja LIKE ? OR regionName_ko LIKE ?
                OR regionName_ru LIKE ? OR regionName_zh LIKE ?)
                AND regionID NOT IN (
                    SELECT regionID FROM regions
                    WHERE regionName_de = ? COLLATE NOCASE OR regionName_en = ? COLLATE NOCASE 
                    OR regionName_es = ? COLLATE NOCASE OR regionName_fr = ? COLLATE NOCASE 
                    OR regionName_ja = ? COLLATE NOCASE OR regionName_ko = ? COLLATE NOCASE 
                    OR regionName_ru = ? COLLATE NOCASE OR regionName_zh = ? COLLATE NOCASE
                )
                UNION ALL
                SELECT DISTINCT regionID, regionName_de, regionName_en, regionName_es, regionName_fr,
                       regionName_ja, regionName_ko, regionName_ru, regionName_zh, 3 as priority,
                       LENGTH(regionName_en) as name_length
                FROM regions
                WHERE (regionName_de LIKE ? OR regionName_en LIKE ? OR regionName_es LIKE ?
                OR regionName_fr LIKE ? OR regionName_ja LIKE ? OR regionName_ko LIKE ?
                OR regionName_ru LIKE ? OR regionName_zh LIKE ?)
                AND regionID NOT IN (
                    SELECT regionID FROM regions
                    WHERE regionName_de = ? COLLATE NOCASE OR regionName_en = ? COLLATE NOCASE 
                    OR regionName_es = ? COLLATE NOCASE OR regionName_fr = ? COLLATE NOCASE 
                    OR regionName_ja = ? COLLATE NOCASE OR regionName_ko = ? COLLATE NOCASE 
                    OR regionName_ru = ? COLLATE NOCASE OR regionName_zh = ? COLLATE NOCASE
                    OR regionName_de LIKE ? OR regionName_en LIKE ? OR regionName_es LIKE ?
                    OR regionName_fr LIKE ? OR regionName_ja LIKE ? OR regionName_ko LIKE ?
                    OR regionName_ru LIKE ? OR regionName_zh LIKE ?
                )
                ORDER BY priority, name_length, regionName_en
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            regionsQuery, parameters: queryParams, useCache: false
        ) {
            for row in rows {
                var names: [String: String] = [:]
                if let deName = row["regionName_de"] as? String { names["de"] = deName }
                if let enName = row["regionName_en"] as? String { names["en"] = enName }
                if let esName = row["regionName_es"] as? String { names["es"] = esName }
                if let frName = row["regionName_fr"] as? String { names["fr"] = frName }
                if let jaName = row["regionName_ja"] as? String { names["ja"] = jaName }
                if let koName = row["regionName_ko"] as? String { names["ko"] = koName }
                if let ruName = row["regionName_ru"] as? String { names["ru"] = ruName }
                if let zhName = row["regionName_zh"] as? String { names["zh"] = zhName }
                if let regionId = row["regionID"] as? Int {
                    let priority = row["priority"] as? Int ?? 3
                    let result = (id: regionId, names: names)
                    switch priority {
                    case 1: exact.append(result)
                    case 2: prefix.append(result)
                    case 3: fuzzy.append(result)
                    default: break
                    }
                }
            }
        }

        // 搜索势力
        let factionsQuery = """
                SELECT DISTINCT id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name, 1 as priority,
                       LENGTH(en_name) as name_length
                FROM factions
                WHERE de_name = ? COLLATE NOCASE OR en_name = ? COLLATE NOCASE OR es_name = ? COLLATE NOCASE 
                OR fr_name = ? COLLATE NOCASE OR ja_name = ? COLLATE NOCASE OR ko_name = ? COLLATE NOCASE 
                OR ru_name = ? COLLATE NOCASE OR zh_name = ? COLLATE NOCASE
                UNION ALL
                SELECT DISTINCT id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name, 2 as priority,
                       LENGTH(en_name) as name_length
                FROM factions
                WHERE (de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?)
                AND id NOT IN (
                    SELECT id FROM factions
                    WHERE de_name = ? COLLATE NOCASE OR en_name = ? COLLATE NOCASE OR es_name = ? COLLATE NOCASE 
                    OR fr_name = ? COLLATE NOCASE OR ja_name = ? COLLATE NOCASE OR ko_name = ? COLLATE NOCASE 
                    OR ru_name = ? COLLATE NOCASE OR zh_name = ? COLLATE NOCASE
                )
                UNION ALL
                SELECT DISTINCT id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name, 3 as priority,
                       LENGTH(en_name) as name_length
                FROM factions
                WHERE (de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?)
                AND id NOT IN (
                    SELECT id FROM factions
                    WHERE de_name = ? COLLATE NOCASE OR en_name = ? COLLATE NOCASE OR es_name = ? COLLATE NOCASE 
                    OR fr_name = ? COLLATE NOCASE OR ja_name = ? COLLATE NOCASE OR ko_name = ? COLLATE NOCASE 
                    OR ru_name = ? COLLATE NOCASE OR zh_name = ? COLLATE NOCASE
                    OR de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                    OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?
                )
                ORDER BY priority, name_length, en_name
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            factionsQuery, parameters: queryParams, useCache: false
        ) {
            for row in rows {
                var names: [String: String] = [:]
                if let deName = row["de_name"] as? String { names["de"] = deName }
                if let enName = row["en_name"] as? String { names["en"] = enName }
                if let esName = row["es_name"] as? String { names["es"] = esName }
                if let frName = row["fr_name"] as? String { names["fr"] = frName }
                if let jaName = row["ja_name"] as? String { names["ja"] = jaName }
                if let koName = row["ko_name"] as? String { names["ko"] = koName }
                if let ruName = row["ru_name"] as? String { names["ru"] = ruName }
                if let zhName = row["zh_name"] as? String { names["zh"] = zhName }
                if let factionId = row["id"] as? Int {
                    let priority = row["priority"] as? Int ?? 3
                    let result = (id: factionId, names: names)
                    switch priority {
                    case 1: exact.append(result)
                    case 2: prefix.append(result)
                    case 3: fuzzy.append(result)
                    default: break
                    }
                }
            }
        }

        // 搜索 NPC 军团
        let npcCorpsQuery = """
                SELECT DISTINCT corporation_id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name, 1 as priority,
                       LENGTH(en_name) as name_length
                FROM npcCorporations
                WHERE de_name = ? COLLATE NOCASE OR en_name = ? COLLATE NOCASE OR es_name = ? COLLATE NOCASE 
                OR fr_name = ? COLLATE NOCASE OR ja_name = ? COLLATE NOCASE OR ko_name = ? COLLATE NOCASE 
                OR ru_name = ? COLLATE NOCASE OR zh_name = ? COLLATE NOCASE
                UNION ALL
                SELECT DISTINCT corporation_id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name, 2 as priority,
                       LENGTH(en_name) as name_length
                FROM npcCorporations
                WHERE (de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?)
                AND corporation_id NOT IN (
                    SELECT corporation_id FROM npcCorporations
                    WHERE de_name = ? COLLATE NOCASE OR en_name = ? COLLATE NOCASE OR es_name = ? COLLATE NOCASE 
                    OR fr_name = ? COLLATE NOCASE OR ja_name = ? COLLATE NOCASE OR ko_name = ? COLLATE NOCASE 
                    OR ru_name = ? COLLATE NOCASE OR zh_name = ? COLLATE NOCASE
                )
                UNION ALL
                SELECT DISTINCT corporation_id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name, 3 as priority,
                       LENGTH(en_name) as name_length
                FROM npcCorporations
                WHERE (de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?)
                AND corporation_id NOT IN (
                    SELECT corporation_id FROM npcCorporations
                    WHERE de_name = ? COLLATE NOCASE OR en_name = ? COLLATE NOCASE OR es_name = ? COLLATE NOCASE 
                    OR fr_name = ? COLLATE NOCASE OR ja_name = ? COLLATE NOCASE OR ko_name = ? COLLATE NOCASE 
                    OR ru_name = ? COLLATE NOCASE OR zh_name = ? COLLATE NOCASE
                    OR de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                    OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?
                )
                ORDER BY priority, name_length, en_name
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            npcCorpsQuery, parameters: queryParams, useCache: false
        ) {
            for row in rows {
                var names: [String: String] = [:]
                if let deName = row["de_name"] as? String { names["de"] = deName }
                if let enName = row["en_name"] as? String { names["en"] = enName }
                if let esName = row["es_name"] as? String { names["es"] = esName }
                if let frName = row["fr_name"] as? String { names["fr"] = frName }
                if let jaName = row["ja_name"] as? String { names["ja"] = jaName }
                if let koName = row["ko_name"] as? String { names["ko"] = koName }
                if let ruName = row["ru_name"] as? String { names["ru"] = ruName }
                if let zhName = row["zh_name"] as? String { names["zh"] = zhName }
                if let corpId = row["corporation_id"] as? Int {
                    let priority = row["priority"] as? Int ?? 3
                    let result = (id: corpId, names: names)
                    switch priority {
                    case 1: exact.append(result)
                    case 2: prefix.append(result)
                    case 3: fuzzy.append(result)
                    default: break
                    }
                }
            }
        }

        // 最后更新结果
        exactMatchResults = exact
        prefixMatchResults = prefix
        fuzzyMatchResults = fuzzy
    }
}
