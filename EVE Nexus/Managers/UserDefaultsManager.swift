import Foundation

class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    private let defaults = UserDefaults.standard

    // The Forge 的 regionID 是 10000002
    private let defaultRegionID = 10_000_002

    // 键名常量
    private enum Keys {
        static let selectedRegionID = "selectedRegionID"
        static let pinnedRegionIDs = "pinnedRegionIDs"
    }

    private init() {}

    // 选中的星域ID
    var selectedRegionID: Int {
        get {
            // Logger.debug("正在从 UserDefaults 读取键: \(Keys.selectedRegionID)")
            return defaults.integer(forKey: Keys.selectedRegionID) == 0
                ? defaultRegionID : defaults.integer(forKey: Keys.selectedRegionID)
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
}
