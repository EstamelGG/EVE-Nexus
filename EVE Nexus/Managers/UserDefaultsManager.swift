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
        static let pinnedAssetLocationIDs = "pinnedAssetLocationIDs"
        static let mergeSimilarTransactions = "mergeSimilarTransactions"
        static let LPStoreUpdatetime = "LPStoreUpdatetime"
        static let LPStoreFullLoadCount = "LPStoreFullLoadCount"
        static let refineryTaxRate = "refineryTaxRate"
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

    // 获取指定角色的置顶资产位置ID列表
    func getPinnedAssetLocationIDs(for characterId: Int) -> [Int64] {
        let key = "\(Keys.pinnedAssetLocationIDs)_\(characterId)"
        return defaults.array(forKey: key) as? [Int64] ?? []
    }

    // 设置指定角色的置顶资产位置ID列表
    func setPinnedAssetLocationIDs(_ locationIDs: [Int64], for characterId: Int) {
        let key = "\(Keys.pinnedAssetLocationIDs)_\(characterId)"
        defaults.set(locationIDs, forKey: key)
    }

    // 添加置顶资产位置
    func addPinnedAssetLocation(_ locationID: Int64, for characterId: Int) {
        var pinnedIDs = getPinnedAssetLocationIDs(for: characterId)
        if !pinnedIDs.contains(locationID) {
            pinnedIDs.append(locationID)
            setPinnedAssetLocationIDs(pinnedIDs, for: characterId)
        }
    }

    // 移除置顶资产位置
    func removePinnedAssetLocation(_ locationID: Int64, for characterId: Int) {
        var pinnedIDs = getPinnedAssetLocationIDs(for: characterId)
        pinnedIDs.removeAll { $0 == locationID }
        setPinnedAssetLocationIDs(pinnedIDs, for: characterId)
    }

    // 检查资产位置是否已置顶
    func isAssetLocationPinned(_ locationID: Int64, for characterId: Int) -> Bool {
        let pinnedIDs = getPinnedAssetLocationIDs(for: characterId)
        return pinnedIDs.contains(locationID)
    }

    // 交易记录合并设置（全局设置，对所有人物生效）
    var mergeSimilarTransactions: Bool {
        get {
            return defaults.bool(forKey: Keys.mergeSimilarTransactions)
        }
        set {
            defaults.set(newValue, forKey: Keys.mergeSimilarTransactions)
        }
    }

    // LP商店数据更新时间
    var LPStoreUpdatetime: Date? {
        get {
            return defaults.object(forKey: Keys.LPStoreUpdatetime) as? Date
        }
        set {
            defaults.set(newValue, forKey: Keys.LPStoreUpdatetime)
        }
    }

    // LP商店全量加载条数
    var LPStoreFullLoadCount: Int {
        get {
            return defaults.integer(forKey: Keys.LPStoreFullLoadCount)
        }
        set {
            defaults.set(newValue, forKey: Keys.LPStoreFullLoadCount)
        }
    }

    // 精炼税率设置
    var refineryTaxRate: Double {
        get {
            return defaults.double(forKey: Keys.refineryTaxRate)
        }
        set {
            defaults.set(newValue, forKey: Keys.refineryTaxRate)
        }
    }
}
