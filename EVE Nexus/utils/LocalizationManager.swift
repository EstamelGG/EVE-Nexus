import Foundation

public class LocalizationManager {
    public static let shared = LocalizationManager()

    private var accountingEntryTypes: [String: [String: Any]] = [:]

    private init() {}

    public func loadAccountingEntryTypes() {
        // 使用StaticResourceManager获取本地化文件路径
        guard let path = StaticResourceManager.shared.getLocalizationPath(filename: "accountingentrytypes_localized") else {
            Logger.error("无法找到账目类型本地化文件")
            return
        }

        Logger.debug("正在从路径加载本地化文件: \(path)")

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                accountingEntryTypes = json
                Logger.debug("成功加载账目类型本地化数据")
            }
        } catch {
            Logger.error("解析账目类型本地化数据失败: \(error)")
        }
    }

    public func getEntryTypeName(for key: String, language: String = "en") -> [String]? {
        guard let entryType = accountingEntryTypes[key],
              let nameData = entryType["entryTypeName"] as? [String: [String]]
        else {
            return nil
        }
        return nameData[language]
    }

    public func getEntryJournalMessage(for key: String, language: String = "en") -> [String]? {
        guard let entryType = accountingEntryTypes[key],
              let messageData = entryType["entryJournalMessage"] as? [String: [String]]
        else {
            Logger.info("未找到 \(key) 的模板: entryJournalMessage")
            return nil
        }
        return messageData[language]
    }

    public func processTemplate(
        targetTemplate: String, englishTemplate: String, esiText: String,
        enTemplateMustMatch: Bool = false
    )
        -> String
    {
        Logger.debug(
            """
                targetTemplate: \(targetTemplate)
                englishTemplate: \(englishTemplate)
                esiText: \(esiText)
                checkExactMatch: \(enTemplateMustMatch)
            """
        )

        // 1. 使用正则表达式提取占位符
        let pattern = "\\{([^}]+)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            Logger.error("正则表达式创建失败")
            return esiText
        }

        let nsString = englishTemplate as NSString
        let matches = regex.matches(
            in: englishTemplate, range: NSRange(location: 0, length: nsString.length)
        )

        // 如果没有找到占位符，根据checkExactMatch参数决定是否检查英文模板匹配度
        if matches.isEmpty {
            if enTemplateMustMatch {
                if englishTemplate == esiText {
                    Logger.info("英文模板与esiText完全匹配，返回目标模板: \(targetTemplate)")
                    return targetTemplate
                } else {
                    Logger.info("英文模板与esiText不匹配，返回esiText: \(esiText)")
                    return esiText
                }
            } else {
                Logger.info("未找到占位符且不检查匹配度，返回目标模板: \(targetTemplate)")
                return targetTemplate
            }
        }

        // 2. 构建正则表达式模式
        var patternParts: [String] = []
        var lastEnd = 0

        for match in matches {
            // 添加占位符前的固定文本
            if match.range.location > lastEnd {
                let text = nsString.substring(
                    with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                patternParts.append(NSRegularExpression.escapedPattern(for: text))
            }

            // 添加占位符匹配模式
            patternParts.append("(.+?)")

            lastEnd = match.range.location + match.range.length
        }

        // 添加最后一个占位符后的固定文本
        if lastEnd < nsString.length {
            let text = nsString.substring(
                with: NSRange(location: lastEnd, length: nsString.length - lastEnd))
            patternParts.append(NSRegularExpression.escapedPattern(for: text))
        }

        let fullPattern = "^" + patternParts.joined() + "$"
        Logger.debug("构建的正则表达式模式: \(fullPattern)")

        // 3. 使用正则表达式匹配并提取值
        guard let matchRegex = try? NSRegularExpression(pattern: fullPattern) else {
            Logger.error("匹配正则表达式创建失败")
            return esiText
        }

        let nsEsiText = esiText as NSString
        guard
            let match = matchRegex.firstMatch(
                in: esiText, range: NSRange(location: 0, length: nsEsiText.length)
            )
        else {
            Logger.info("无法匹配文本，返回原文: \(esiText)")
            return esiText
        }

        // 4. 提取所有匹配的值
        var values: [String: String] = [:]
        for i in 0 ..< matches.count {
            let range = match.range(at: i + 1)
            let value = nsEsiText.substring(with: range)
            let placeholder = nsString.substring(with: matches[i].range)
            values[placeholder] = value
            Logger.debug("提取到值: \(placeholder) = '\(value)'")
        }

        // 5. 将值应用到目标模板
        var result = targetTemplate
        for (placeholder, value) in values {
            result = result.replacingOccurrences(of: placeholder, with: value)
            Logger.debug("替换 \(placeholder) 为 '\(value)'")
        }

        Logger.info("处理完成，返回结果: \(result)")
        return result
    }

    // 便捷方法：处理日志消息模板
    public func processJournalMessage(for key: String, esiText: String, language: String = "en")
        -> String
    {
        Logger.debug(
            """
            key: \(key)
            esiText: \(esiText)
            language: \(language)
            """
        )

        let targetTemplates = getEntryJournalMessage(for: key, language: language)
        let englishTemplates = getEntryJournalMessage(for: key, language: "en")

        if targetTemplates == nil {
            Logger.debug("[JournalMessage] 获取目标语言模板失败: key=\(key), language=\(language)")
        }
        if englishTemplates == nil {
            Logger.debug("[JournalMessage] 获取英文模板失败: key=\(key)")
        }

        if let targetTemplates = targetTemplates,
           let englishTemplates = englishTemplates
        {
            // 确保两个数组长度相同
            guard targetTemplates.count == englishTemplates.count else {
                Logger.error("[JournalMessage] 目标语言模板数量与英文模板数量不匹配")
                return esiText
            }

            // 尝试每个模板对
            for (targetTemplate, englishTemplate) in zip(targetTemplates, englishTemplates) {
                let result = processTemplate(
                    targetTemplate: targetTemplate,
                    englishTemplate: englishTemplate,
                    esiText: esiText,
                    enTemplateMustMatch: true
                )

                // 如果结果与原文不同，说明匹配成功
                if result != esiText {
                    Logger.debug("[JournalMessage] 模板转换成功: \(esiText) -> \(result)")
                    return result
                }
            }

            Logger.debug("[JournalMessage] 所有模板都未能匹配，返回原文")
        }

        Logger.debug("[JournalMessage] 模板转换错误，原文输出. -2")
        return esiText
    }

    // 处理账目类型名称
    public func processEntryTypeName(for key: String, esiText: String, language: String = "en")
        -> String
    {
        Logger.debug(
            """
            key: \(key)
            esiText: \(esiText),
            language: \(language)
            """
        )

        let targetTemplates = getEntryTypeName(for: key, language: language)
        let englishTemplates = getEntryTypeName(for: key, language: "en")

        if targetTemplates == nil {
            Logger.debug("[EntryTypeName] 获取目标语言模板失败: key=\(key), language=\(language)")
        }
        if englishTemplates == nil {
            Logger.debug("[EntryTypeName] 获取英文模板失败: key=\(key)")
        }

        if let targetTemplates = targetTemplates,
           let englishTemplates = englishTemplates
        {
            // 确保两个数组长度相同
            guard targetTemplates.count == englishTemplates.count else {
                Logger.error("[EntryTypeName] 目标语言模板数量与英文模板数量不匹配")
                return esiText
            }

            // 尝试每个模板对
            for (targetTemplate, englishTemplate) in zip(targetTemplates, englishTemplates) {
                let result = processTemplate(
                    targetTemplate: targetTemplate,
                    englishTemplate: englishTemplate,
                    esiText: esiText,
                    enTemplateMustMatch: false
                )

                // 如果结果与原文不同，说明匹配成功
                if result != esiText {
                    Logger.debug("[EntryTypeName] 模板转换成功: \(esiText) -> \(result)")
                    return result
                }
            }

            Logger.debug("[EntryTypeName] 所有模板都未能匹配，返回原文")
        }

        Logger.debug("[EntryTypeName] 模板转换错误，原文输出. -1")
        return esiText
    }
}
