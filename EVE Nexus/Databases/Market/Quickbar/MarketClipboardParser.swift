import Foundation

class MarketClipboardParser {
    /// 剪贴板导入时，去重后的 type_id 个数上限
    static let maxImportDistinctTypeCount = 200

    /// 剪贴板解析结果
    struct ParseResult {
        let successCount: Int
        let failedItems: [String]
        let updatedItems: [QuickbarItem]
    }

    /// 解析剪贴板内容
    static func parseClipboardContent(
        _ content: String,
        databaseManager: DatabaseManager
    ) -> ParseResult {
        Logger.debug("剪贴板原始内容:\n\(content)")

        let lines = content.components(separatedBy: .newlines)
        Logger.debug("解析到 \(lines.count) 行数据")

        var itemsToImport: [(name: String, quantity: Int64)] = []
        var failedLines: [String] = []

        // 正则表达式匹配三种格式：
        // 格式1: 数量 + 空白字符 + 物品名称
        // 格式2: 物品名称 + 空白字符 + 数量 + 可选的其他内容
        // 格式3: 物品名称 + \t + 其他信息 + \t + 数量
        let format1Regex = try! NSRegularExpression(pattern: #"^([\d,]+)\s+(.+)$"#, options: [])
        let format2Regex = try! NSRegularExpression(
            pattern: #"^(.+?)\s+([\d,]+)(\s+|$)"#, options: []
        )

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.debug("处理第 \(index + 1) 行: '\(trimmedLine)'")

            if trimmedLine.isEmpty {
                Logger.debug("第 \(index + 1) 行为空，跳过")
                continue
            }

            // 跳过以 "Total:" 开头的行
            if trimmedLine.hasPrefix("Total:") {
                Logger.debug("第 \(index + 1) 行是总计行，跳过: \(trimmedLine)")
                continue
            }

            let range = NSRange(trimmedLine.startIndex ..< trimmedLine.endIndex, in: trimmedLine)
            var quantityStr: String?
            var itemName: String?

            // 首先尝试格式3: 通过\t分割的格式 (物品名称\t其他信息\t数量)
            if trimmedLine.contains("\t") {
                let components = trimmedLine.components(separatedBy: "\t")
                if components.count >= 3 {
                    let nameComponent = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let quantityComponent = components[2].trimmingCharacters(in: .whitespacesAndNewlines)

                    // 验证数量是否为数字
                    let cleanQuantityStr = quantityComponent.replacingOccurrences(of: ",", with: "")
                    if Int64(cleanQuantityStr) != nil {
                        itemName = nameComponent
                        quantityStr = quantityComponent
                        Logger.debug("匹配格式3 - 物品名: '\(itemName ?? "")', 数量: \(quantityStr ?? "")")
                    }
                }
            }

            // 如果格式3没有匹配，尝试格式1: 数量 + 空白字符 + 物品名称
            if itemName == nil {
                if let match = format1Regex.firstMatch(in: trimmedLine, options: [], range: range) {
                    if let quantityRange = Range(match.range(at: 1), in: trimmedLine),
                       let nameRange = Range(match.range(at: 2), in: trimmedLine)
                    {
                        quantityStr = String(trimmedLine[quantityRange])
                        itemName = String(trimmedLine[nameRange]).trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        Logger.debug("匹配格式1 - 物品名: '\(itemName ?? "")', 数量: \(quantityStr ?? "")")
                    }
                }
            }

            // 如果格式1也没有匹配，尝试格式2: 物品名称 + 空白字符 + 数量 + 可选的其他内容
            if itemName == nil {
                if let match = format2Regex.firstMatch(in: trimmedLine, options: [], range: range) {
                    if let nameRange = Range(match.range(at: 1), in: trimmedLine),
                       let quantityRange = Range(match.range(at: 2), in: trimmedLine)
                    {
                        itemName = String(trimmedLine[nameRange]).trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        quantityStr = String(trimmedLine[quantityRange])
                        Logger.debug("匹配格式2 - 物品名: '\(itemName ?? "")', 数量: \(quantityStr ?? "")")
                    }
                }
            }

            if let quantityStr = quantityStr, let itemName = itemName {
                Logger.debug("解析成功 - 物品名: '\(itemName)', 数量: \(quantityStr)")

                // 处理物品名末尾的*符号
                let cleanItemName = itemName.hasSuffix("*") ? String(itemName.dropLast()) : itemName
                Logger.debug("清理后的物品名: '\(cleanItemName)'")

                // 移除数量字符串中的逗号分隔符
                let cleanQuantityStr = quantityStr.replacingOccurrences(of: ",", with: "")

                if let quantity = Int64(cleanQuantityStr), quantity > 0 {
                    let validQuantity = min(quantity, 999_999_999)
                    itemsToImport.append((name: cleanItemName, quantity: validQuantity))
                    Logger.debug("添加到导入列表: \(cleanItemName) x \(validQuantity)")
                } else if Int64(cleanQuantityStr) != nil {
                    // 能解析出数字但不合法（如 0、负数）→ 视为失败
                    Logger.warning("数量不合法: \(quantityStr) -> \(cleanQuantityStr)")
                    failedLines.append(trimmedLine)
                } else {
                    // 解析不出数字，将整行视为物品名，由数据库校验；若合法则默认数量为 1
                    Logger.debug("无法解析数量，将整行视为物品名，默认数量 1: \(trimmedLine)")
                    itemsToImport.append((name: cleanItemName, quantity: 1))
                }
            } else {
                // 未匹配格式，将整行视为物品名，由数据库校验；若合法则默认数量为 1
                let cleanItemName = trimmedLine.hasSuffix("*") ? String(trimmedLine.dropLast()) : trimmedLine
                Logger.debug("无法匹配格式，将整行视为物品名，默认数量 1: \(cleanItemName)")
                itemsToImport.append((name: cleanItemName, quantity: 1))
            }
        }

        Logger.info("解析完成 - 成功解析: \(itemsToImport.count) 个, 失败: \(failedLines.count) 个")
        Logger.debug("待导入物品: \(itemsToImport.map { "\($0.name) x \($0.quantity)" })")
        Logger.debug("失败的行: \(failedLines)")

        // 如果没有解析到任何物品，返回失败
        if itemsToImport.isEmpty {
            return ParseResult(successCount: 0, failedItems: failedLines, updatedItems: [])
        }

        // 查询物品type_id
        let itemNames = itemsToImport.map { $0.name }
        Logger.debug("查询物品名称: \(itemNames)")
        let typeIDMap = getTypeIDsForNames(itemNames, databaseManager: databaseManager)
        Logger.debug("数据库查询结果: \(typeIDMap)")

        var successCount = 0
        var failedItems: [String] = []
        var updatedItems: [QuickbarItem] = []
        var typeIDQuantityMap: [Int: Int64] = [:] // 用于合并相同typeID的数量

        for item in itemsToImport {
            if let typeID = typeIDMap[item.name] {
                // 合并相同typeID的数量
                if let existingQuantity = typeIDQuantityMap[typeID] {
                    let newQuantity = existingQuantity + item.quantity
                    let validQuantity = min(newQuantity, 999_999_999) // 限制最大数量
                    typeIDQuantityMap[typeID] = validQuantity
                    Logger.debug("合并物品 \(item.name) (typeID: \(typeID)): \(existingQuantity) + \(item.quantity) = \(validQuantity)")
                } else {
                    typeIDQuantityMap[typeID] = item.quantity
                    Logger.debug("添加物品 \(item.name) (typeID: \(typeID)): \(item.quantity)")
                }
                successCount += 1
            } else {
                Logger.warning("数据库中未找到物品: \(item.name)")
                failedItems.append(item.name)
            }
        }

        // 将合并后的结果转换为QuickbarItem数组
        for (typeID, quantity) in typeIDQuantityMap {
            updatedItems.append(QuickbarItem(typeID: typeID, quantity: quantity))
        }

        Logger.info("导入完成 - 成功: \(successCount) 个, 失败: \(failedItems.count) 个")
        return ParseResult(
            successCount: successCount, failedItems: failedItems, updatedItems: updatedItems
        )
    }

    /// 根据物品名称获取type_id
    private static func getTypeIDsForNames(_ names: [String], databaseManager _: DatabaseManager)
        -> [String: Int]
    {
        guard !names.isEmpty else { return [:] }

        var typeIDMap: [String: Int] = [:]

        // 精确匹配全语种物品名（内存索引）
        for (typeID, info) in SDEMemoryStore.types {
            for name in names where info.names.matchesExact(name) {
                typeIDMap[name] = typeID
            }
        }

        return typeIDMap
    }
}
