import SwiftUI

// MARK: - 深渊突变属性模型

/// 用于展示的突变属性条目
private struct DynamicAttributeEntry: Identifiable {
    let id: Int // attribute_id
    let name: String
    let iconFileName: String?
    let unitName: String? // 属性单位（如 "mm", "HP", "s", "%"）
    let originalValue: Double // 来源物品的原始数值
    let currentValue: Double // ESI 返回的当前实际数值
    let minMutator: Double // 突变质体的最小乘数
    let maxMutator: Double // 突变质体的最大乘数
    let highIsGood: Bool

    /// 当前突变乘数 = currentValue / originalValue
    var mutationMultiplier: Double {
        guard originalValue != 0 else { return 1.0 }
        return currentValue / originalValue
    }
}

// MARK: - 深渊突变物品详情页

/// 通过 ESI dogma/dynamic/items API 获取制作者、来源物品、突变质体及属性突变情况
struct DynamicItemDetailView: View {
    let typeId: Int
    let itemId: Int64
    let itemName: String

    private let databaseManager = DatabaseManager()

    // MARK: - State

    @State private var isLoading = true
    @State private var errorMessage: String?

    /// API 返回的原始结果
    @State private var dynamicResult: DogmaDynamicItemsResult?

    /// 制作者名称
    @State private var creatorName: String?

    /// 来源物品信息
    @State private var sourceItemInfo: (name: String, iconFileName: String)?

    /// 突变质体信息
    @State private var mutaplasmidInfo: (name: String, iconFileName: String)?

    /// 解析后的突变属性列表
    @State private var mutationAttributes: [DynamicAttributeEntry] = []

    // MARK: - Body

    var body: some View {
        List {
            // 物品基本信息
            if let details = databaseManager.getItemDetails(for: typeId) {
                ItemBasicInfoView(
                    itemDetails: details,
                    databaseManager: databaseManager,
                    modifiedAttributes: nil
                )
            }

            // 加载中
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(NSLocalizedString("Abyssal_Loading", comment: ""))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }

            // 错误提示
            if let errorMessage = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // 突变属性
            if !mutationAttributes.isEmpty {
                Section(
                    header: sectionHeader(NSLocalizedString("Main_Database_Mutation_Attribute", comment: ""))
                ) {
                    ForEach(mutationAttributes) { attr in
                        DynamicAttributeRowView(attribute: attr)
                    }
                }
            }

            // 制作者（可跳转到角色详情）
            if let creatorName = creatorName, let result = dynamicResult {
                Section(header: sectionHeader(NSLocalizedString("Abyssal_Created_By", comment: ""))) {
                    if let character = currentCharacter {
                        NavigationLink {
                            CharacterDetailView(
                                characterId: result.created_by,
                                character: character
                            )
                        } label: {
                            creatorRow(createdBy: result.created_by, name: creatorName)
                        }
                    } else {
                        creatorRow(createdBy: result.created_by, name: creatorName)
                    }
                }
            }

            // 来源物品
            if let sourceInfo = sourceItemInfo, let result = dynamicResult {
                Section(header: sectionHeader(NSLocalizedString("Abyssal_Source_Item", comment: ""))) {
                    NavigationLink {
                        ShowItemInfo(databaseManager: databaseManager, itemID: result.source_type_id)
                    } label: {
                        HStack(spacing: 12) {
                            IconManager.shared.loadImage(for: sourceInfo.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(sourceInfo.name)
                        }
                    }
                }
            }

            // 使用的突变质体
            if let mutaInfo = mutaplasmidInfo, let result = dynamicResult {
                Section(header: sectionHeader(NSLocalizedString("Abyssal_Mutaplasmid_Used", comment: ""))) {
                    NavigationLink {
                        ShowItemInfo(databaseManager: databaseManager, itemID: result.mutator_type_id)
                    } label: {
                        HStack(spacing: 12) {
                            IconManager.shared.loadImage(for: mutaInfo.iconFileName)
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(mutaInfo.name)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Abyssal_Item_Detail", comment: ""))
        .task {
            await loadDynamicItemInfo()
        }
    }

    // MARK: - 当前登录角色

    /// 通过 UserDefaults 获取当前角色信息，用于跳转 CharacterDetailView
    private var currentCharacter: EVECharacterInfo? {
        let charId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        guard charId > 0 else { return nil }
        return EVELogin.shared.getCharacterByID(charId)?.character
    }

    /// 制作者行视图（提取复用，避免 NavigationLink 和非跳转两种情况重复代码）
    private func creatorRow(createdBy: Int, name: String) -> some View {
        HStack(spacing: 12) {
            AsyncImage(
                url: URL(
                    string: "https://images.evetech.net/characters/\(createdBy)/portrait?size=64"
                )
            ) { phase in
                switch phase {
                case let .success(image):
                    image.resizable()
                        .frame(width: 40, height: 40)
                        .cornerRadius(20)
                case .failure:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.secondary)
                default:
                    ProgressView()
                        .frame(width: 40, height: 40)
                }
            }
            Text(name)
        }
    }

    // MARK: - 通用 Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .fontWeight(.semibold)
            .font(.system(size: 18))
            .foregroundColor(.primary)
            .textCase(.none)
    }

    // MARK: - 数据加载

    private func loadDynamicItemInfo() async {
        isLoading = true
        errorMessage = nil

        do {
            // 1. 调用 ESI API 获取突变物品信息
            let result = try await DogmaDynamicItemsAPI.shared.fetch(
                typeId: typeId, itemId: Int(itemId)
            )
            dynamicResult = result

            // 2. 获取制作者名称
            let namesMap = try await UniverseAPI.shared.getNamesWithFallback(
                ids: [result.created_by]
            )
            creatorName = namesMap[result.created_by]?.name ?? "ID: \(result.created_by)"

            // 3. 从数据库获取来源物品信息
            sourceItemInfo = queryTypeInfo(typeId: result.source_type_id)

            // 4. 从数据库获取突变质体信息
            mutaplasmidInfo = queryTypeInfo(typeId: result.mutator_type_id)

            // 5. 构建突变属性列表
            mutationAttributes = buildMutationAttributes(
                apiAttributes: result.dogma_attributes,
                sourceTypeId: result.source_type_id,
                mutatorTypeId: result.mutator_type_id
            )

            isLoading = false
        } catch {
            Logger.error("加载深渊物品详情失败: \(error)")
            errorMessage = NSLocalizedString("Abyssal_Load_Error", comment: "")
            isLoading = false
        }
    }

    // MARK: - 构建突变属性

    /// 组合三方数据：突变质体属性范围 + 来源物品原始值 + ESI 返回的当前值
    private func buildMutationAttributes(
        apiAttributes: [DogmaAttributeItem],
        sourceTypeId: Int,
        mutatorTypeId: Int
    ) -> [DynamicAttributeEntry] {
        // 1. 从 dynamic_item_attributes 获取突变质体能影响的属性（含范围和 highIsGood）
        let mutatorAttrs = loadMutatorAttributeRanges(mutatorTypeId: mutatorTypeId)
        guard !mutatorAttrs.isEmpty else { return [] }

        // 受影响的 attribute_id 集合
        let affectedAttrIds = Set(mutatorAttrs.map { $0.attributeID })

        // 2. 从 typeAttributes 获取来源物品的原始属性值
        let originalValues = loadOriginalAttributeValues(
            sourceTypeId: sourceTypeId,
            attributeIds: affectedAttrIds
        )

        // 3. 将 ESI 返回的属性值转为字典
        var currentValues: [Int: Double] = [:]
        for attr in apiAttributes {
            currentValues[attr.attribute_id] = attr.value
        }

        // 4. 组装
        var entries: [DynamicAttributeEntry] = []
        for mAttr in mutatorAttrs {
            guard let original = originalValues[mAttr.attributeID],
                  let current = currentValues[mAttr.attributeID]
            else { continue }

            entries.append(DynamicAttributeEntry(
                id: mAttr.attributeID,
                name: mAttr.name,
                iconFileName: mAttr.iconFileName,
                unitName: mAttr.unitName,
                originalValue: original,
                currentValue: current,
                minMutator: mAttr.minValue,
                maxMutator: mAttr.maxValue,
                highIsGood: mAttr.highIsGood
            ))
        }

        return entries
    }

    /// 从 dynamic_item_attributes 表加载突变质体的属性范围
    private func loadMutatorAttributeRanges(mutatorTypeId: Int) -> [(
        attributeID: Int, name: String, iconFileName: String?, unitName: String?,
        minValue: Double, maxValue: Double, highIsGood: Bool
    )] {
        let query = """
            SELECT a.attribute_id, d.display_name, COALESCE(d.icon_filename, '') as icon_filename,
                   d.unitName, a.min_value, a.max_value, d.highIsGood
            FROM dynamic_item_attributes a
            LEFT JOIN dogmaAttributes d ON a.attribute_id = d.attribute_id
            WHERE a.type_id = ?
            ORDER BY d.display_name
        """

        guard case let .success(rows) = databaseManager.executeQuery(
            query, parameters: [mutatorTypeId]
        ) else { return [] }

        return rows.compactMap { row in
            guard let attrId = row["attribute_id"] as? Int,
                  let name = row["display_name"] as? String,
                  let minVal = row["min_value"] as? Double,
                  let maxVal = row["max_value"] as? Double,
                  let hig = row["highIsGood"] as? Int
            else { return nil }
            let icon = row["icon_filename"] as? String
            let unit = row["unitName"] as? String
            return (
                attributeID: attrId,
                name: name,
                iconFileName: (icon?.isEmpty ?? true) ? nil : icon,
                unitName: (unit?.isEmpty ?? true) ? nil : unit,
                minValue: minVal,
                maxValue: maxVal,
                highIsGood: hig == 1
            )
        }
    }

    /// 从 typeAttributes 表获取来源物品某些属性的原始数值
    private func loadOriginalAttributeValues(
        sourceTypeId: Int, attributeIds: Set<Int>
    ) -> [Int: Double] {
        guard !attributeIds.isEmpty else { return [:] }
        let idList = attributeIds.sorted().map { String($0) }.joined(separator: ",")
        let query = """
            SELECT attribute_id, value
            FROM typeAttributes
            WHERE type_id = ? AND attribute_id IN (\(idList))
        """
        var result: [Int: Double] = [:]
        if case let .success(rows) = databaseManager.executeQuery(
            query, parameters: [sourceTypeId]
        ) {
            for row in rows {
                if let attrId = row["attribute_id"] as? Int,
                   let value = row["value"] as? Double
                {
                    result[attrId] = value
                }
            }
        }
        return result
    }

    /// 从数据库查询 type_id 对应的名称和图标
    private func queryTypeInfo(typeId: Int) -> (name: String, iconFileName: String)? {
        let query = "SELECT name, icon_filename FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let name = row["name"] as? String,
           let icon = row["icon_filename"] as? String
        {
            return (name: name, iconFileName: icon.isEmpty ? DatabaseConfig.defaultItemIcon : icon)
        }
        return nil
    }
}

// MARK: - 突变属性行视图（只读展示，带进度条）

private struct DynamicAttributeRowView: View {
    let attribute: DynamicAttributeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 第一行：图标 + 属性名 + 数值
            HStack(spacing: 8) {
                if let iconFileName = attribute.iconFileName, !iconFileName.isEmpty {
                    IconManager.shared.loadImage(for: iconFileName)
                        .resizable()
                        .frame(width: 24, height: 24)
                }

                Text(attribute.name)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                // 原始值 → 当前值（带单位）
                HStack(spacing: 4) {
                    Text(formatValueWithUnit(attribute.originalValue))
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatValueWithUnit(attribute.currentValue))
                        .foregroundColor(valueColor)
                }
                .font(.body)
            }

            // 第二行：红绿进度条
            MutationProgressBarView(
                currentValue: attribute.mutationMultiplier,
                minValue: attribute.minMutator,
                maxValue: attribute.maxMutator,
                highIsGood: attribute.highIsGood
            )
        }
        .padding(.vertical, 4)
    }

    /// 当前值的颜色
    private var valueColor: Color {
        let diff = attribute.currentValue - attribute.originalValue
        if abs(diff) < 0.0001 { return .secondary }
        let improved = attribute.highIsGood ? (diff > 0) : (diff < 0)
        return improved ? .green : .red
    }

    /// 格式化数值并附加单位
    private func formatValueWithUnit(_ value: Double) -> String {
        let numberString = formatAbsoluteValue(value)
        guard let unit = attribute.unitName, !unit.isEmpty else {
            return numberString
        }
        // 百分号紧贴数字，其他单位加空格
        return unit == "%" ? "\(numberString)\(unit)" : "\(numberString) \(unit)"
    }

    /// 格式化绝对数值（保留合理精度）
    private func formatAbsoluteValue(_ value: Double) -> String {
        // 对于很大的整数值（如 hitpoints）不显示小数
        if value == value.rounded() && abs(value) >= 1 {
            return FormatUtil.format(value)
        }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
