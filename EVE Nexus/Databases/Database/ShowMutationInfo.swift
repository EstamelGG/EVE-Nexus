import SwiftUI

struct ShowMutationInfo: View {
    let itemID: Int
    @ObservedObject var databaseManager: DatabaseManager

    // 基础信息
    @State private var itemDetails: ItemDetails?

    // 突变属性
    @State private var mutationAttributes:
        [(
            attributeID: Int, name: String, iconFileName: String?, minValue: Double,
            maxValue: Double, highIsGood: Bool
        )] = []

    // 可应用物品
    @State private var applicableItems: [(typeID: Int, name: String, iconFileName: String)] = []
    @State private var resultingItem: (typeID: Int, name: String, iconFileName: String)?

    var body: some View {
        List {
            // 基础信息部分
            if let itemDetails = itemDetails {
                ItemBasicInfoView(itemDetails: itemDetails, databaseManager: databaseManager)
            }

            // 工业相关部分
            IndustrySection(
                itemID: itemID, databaseManager: databaseManager, itemDetails: itemDetails)

            // 突变属性部分
            if !mutationAttributes.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_Database_Mutation_Attribute", comment: ""))
                        .font(.headline)
                ) {
                    ForEach(mutationAttributes, id: \.attributeID) { attribute in
                        HStack {
                            // 左侧：图标和名称
                            HStack(spacing: 8) {
                                if let iconFileName = attribute.iconFileName {
                                    IconManager.shared.loadImage(for: iconFileName)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }

                                Text(attribute.name)
                                    .font(.body)
                            }

                            Spacer()

                            // 右侧：数值范围
                            HStack(spacing: 4) {
                                Text(
                                    formatValue(
                                        attribute.highIsGood
                                            ? attribute.minValue : attribute.maxValue)
                                )
                                .foregroundColor(.red)
                                Text("-")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(
                                    formatValue(
                                        attribute.highIsGood
                                            ? attribute.maxValue : attribute.minValue)
                                )
                                .foregroundColor(.green)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // 可应用物品部分
            if !applicableItems.isEmpty {
                Section(
                    header: Text(NSLocalizedString("Main_Database_Mutation_Source", comment: ""))
                        .font(.headline)
                ) {
                    ForEach(applicableItems, id: \.typeID) { item in
                        NavigationLink {
                            ShowItemInfo(databaseManager: databaseManager, itemID: item.typeID)
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: item.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)

                                Text(item.name)
                                    .font(.body)
                            }
                        }
                    }
                }

                // 突变结果
                if let resultingItem = resultingItem {
                    Section(
                        header: Text(
                            NSLocalizedString("Main_Database_Mutation_Results", comment: "")
                        ).font(.headline)
                    ) {
                        NavigationLink {
                            ShowItemInfo(
                                databaseManager: databaseManager, itemID: resultingItem.typeID)
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: resultingItem.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)

                                Text(resultingItem.name)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Info")
        .onAppear {
            itemDetails = databaseManager.getItemDetails(for: itemID)
            loadMutationData()
        }
    }

    private func formatValue(_ value: Double) -> String {
        let percentage = (value - 1) * 100
        return String(format: "%+.2f%%", percentage)
    }

    private func loadMutationData() {
        // 加载突变属性
        let attributesQuery = """
                SELECT a.attribute_id, d.display_name, COALESCE(i.iconFile_new, '') as icon_filename, 
                       a.min_value, a.max_value, d.highIsGood
                FROM dynamic_item_attributes a
                LEFT JOIN dogmaAttributes d ON a.attribute_id = d.attribute_id
                LEFT JOIN iconIDs i ON d.iconID = i.icon_id
                WHERE a.type_id = ?
                ORDER BY d.display_name
            """

        if case let .success(rows) = databaseManager.executeQuery(
            attributesQuery, parameters: [itemID])
        {
            mutationAttributes = rows.compactMap { row in
                guard let attributeID = row["attribute_id"] as? Int,
                    let name = row["display_name"] as? String,
                    let minValue = row["min_value"] as? Double,
                    let maxValue = row["max_value"] as? Double,
                    let highIsGood = row["highIsGood"] as? Int
                else { return nil }
                let iconFileName = row["icon_filename"] as? String
                return (
                    attributeID: attributeID,
                    name: name,
                    iconFileName: iconFileName,
                    minValue: minValue,
                    maxValue: maxValue,
                    highIsGood: highIsGood == 1
                )
            }
        }

        // 加载可应用物品和结果
        let mappingsQuery = """
                SELECT m.applicable_type, m.resulting_type,
                       t1.name as applicable_name, t1.icon_filename as applicable_icon, t1.metaGroupID as applicable_meta,
                       t2.name as resulting_name, t2.icon_filename as resulting_icon
                FROM dynamic_item_mappings m
                LEFT JOIN types t1 ON m.applicable_type = t1.type_id
                LEFT JOIN types t2 ON m.resulting_type = t2.type_id
                WHERE m.type_id = ?
                ORDER BY t1.metaGroupID ASC, t1.type_id ASC
            """

        if case let .success(rows) = databaseManager.executeQuery(
            mappingsQuery, parameters: [itemID])
        {
            // 处理可应用物品
            var seenTypeIDs = Set<Int>()
            applicableItems = rows.compactMap { row in
                guard let typeID = row["applicable_type"] as? Int,
                    let name = row["applicable_name"] as? String,
                    let iconFileName = row["applicable_icon"] as? String,
                    !seenTypeIDs.contains(typeID)
                else { return nil }
                seenTypeIDs.insert(typeID)
                return (typeID: typeID, name: name, iconFileName: iconFileName)
            }

            // 处理突变结果（取第一行即可，因为对于同一个突变质体，结果都是一样的）
            if let row = rows.first,
                let typeID = row["resulting_type"] as? Int,
                let name = row["resulting_name"] as? String,
                let iconFileName = row["resulting_icon"] as? String
            {
                resultingItem = (typeID: typeID, name: name, iconFileName: iconFileName)
            }
        }
    }
}
