import Foundation

class SkillPlanReaderTool {
    static func parseSkillPlan(from text: String, databaseManager: DatabaseManager) -> [String] {
        Logger.debug("开始解析技能计划文本...")
        
        // 将输入文本按行分割
        let lines = text.components(separatedBy: .newlines)
        Logger.debug("总行数: \(lines.count)")
        
        // 存储解析出的技能名称和等级
        var skillsWithLevel: [(name: String, level: Int)] = []
        var parseFailedLines: [(lineNumber: Int, content: String)] = []
        
        // 解析每一行
        for (index, line) in lines.enumerated() {
            // 跳过空行
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty {
                Logger.debug("第 \(index + 1) 行: 空行，已跳过")
                continue
            }
            
            // 使用正则表达式匹配行尾的数字
            let pattern = #"^(.+?)\s+(\d+)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) else {
                parseFailedLines.append((index + 1, trimmedLine))
                continue
            }
            
            // 提取技能名称和等级
            guard let nameRange = Range(match.range(at: 1), in: trimmedLine),
                  let levelRange = Range(match.range(at: 2), in: trimmedLine),
                  let level = Int(trimmedLine[levelRange]),
                  level >= 1 && level <= 5 else {
                parseFailedLines.append((index + 1, trimmedLine))
                continue
            }
            
            let skillName = String(trimmedLine[nameRange]).trimmingCharacters(in: .whitespaces)
            if skillName.isEmpty {
                parseFailedLines.append((index + 1, trimmedLine))
                continue
            }
            
            skillsWithLevel.append((name: skillName, level: level))
            // Logger.debug("第 \(index + 1) 行: 成功解析 - 技能: \(skillName), 等级: \(level)")
        }
        
        // 显示解析失败的行
        if !parseFailedLines.isEmpty {
            Logger.error("以下行解析失败:")
            for failedLine in parseFailedLines {
                Logger.error("- 第 \(failedLine.lineNumber) 行: \(failedLine.content)")
            }
        }
        
        // 如果没有解析出任何技能，直接返回空数组
        if skillsWithLevel.isEmpty {
            Logger.error("技能计划解析失败 - 未找到任何有效的技能行")
            return []
        }
        
        // 获取去重后的技能名称集合
        let uniqueSkillNames = Set(skillsWithLevel.map { $0.name })
        Logger.debug("解析出 \(skillsWithLevel.count) 个技能条目，去重后剩余 \(uniqueSkillNames.count) 个不同技能")
        
        // 构建SQL查询，使用子查询和UNION来处理未找到的技能名称
        let skillNamesValues = uniqueSkillNames.map { "SELECT '\($0)' as name" }.joined(separator: " UNION ")
        let query = """
            SELECT COALESCE(t.type_id, 0) as type_id, s.name
            FROM (\(skillNamesValues)) s
            LEFT JOIN types t ON t.name = s.name
        """
        Logger.debug("执行SQL查询: \(query)")
        
        // 执行查询
        var typeIdMap: [String: Int] = [:]
        let queryResult = databaseManager.executeQuery(query)
        
        switch queryResult {
        case .success(let rows):
            Logger.debug("SQL查询成功，返回 \(rows.count) 条结果")
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    typeIdMap[name] = typeId
                    if typeId == 0 {
                        Logger.error("未找到技能: \(name)")
                    }
                }
            }
            
        case .error(let error):
            Logger.error("SQL查询失败: \(error)")
            return []
        }
        
        // 构建最终结果
        var finalResult: [String] = []
        for skill in skillsWithLevel {
            let typeId = typeIdMap[skill.name] ?? 0
            finalResult.append("\(typeId):\(skill.level)")
        }
        
        Logger.debug("技能计划解析完成，返回 \(finalResult.count) 个结果")
        return finalResult
    }
} 
