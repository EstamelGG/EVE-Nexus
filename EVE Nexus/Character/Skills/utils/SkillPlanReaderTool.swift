import Foundation

struct SkillPlanParseResult {
    let skills: [String]
    let parseErrors: [String]
    let notFoundSkills: [String]
    
    var hasErrors: Bool {
        return !parseErrors.isEmpty || !notFoundSkills.isEmpty
    }
}

class SkillPlanReaderTool {
    static func parseSkillPlan(from text: String, databaseManager: DatabaseManager) -> SkillPlanParseResult {
        var parseFailedLines: [String] = []
        var notFoundSkills: [String] = []
        var skills: [String] = []
        
        // 收集所有技能名称
        let lines = text.components(separatedBy: .newlines)
        var skillNames: Set<String> = []
        var skillLevels: [String: Int] = [:]
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty { continue }
            
            // 使用正则表达式匹配技能名称和等级
            let pattern = "^(.+?)\\s+(\\d+)$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)) {
                
                let nameRange = Range(match.range(at: 1), in: trimmedLine)!
                let levelRange = Range(match.range(at: 2), in: trimmedLine)!
                
                let skillName = String(trimmedLine[nameRange]).trimmingCharacters(in: .whitespaces)
                if let level = Int(trimmedLine[levelRange]),
                   level >= 1 && level <= 5 {
                    skillNames.insert(skillName)
                    skillLevels[skillName] = level
                } else {
                    parseFailedLines.append(trimmedLine)
                }
            } else {
                parseFailedLines.append(trimmedLine)
            }
        }
        
        // 如果有技能名称，查询它们的 type_id
        if !skillNames.isEmpty {
            let skillNamesString = skillNames.map { "'\($0)'" }.joined(separator: " UNION SELECT ")
            let query = """
                SELECT t.type_id, t.name
                FROM types t
                WHERE t.name IN (SELECT \(skillNamesString))
                AND t.categoryID = 16
            """
            
            let queryResult = databaseManager.executeQuery(query)
            var typeIdMap: [String: Int] = [:]
            
            switch queryResult {
            case .success(let rows):
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let name = row["name"] as? String {
                        typeIdMap[name] = typeId
                    }
                }
            case .error(let error):
                Logger.error("查询技能失败: \(error)")
            }
            
            // 检查哪些技能未找到
            for skillName in skillNames {
                if let typeId = typeIdMap[skillName],
                   let level = skillLevels[skillName] {
                    skills.append("\(typeId):\(level)")
                } else {
                    notFoundSkills.append(skillName)
                }
            }
        }
        
        return SkillPlanParseResult(
            skills: skills,
            parseErrors: parseFailedLines,
            notFoundSkills: notFoundSkills
        )
    }
} 
