import Foundation

/// SDE 数据库语言列前缀（对应 `en_name` / `zh_name` 等）
enum SDELanguage {
    static let supportedPrefixes = ["de", "en", "es", "fr", "ja", "ko", "ru", "zh"]

    /// 将 `selectedDatabaseLanguage`（如 `zh-Hans`）转为列前缀（如 `zh`）
    static func columnPrefix(from databaseLanguage: String? = nil) -> String {
        let code = databaseLanguage
            ?? UserDefaults.standard.string(forKey: "selectedDatabaseLanguage")
            ?? "en"
        switch code {
        case "zh-Hans", "zh-Hant", "zh":
            return "zh"
        default:
            return supportedPrefixes.contains(code) ? code : "en"
        }
    }
}
