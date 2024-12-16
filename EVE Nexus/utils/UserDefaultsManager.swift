import Foundation

/// 用户设置管理器
/// 统一管理应用程序的用户设置
class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    private let defaults = UserDefaults.standard
    
    // MARK: - 键名定义
    private struct Keys {
        // 数据库相关
        struct Database {
            static let isSimplifiedMode = "database.itemInfo.isSimplifiedMode"
        }
        
        // 市场相关
        struct Market {
            static let selectedRegionID = "market.selectedRegionID"
        }
    }
    
    // MARK: - 数据库设置
    var isSimplifiedMode: Bool {
        get { defaults.bool(forKey: Keys.Database.isSimplifiedMode) }
        set { defaults.set(newValue, forKey: Keys.Database.isSimplifiedMode) }
    }
    
    // MARK: - 市场设置
    var selectedRegionID: Int {
        get { defaults.integer(forKey: Keys.Market.selectedRegionID) }
        set { defaults.set(newValue, forKey: Keys.Market.selectedRegionID) }
    }
    
    // MARK: - 初始化
    private init() {
        // 设置默认值
        if defaults.object(forKey: Keys.Market.selectedRegionID) == nil {
            defaults.set(10000002, forKey: Keys.Market.selectedRegionID) // 默认为 The Forge (Jita)
        }
        
        // 设置属性显示模式的默认值
        if defaults.object(forKey: Keys.Database.isSimplifiedMode) == nil {
            defaults.set(true, forKey: Keys.Database.isSimplifiedMode) // 默认使用简化模式
        }
    }
} 