import Foundation

class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    private let defaults = UserDefaults.standard
    
    // 键名常量
    private struct Keys {
        static let selectedRegionID = "selectedRegionID"
        static let pinnedRegionIDs = "pinnedRegionIDs"
        static let selectedLanguage = "selectedLanguage"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let lastDatabaseUpdate = "lastDatabaseUpdate"
        static let lastMarketUpdate = "lastMarketUpdate"
        static let isSimplifiedMode = "isSimplifiedMode"
    }
    
    private init() {}
    
    // 选中的星域ID
    var selectedRegionID: Int {
        get {
            defaults.integer(forKey: Keys.selectedRegionID)
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedRegionID)
        }
    }
    
    // 置顶的星域ID列表
    var pinnedRegionIDs: [Int] {
        get {
            defaults.array(forKey: Keys.pinnedRegionIDs) as? [Int] ?? []
        }
        set {
            defaults.set(newValue, forKey: Keys.pinnedRegionIDs)
        }
    }
    
    // 选中的语言
    var selectedLanguage: String {
        get {
            defaults.string(forKey: Keys.selectedLanguage) ?? "en"
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedLanguage)
        }
    }
    
    // 是否使用简化模式
    var isSimplifiedMode: Bool {
        get {
            defaults.bool(forKey: Keys.isSimplifiedMode)
        }
        set {
            defaults.set(newValue, forKey: Keys.isSimplifiedMode)
        }
    }
    
    // 最后检查更新时间
    var lastUpdateCheck: Date? {
        get {
            defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        }
        set {
            defaults.set(newValue, forKey: Keys.lastUpdateCheck)
        }
    }
    
    // 最后数据库更新时间
    var lastDatabaseUpdate: Date? {
        get {
            defaults.object(forKey: Keys.lastDatabaseUpdate) as? Date
        }
        set {
            defaults.set(newValue, forKey: Keys.lastDatabaseUpdate)
        }
    }
    
    // 最后市场数据更新时间
    var lastMarketUpdate: Date? {
        get {
            defaults.object(forKey: Keys.lastMarketUpdate) as? Date
        }
        set {
            defaults.set(newValue, forKey: Keys.lastMarketUpdate)
        }
    }
} 