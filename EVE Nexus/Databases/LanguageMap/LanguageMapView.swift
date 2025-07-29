import SwiftUI

struct LanguageMapView: View {
    // State 属性
    @State private var exactMatchResults: [(id: Int, names: [String: String])] = []  // 完全匹配结果
    @State private var prefixMatchResults: [(id: Int, names: [String: String])] = []  // 前缀匹配结果
    @State private var fuzzyMatchResults: [(id: Int, names: [String: String])] = []  // 模糊匹配结果
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var hasTypeIdMatch = false
    @State private var showingSettings = false
    @State private var selectedLanguages: [String] = LanguageMapConstants.languageMapDefaultLanguages

    let availableLanguages = LanguageMapConstants.availableLanguages

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
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_5", comment: "5. 物品目录名")
                        )
                        .foregroundColor(.secondary)
                        Text(
                            NSLocalizedString(
                                "Main_Language_Map_Search_Object_6", comment: "6. 物品组名")
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
                            .fontWeight(.semibold)
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
                            .fontWeight(.semibold)
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
                            .fontWeight(.semibold)
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
        .onSubmit(of: .search) {
            // 点击小键盘搜索按钮时执行搜索
            performSearch()
        }
        .onChange(of: searchText) { _, newValue in
            // 当搜索文本清空时，清除结果
            if newValue.isEmpty {
                exactMatchResults = []
                prefixMatchResults = []
                fuzzyMatchResults = []
                hasTypeIdMatch = false
            }
        }
        .navigationTitle(NSLocalizedString("Main_Language_Map", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            LanguageMapSettingsView()
        }
        .onAppear {
            // 从UserDefaults读取选中的语言
            selectedLanguages = UserDefaults.standard.stringArray(forKey: LanguageMapConstants.userDefaultsKey) ?? LanguageMapConstants.languageMapDefaultLanguages
        }
    }

    // 提取结果行视图为单独的组件
    private struct ResultRow: View {
        let result: (id: Int, names: [String: String])
        let availableLanguages: [String: String]
        @State private var selectedLanguages: [String] = LanguageMapConstants.languageMapDefaultLanguages

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(selectedLanguages.sorted(), id: \.self) { langCode in
                    if let name = result.names[langCode] {
                        HStack {
                            Text("\(availableLanguages[langCode] ?? langCode):")
                                .foregroundColor(.gray)
                                .frame(width: 80, alignment: .trailing)
                            Text(name)
                                .contextMenu {
                                    // 为每种选中的语言提供单独的复制按钮
                                    ForEach(selectedLanguages.sorted(), id: \.self) { lang in
                                        if let text = result.names[lang] {
                                            Button {
                                                UIPasteboard.general.string = text
                                            } label: {
                                                Label("\(NSLocalizedString("Misc_Copy", comment: "")) \(availableLanguages[lang] ?? lang)", systemImage: "doc.on.doc")
                                            }
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Button {
                                        // 构建所有选中语言的文本
                                        let allLanguagesText = selectedLanguages.sorted().compactMap { lang in
                                            if let text = result.names[lang] {
                                                return "\(availableLanguages[lang] ?? lang): \(text)"
                                            }
                                            return nil
                                        }.joined(separator: "\n")
                                        
                                        UIPasteboard.general.string = allLanguagesText
                                    } label: {
                                        Label(NSLocalizedString("Misc_Copy_All_Languages", comment: "复制所有语言"), systemImage: "doc.on.doc.fill")
                                    }
                                }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .onAppear {
                // 从UserDefaults读取选中的语言
                selectedLanguages = UserDefaults.standard.stringArray(forKey: LanguageMapConstants.userDefaultsKey) ?? LanguageMapConstants.languageMapDefaultLanguages
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else {
            exactMatchResults = []
            prefixMatchResults = []
            fuzzyMatchResults = []
            hasTypeIdMatch = false
            return
        }

        var exact: [(id: Int, names: [String: String])] = []
        var prefix: [(id: Int, names: [String: String])] = []
        var fuzzy: [(id: Int, names: [String: String])] = []

        // 重置hasTypeIdMatch
        hasTypeIdMatch = false

        // 检查searchText是否可以转换为整数（用于type_id搜索）
        let typeIdToSearch = Int(searchText)

        // 搜索物品 - 使用简化的SQL，在代码中进行匹配类型分类
        let typesQuery = """
                SELECT DISTINCT type_id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name, 
                       LENGTH(en_name) as name_length
                FROM types
                WHERE (
                      -- type_id精确匹配（如果searchText是数字）
                      (\(typeIdToSearch != nil ? "type_id = \(typeIdToSearch!)" : "0=1"))
                      -- 名称模糊匹配（包含所有匹配类型）
                      OR de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                      OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?
                )
                ORDER BY name_length, en_name
                LIMIT 200
            """

        // 简化的查询参数：只需要模糊匹配的参数
        let searchPattern = "%\(searchText)%"
        let simplifiedParams = Array(repeating: searchPattern, count: 8)

        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            typesQuery, parameters: simplifiedParams, useCache: false
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
                    let result = (id: typeId, names: names)

                    // 在代码中判断匹配类型
                    if typeId == typeIdToSearch {
                        // type_id精确匹配
                        hasTypeIdMatch = true
                        exact.append(result)
                    } else if isExactNameMatch(names: names, searchText: searchText) {
                        // 名称完全匹配
                        exact.append(result)
                    } else if isPrefixNameMatch(names: names, searchText: searchText) {
                        // 名称前缀匹配
                        prefix.append(result)
                    } else {
                        // 名称模糊匹配
                        fuzzy.append(result)
                    }
                }
            }
        }

        // 搜索星系 - 简化的SQL，在代码中进行匹配类型分类
        let systemsQuery = """
                SELECT DISTINCT solarSystemID, solarSystemName_de, solarSystemName_en, solarSystemName_es, solarSystemName_fr,
                       solarSystemName_ja, solarSystemName_ko, solarSystemName_ru, solarSystemName_zh,
                       LENGTH(solarSystemName_en) as name_length
                FROM solarsystems
                WHERE solarSystemName_de LIKE ? OR solarSystemName_en LIKE ? OR solarSystemName_es LIKE ?
                OR solarSystemName_fr LIKE ? OR solarSystemName_ja LIKE ? OR solarSystemName_ko LIKE ?
                OR solarSystemName_ru LIKE ? OR solarSystemName_zh LIKE ?
                ORDER BY name_length, solarSystemName_en
                LIMIT 200
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            systemsQuery, parameters: simplifiedParams, useCache: false
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
                    let result = (id: systemId, names: names)
                    
                    // 在代码中判断匹配类型
                    if isExactNameMatch(names: names, searchText: searchText) {
                        exact.append(result)
                    } else if isPrefixNameMatch(names: names, searchText: searchText) {
                        prefix.append(result)
                    } else {
                        fuzzy.append(result)
                    }
                }
            }
        }

        // 搜索星座 - 简化的SQL，在代码中进行匹配类型分类
        let constellationsQuery = """
                SELECT DISTINCT constellationID, constellationName_de, constellationName_en, constellationName_es, constellationName_fr,
                       constellationName_ja, constellationName_ko, constellationName_ru, constellationName_zh,
                       LENGTH(constellationName_en) as name_length
                FROM constellations
                WHERE constellationName_de LIKE ? OR constellationName_en LIKE ? OR constellationName_es LIKE ?
                OR constellationName_fr LIKE ? OR constellationName_ja LIKE ? OR constellationName_ko LIKE ?
                OR constellationName_ru LIKE ? OR constellationName_zh LIKE ?
                ORDER BY name_length, constellationName_en
                LIMIT 200
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            constellationsQuery, parameters: simplifiedParams, useCache: false
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
                    let result = (id: constellationId, names: names)
                    
                    // 在代码中判断匹配类型
                    if isExactNameMatch(names: names, searchText: searchText) {
                        exact.append(result)
                    } else if isPrefixNameMatch(names: names, searchText: searchText) {
                        prefix.append(result)
                    } else {
                        fuzzy.append(result)
                    }
                }
            }
        }

        // 搜索星域 - 简化的SQL，在代码中进行匹配类型分类
        let regionsQuery = """
                SELECT DISTINCT regionID, regionName_de, regionName_en, regionName_es, regionName_fr,
                       regionName_ja, regionName_ko, regionName_ru, regionName_zh,
                       LENGTH(regionName_en) as name_length
                FROM regions
                WHERE regionName_de LIKE ? OR regionName_en LIKE ? OR regionName_es LIKE ?
                OR regionName_fr LIKE ? OR regionName_ja LIKE ? OR regionName_ko LIKE ?
                OR regionName_ru LIKE ? OR regionName_zh LIKE ?
                ORDER BY name_length, regionName_en
                LIMIT 200
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            regionsQuery, parameters: simplifiedParams, useCache: false
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
                    let result = (id: regionId, names: names)
                    
                    // 在代码中判断匹配类型
                    if isExactNameMatch(names: names, searchText: searchText) {
                        exact.append(result)
                    } else if isPrefixNameMatch(names: names, searchText: searchText) {
                        prefix.append(result)
                    } else {
                        fuzzy.append(result)
                    }
                }
            }
        }

        // 搜索势力 - 简化的SQL，在代码中进行匹配类型分类
        let factionsQuery = """
                SELECT DISTINCT id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name,
                       LENGTH(en_name) as name_length
                FROM factions
                WHERE de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?
                ORDER BY name_length, en_name
                LIMIT 200
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            factionsQuery, parameters: simplifiedParams, useCache: false
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
                    let result = (id: factionId, names: names)
                    
                    // 在代码中判断匹配类型
                    if isExactNameMatch(names: names, searchText: searchText) {
                        exact.append(result)
                    } else if isPrefixNameMatch(names: names, searchText: searchText) {
                        prefix.append(result)
                    } else {
                        fuzzy.append(result)
                    }
                }
            }
        }

        // 搜索 NPC 军团 - 简化的SQL，在代码中进行匹配类型分类
        let npcCorpsQuery = """
                SELECT DISTINCT corporation_id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name,
                       LENGTH(en_name) as name_length
                FROM npcCorporations
                WHERE de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?
                ORDER BY name_length, en_name
                LIMIT 200
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            npcCorpsQuery, parameters: simplifiedParams, useCache: false
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
                    let result = (id: corpId, names: names)
                    
                    // 在代码中判断匹配类型
                    if isExactNameMatch(names: names, searchText: searchText) {
                        exact.append(result)
                    } else if isPrefixNameMatch(names: names, searchText: searchText) {
                        prefix.append(result)
                    } else {
                        fuzzy.append(result)
                    }
                }
            }
        }

        // 搜索物品目录名 - 简化的SQL，在代码中进行匹配类型分类
        let categoriesQuery = """
                SELECT DISTINCT category_id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name,
                       LENGTH(en_name) as name_length
                FROM categories
                WHERE de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?
                ORDER BY name_length, en_name
                LIMIT 200
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            categoriesQuery, parameters: simplifiedParams, useCache: false
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
                if let categoryId = row["category_id"] as? Int {
                    let result = (id: categoryId, names: names)
                    
                    // 在代码中判断匹配类型
                    if isExactNameMatch(names: names, searchText: searchText) {
                        exact.append(result)
                    } else if isPrefixNameMatch(names: names, searchText: searchText) {
                        prefix.append(result)
                    } else {
                        fuzzy.append(result)
                    }
                }
            }
        }

        // 搜索物品组名 - 简化的SQL，在代码中进行匹配类型分类
        let groupsQuery = """
                SELECT DISTINCT group_id, de_name, en_name, es_name, fr_name, ja_name, ko_name, ru_name, zh_name,
                       LENGTH(en_name) as name_length
                FROM groups
                WHERE de_name LIKE ? OR en_name LIKE ? OR es_name LIKE ? OR fr_name LIKE ?
                OR ja_name LIKE ? OR ko_name LIKE ? OR ru_name LIKE ? OR zh_name LIKE ?
                ORDER BY name_length, en_name
                LIMIT 200
            """
        if case let .success(rows) = DatabaseManager.shared.executeQuery(
            groupsQuery, parameters: simplifiedParams, useCache: false
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
                if let groupId = row["group_id"] as? Int {
                    let result = (id: groupId, names: names)
                    
                    // 在代码中判断匹配类型
                    if isExactNameMatch(names: names, searchText: searchText) {
                        exact.append(result)
                    } else if isPrefixNameMatch(names: names, searchText: searchText) {
                        prefix.append(result)
                    } else {
                        fuzzy.append(result)
                    }
                }
            }
        }

        // 最后更新结果
        exactMatchResults = exact
        prefixMatchResults = prefix
        fuzzyMatchResults = fuzzy
    }

    // 判断是否为名称完全匹配
    private func isExactNameMatch(names: [String: String], searchText: String) -> Bool {
        let lowercaseSearchText = searchText.lowercased()
        return names.values.contains { $0.lowercased() == lowercaseSearchText }
    }

    // 判断是否为名称前缀匹配
    private func isPrefixNameMatch(names: [String: String], searchText: String) -> Bool {
        let lowercaseSearchText = searchText.lowercased()
        return names.values.contains { $0.lowercased().hasPrefix(lowercaseSearchText) }
    }
}
