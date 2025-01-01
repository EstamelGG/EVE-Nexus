import Foundation

class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    private let defaults = UserDefaults.standard
    
    // The Forge 的 regionID 是 10000002
    private let defaultRegionID = 10000002
    let defaultRegionName = "The Forge"
    
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
            // Logger.debug("正在从 UserDefaults 读取键: \(Keys.selectedRegionID)")
            return defaults.integer(forKey: Keys.selectedRegionID) == 0 ? defaultRegionID : defaults.integer(forKey: Keys.selectedRegionID)
        }
        set {
            // Logger.debug("正在写入 UserDefaults，键: \(Keys.selectedRegionID), 值: \(newValue), 数据大小: \(MemoryLayout<Int>.size) bytes")
            defaults.set(newValue, forKey: Keys.selectedRegionID)
        }
    }
    
    // 置顶的星域ID列表
    var pinnedRegionIDs: [Int] {
        get {
            // Logger.debug("正在从 UserDefaults 读取键: \(Keys.pinnedRegionIDs)")
            if defaults.object(forKey: Keys.pinnedRegionIDs) == nil {
                return [defaultRegionID]
            }
            return defaults.array(forKey: Keys.pinnedRegionIDs) as? [Int] ?? []
        }
        set {
            // Logger.debug("正在写入 UserDefaults，键: \(Keys.pinnedRegionIDs), 值: \(newValue), 数据大小: \(MemoryLayout<Int>.size * newValue.count) bytes")
            defaults.set(newValue, forKey: Keys.pinnedRegionIDs)
        }
    }
    
    // 选中的语言
    var selectedLanguage: String {
        get {
            // Logger.debug("正在从 UserDefaults 读取键: \(Keys.selectedLanguage)")
            return defaults.string(forKey: Keys.selectedLanguage) ?? "en"
        }
        set {
            // Logger.debug("正在写入 UserDefaults，键: \(Keys.selectedLanguage), 值: \(newValue), 数据大小: \(newValue.utf8.count) bytes")
            defaults.set(newValue, forKey: Keys.selectedLanguage)
        }
    }
    
    // 是否使用简化模式
    var isSimplifiedMode: Bool {
        get {
            // Logger.debug("正在从 UserDefaults 读取键: \(Keys.isSimplifiedMode)")
            return defaults.bool(forKey: Keys.isSimplifiedMode)
        }
        set {
            // Logger.debug("正在写入 UserDefaults，键: \(Keys.isSimplifiedMode), 值: \(newValue), 数据大小: \(MemoryLayout<Bool>.size) bytes")
            defaults.set(newValue, forKey: Keys.isSimplifiedMode)
        }
    }
    
    // 最后检查更新时间
    var lastUpdateCheck: Date? {
        get {
            // Logger.debug("正在从 UserDefaults 读取键: \(Keys.lastUpdateCheck)")
            return defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        }
        set {
            // Logger.debug("正在写入 UserDefaults，键: \(Keys.lastUpdateCheck), 值: \(String(describing: newValue)), 数据大小: \(MemoryLayout<Date>.size) bytes")
            defaults.set(newValue, forKey: Keys.lastUpdateCheck)
        }
    }
    
    // 最后数据库更新时间
    var lastDatabaseUpdate: Date? {
        get {
            // Logger.debug("正在从 UserDefaults 读取键: \(Keys.lastDatabaseUpdate)")
            return defaults.object(forKey: Keys.lastDatabaseUpdate) as? Date
        }
        set {
            // Logger.debug("正在写入 UserDefaults，键: \(Keys.lastDatabaseUpdate), 值: \(String(describing: newValue)), 数据大小: \(MemoryLayout<Date>.size) bytes")
            defaults.set(newValue, forKey: Keys.lastDatabaseUpdate)
        }
    }
    
    // 最后市场数据更新时间
    var lastMarketUpdate: Date? {
        get {
            // Logger.debug("正在从 UserDefaults 读取键: \(Keys.lastMarketUpdate)")
            return defaults.object(forKey: Keys.lastMarketUpdate) as? Date
        }
        set {
            // Logger.debug("正在写入 UserDefaults，键: \(Keys.lastMarketUpdate), 值: \(String(describing: newValue)), 数据大小: \(MemoryLayout<Date>.size) bytes")
            defaults.set(newValue, forKey: Keys.lastMarketUpdate)
        }
    }
} 
