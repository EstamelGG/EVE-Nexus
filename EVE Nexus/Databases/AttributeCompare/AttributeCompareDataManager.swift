import Foundation

// 属性对比功能实用工具
enum AttributeCompareUtil {
    // 所有用于JSON序列化的结构都必须遵循Codable
    struct AttributeValueInfo: Codable {
        let value: Double
        let unitID: Int?
    }

    // 完整的对比结果结构，全部基于Codable
    struct CompareResult: Codable {
        // 属性对比数据 - 格式: [attributeID: [typeID: {value, unitID}]]
        let compareResult: [String: [String: AttributeValueInfo]]

        // 物品名称信息 - 格式: [typeID: name]
        let typeInfo: [String: String]

        // 已发布属性名称信息 - 格式: [attributeID: display_name]
        let publishedAttributeInfo: [String: String]

        // 未发布属性名称信息 - 格式: [attributeID: name]
        let unpublishedAttributeInfo: [String: String]

        // 属性图标信息 - 格式: [attributeID: iconFileName]
        let attributeIcons: [String: String]

        // 编码键名映射
        enum CodingKeys: String, CodingKey {
            case compareResult = "compare_result"
            case typeInfo = "type_info"
            case publishedAttributeInfo = "published_attribute_info"
            case unpublishedAttributeInfo = "unpublished_attribute_info"
            case attributeIcons = "attribute_icons"
        }
    }

    // 获取多个物品的属性对比数据（静态函数）
    static func compareAttributes(typeIDs: [Int], databaseManager: DatabaseManager) {
        // 如果物品数量少于2个，不进行对比
        if typeIDs.count < 2 {
            Logger.info("需要至少两个物品才能进行对比")
            return
        }

        // 去重处理
        let uniqueTypeIDs = Array(Set(typeIDs))

        if uniqueTypeIDs.count < 2 {
            Logger.info("去重后物品数量少于2个，无法进行对比")
            return
        }

        Logger.info("开始属性对比，物品ID: \(uniqueTypeIDs)")

        // 构建SQL查询条件
        let typeIDsString = uniqueTypeIDs.map { String($0) }.joined(separator: ",")

        // 查询SQL - 获取属性值和单位信息
        let query = """
                SELECT 
                    ta.type_id, 
                    ta.attribute_id, 
                    a.display_name,
                    a.name,
                    ta.value, 
                    COALESCE(ta.unitID, a.unitID) as unitID
                FROM 
                    typeAttributes ta
                LEFT JOIN 
                    dogmaAttributes a ON ta.attribute_id = a.attribute_id
                WHERE 
                    ta.type_id IN (\(typeIDsString))
                ORDER BY 
                    ta.attribute_id
            """

        // 执行查询
        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            Logger.error("获取物品属性对比数据失败")
            return
        }

        Logger.info("查询到 \(rows.count) 行原始数据")

        // 初始化结果字典 - 格式: [attributeID: [typeID: {value, unitID}]]
        var attributeValues: [String: [String: AttributeValueInfo]] = [:]

        // 处理查询结果
        for row in rows {
            guard let typeID = row["type_id"] as? Int,
                let attributeID = row["attribute_id"] as? Int,
                let value = row["value"] as? Double
            else {
                continue
            }

            let unitID = row["unitID"] as? Int
            let displayName = row["display_name"] as? String
            let name = row["name"] as? String

            // 属性名称处理
            let attributeName = displayName.flatMap { $0.isEmpty ? nil : $0 } ?? name ?? "未知属性"

            let attributeIDString = String(attributeID)
            let typeIDString = String(typeID)

            // 如果该属性ID还没有在结果字典中，添加它
            if attributeValues[attributeIDString] == nil {
                attributeValues[attributeIDString] = [:]
            }

            // 添加当前物品的属性值信息
            attributeValues[attributeIDString]?[typeIDString] = AttributeValueInfo(
                value: value, unitID: unitID)

            // 此处可以添加属性名称到日志，用于调试
            Logger.debug(
                "处理属性: \(attributeIDString) (\(attributeName)), 物品ID: \(typeIDString), 值: \(value)")
        }

        // 补充物品名称信息
        let typeNames = getTypeNames(typeIDs: uniqueTypeIDs, databaseManager: databaseManager)
        var typeInfo: [String: String] = [:]
        for (id, name) in typeNames {
            typeInfo[String(id)] = name
        }

        // 获取属性信息并区分已发布和未发布
        let attributeIDs = Array(attributeValues.keys).compactMap { Int($0) }
        let attributeDetails = getAttributeDetails(
            attributeIDs: attributeIDs, databaseManager: databaseManager)

        // 已发布属性信息 (有display_name的)
        var publishedAttributeInfo: [String: String] = [:]
        // 未发布属性信息 (只有name的)
        var unpublishedAttributeInfo: [String: String] = [:]

        for (id, details) in attributeDetails {
            let attributeIDString = String(id)

            if let displayName = details.displayName, !displayName.isEmpty {
                // 有display_name的属性放入已发布列表
                publishedAttributeInfo[attributeIDString] = displayName
            } else if let name = details.name {
                // 只有name的属性放入未发布列表
                unpublishedAttributeInfo[attributeIDString] = name
            }
        }

        // 构建符合Codable的结果对象
        let result = CompareResult(
            compareResult: attributeValues,
            typeInfo: typeInfo,
            publishedAttributeInfo: publishedAttributeInfo,
            unpublishedAttributeInfo: unpublishedAttributeInfo,
            attributeIcons: [:]
        )

        // 使用JSONEncoder直接序列化Codable对象
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(result)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                Logger.info("属性对比结果JSON:\n\(jsonString)")
            }
        } catch {
            Logger.error("无法将结果转换为JSON: \(error)")
        }
    }

    // 属性详细信息结构
    struct AttributeDetail {
        let displayName: String?
        let name: String?
    }

    // 获取属性的详细信息
    private static func getAttributeDetails(attributeIDs: [Int], databaseManager: DatabaseManager)
        -> [Int: AttributeDetail]
    {
        if attributeIDs.isEmpty {
            return [:]
        }

        let attributeIDsString = attributeIDs.map { String($0) }.joined(separator: ",")

        let query = """
                SELECT 
                    attribute_id, 
                    display_name,
                    name
                FROM 
                    dogmaAttributes
                WHERE 
                    attribute_id IN (\(attributeIDsString))
            """

        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            return [:]
        }

        var result: [Int: AttributeDetail] = [:]

        for row in rows {
            guard let attributeID = row["attribute_id"] as? Int else {
                continue
            }

            let displayName = row["display_name"] as? String
            let name = row["name"] as? String

            result[attributeID] = AttributeDetail(
                displayName: displayName,
                name: name
            )
        }

        return result
    }

    // 获取物品名称
    private static func getTypeNames(typeIDs: [Int], databaseManager: DatabaseManager) -> [Int:
        String]
    {
        if typeIDs.isEmpty {
            return [:]
        }

        let typeIDsString = typeIDs.map { String($0) }.joined(separator: ",")

        let query = """
                SELECT 
                    type_id, 
                    name
                FROM 
                    types
                WHERE 
                    type_id IN (\(typeIDsString))
            """

        guard case let .success(rows) = databaseManager.executeQuery(query) else {
            return [:]
        }

        var result: [Int: String] = [:]

        for row in rows {
            guard let typeID = row["type_id"] as? Int,
                let name = row["name"] as? String
            else {
                continue
            }

            result[typeID] = name
        }

        return result
    }
}
