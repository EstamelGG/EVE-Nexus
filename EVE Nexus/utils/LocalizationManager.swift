import Foundation

public class LocalizationManager {
    public static let shared = LocalizationManager()
    
    private var accountingEntryTypes: [String: [String: Any]] = [:]
    
    private init() {}
    
    public func loadAccountingEntryTypes() {
        // 调试：列出 bundle 中的所有资源
//        if let resourcePath = Bundle.main.resourcePath {
//            let fileManager = FileManager.default
//            do {
//                let items = try fileManager.contentsOfDirectory(atPath: resourcePath)
//                Logger.debug("Bundle 资源列表:")
//                for item in items {
//                    Logger.debug("- \(item)")
//                }
//            } catch {
//                Logger.error("无法列出 bundle 资源: \(error)")
//            }
//        }
        
        guard let path = Bundle.main.path(forResource: "accountingentrytypes_localized", ofType: "json") else {
            Logger.error("无法找到账目类型本地化文件")
            return
        }
        
        Logger.debug("正在从路径加载本地化文件: \(path)")
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                self.accountingEntryTypes = json
                Logger.debug("成功加载账目类型本地化数据")
            }
        } catch {
            Logger.error("解析账目类型本地化数据失败: \(error)")
        }
    }
    
    public func getEntryTypeName(for key: String, language: String = "en") -> String? {
        guard let entryType = accountingEntryTypes[key],
              let nameData = entryType["entryTypeName"] as? [String: String] else {
            return nil
        }
        return nameData[language]
    }
    
    public func getEntryJournalMessage(for key: String, language: String = "en") -> String? {
        guard let entryType = accountingEntryTypes[key],
              let messageData = entryType["entryJournalMessage"] as? [String: String] else {
            Logger.info("未找到 \(key) 的模板: entryJournalMessage")
            return nil
        }
        return messageData[language]
    }
    
    public func processTemplate(targetTemplate: String, englishTemplate: String, esiText: String) -> String {
        Logger.debug(
            """
                targetTemplate: \(targetTemplate)
                englishTemplate: \(englishTemplate),
                esiText: \(esiText)
            """
        )
        // 如果模板相同，直接返回原文
        if targetTemplate == englishTemplate {
            return esiText
        }
        
        do {
            // 1. 从英文模板中提取所有占位符
            let pattern = "\\{([^}]+)\\}"
            let regex = try NSRegularExpression(pattern: pattern)
            
            // 获取英文模板中的所有占位符
            let englishMatches = regex.matches(
                in: englishTemplate,
                range: NSRange(englishTemplate.startIndex..., in: englishTemplate)
            )
            
            if englishMatches.isEmpty { // 没匹配到占位符则直接返回目标模板文本
                return targetTemplate
            }
            
            // 2. 创建占位符到实际值的映射
            var placeholderValues: [String: String] = [:]
            
            // 将英文模板转换为正则表达式模式
            var extractPattern = englishTemplate
                .replacingOccurrences(of: ".", with: "\\.")
                .replacingOccurrences(of: "?", with: "\\?")
            
            // 替换所有占位符为捕获组
            for match in englishMatches {
                if let range = Range(match.range, in: englishTemplate) {
                    let placeholder = String(englishTemplate[range])
                    extractPattern = extractPattern.replacingOccurrences(
                        of: placeholder,
                        with: "(.+?)"
                    )
                }
            }
            
            // 3. 从ESI文本中提取实际值
            if let extractRegex = try? NSRegularExpression(pattern: "^" + extractPattern + "$"),
               let match = extractRegex.firstMatch(
                in: esiText,
                range: NSRange(esiText.startIndex..., in: esiText)
               ) {
                
                // 将占位符和实际值配对
                for (index, placeholder) in englishMatches.enumerated() {
                    if let placeholderRange = Range(placeholder.range, in: englishTemplate),
                       let valueRange = Range(match.range(at: index + 1), in: esiText) {
                        let placeholderName = String(englishTemplate[placeholderRange])
                        let value = String(esiText[valueRange])
                        placeholderValues[placeholderName] = value
                    }
                }
                
                // 4. 将值应用到目标语言模板
                var result = targetTemplate
                for (placeholder, value) in placeholderValues {
                    result = result.replacingOccurrences(of: placeholder, with: value)
                }
                
                return result
            }
        } catch {
            Logger.error("处理模板时发生错误: \(error)")
        }
        
        // 如果出现任何错误，返回原始ESI文本
        return esiText
    }
    
    // 便捷方法：处理日志消息模板
    public func processJournalMessage(for key: String, esiText: String, language: String = "en") -> String {
        Logger.debug(
            """
            key: \(key)
            esiText: \(esiText),
            language: \(language)
            """
        )
        guard language != "en" else {
            Logger.debug("无需转换，原文输出.")
            return esiText
        }
        
        let targetTemplate = getEntryJournalMessage(for: key, language: language)
        let englishTemplate = getEntryJournalMessage(for: key, language: "en")
        
        if targetTemplate == nil {
            Logger.debug("获取目标语言模板失败: key=\(key), language=\(language)")
        }
        if englishTemplate == nil {
            Logger.debug("获取英文模板失败: key=\(key)")
        }
        
        if let targetTemplate = targetTemplate,
           let englishTemplate = englishTemplate {
            let result = processTemplate(
                targetTemplate: targetTemplate,
                englishTemplate: englishTemplate,
                esiText: esiText
            )
            Logger.debug("模板转换: \(esiText) -> \(result)")
            return result
        }
        
        Logger.debug("模板转换错误，原文输出.")
        return esiText
    }
} 
