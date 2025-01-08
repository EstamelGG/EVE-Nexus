import Foundation

class SkillPlanReaderTool {
    static func parseSkillPlan(from text: String, databaseManager: DatabaseManager) -> [String] {
        // 将输入文本按行分割
        let lines = text.components(separatedBy: .newlines)
        
        // 存储解析出的技能名称和等级
        var skillsWithLevel: [(name: String, level: Int)] = []
        
        // 解析每一行
        for (index, line) in lines.enumerated() {
            // 跳过空行
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            
            // 使用最后一个空格分割技能名称和等级
            let components = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            
            // 检查格式是否正确
            guard components.count == 2,
                  let lastComponent = components.last,
                  let level = Int(lastComponent),
                  level >= 1 && level <= 5 else {
                Logger.error("技能计划解析失败 - 行 \(index + 1): \(line)")
                continue
            }
            
            // 获取技能名称（除最后一个空格及数字外的所有内容）
            let skillName = line.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " \(lastComponent)$", with: "", options: .regularExpression)
            
            skillsWithLevel.append((name: skillName, level: level))
        }
        
        // 如果没有解析出任何技能，直接返回空数组
        if skillsWithLevel.isEmpty {
            Logger.error("技能计划解析失败 - 未找到任何有效的技能行")
            return []
        }
        
        // 获取去重后的技能名称集合
        let uniqueSkillNames = Set(skillsWithLevel.map { $0.name })
        Logger.debug("解析出 \(skillsWithLevel.count) 个技能条目，去重后剩余 \(uniqueSkillNames.count) 个不同技能")
        
        // 构建SQL查询
        let skillNamesForQuery = uniqueSkillNames.map { "'\($0)'" }.joined(separator: ",")
        let query = "SELECT type_id, name FROM types WHERE name IN (\(skillNamesForQuery))"
        
        // 执行查询
        var typeIdMap: [String: Int] = [:]
        let queryResult = databaseManager.executeQuery(query)
        
        switch queryResult {
        case .success(let rows):
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String {
                    typeIdMap[name] = typeId
                }
            }
            
            // 检查哪些技能名称没有找到
            let foundSkillNames = Set(typeIdMap.keys)
            let notFoundSkillNames = uniqueSkillNames.subtracting(foundSkillNames)
            
            if !notFoundSkillNames.isEmpty {
                Logger.error("以下技能未找到:")
                for skillName in notFoundSkillNames {
                    Logger.error("- \(skillName)")
                }
            }
            
        case .error(let error):
            Logger.error("查询技能ID失败: \(error)")
            return []
        }
        
        // 构建最终结果
        var finalResult: [String] = []
        for skill in skillsWithLevel {
            let typeId = typeIdMap[skill.name] ?? 0
            if typeId == 0 {
                Logger.error("未找到技能: \(skill.name)")
            }
            finalResult.append("\(typeId):\(skill.level)")
        }
        
        return finalResult
    }
} 