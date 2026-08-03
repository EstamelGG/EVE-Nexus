import Foundation

class UserDefaultsManager {
    static let shared = UserDefaultsManager()
    private let defaults = UserDefaults.standard

    /// The Forge 的 regionID 是 10000002
    private let defaultRegionID = MarketManager.theForgeRegionID

    /// 键名常量
    private enum Keys {
        static let selectedLocation = "selectedLocation"
        static let pinnedRegionIDs = "pinnedRegionIDs"
        static let pinnedLocationIDs = "pinnedLocationIDs"
        static let pinnedAssetLocationIDs = "pinnedAssetLocationIDs"
        static let mergeSimilarTransactions = "mergeSimilarTransactions"
        static let refineryTaxRate = "refineryTaxRate"
    }

    private init() {}

    /// 选中的市场地点 ID（正数=星域或星系，负数=建筑虚拟 ID）
    /// 类型由 MarketLocationType.from(id:) 在运行时判断，无需额外存储
    var selectedLocation: Int {
        get {
            if defaults.object(forKey: Keys.selectedLocation) != nil {
                let val = defaults.integer(forKey: Keys.selectedLocation)
                return val == 0 ? defaultRegionID : val
            }
            // 从旧格式迁移：selectedRegionID → selectedLocation
            let oldKey = "selectedRegionID"
            if defaults.object(forKey: oldKey) != nil {
                let oldVal = defaults.integer(forKey: oldKey)
                let migrated = oldVal == 0 ? defaultRegionID : oldVal
                defaults.set(migrated, forKey: Keys.selectedLocation)
                return migrated
            }
            return defaultRegionID
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedLocation)
        }
    }

    /// 置顶的星域ID列表（旧格式，仅存星域ID）
    var pinnedRegionIDs: [Int] {
        get {
            if defaults.object(forKey: Keys.pinnedRegionIDs) == nil {
                return [defaultRegionID]
            }
            return defaults.array(forKey: Keys.pinnedRegionIDs) as? [Int] ?? []
        }
        set {
            defaults.set(newValue, forKey: Keys.pinnedRegionIDs)
        }
    }

    /// 置顶的地点列表（新格式，支持星域/星系/建筑）
    /// 格式：region_id:10000002 / system_id:30000142 / structure_id:1034567890123
    var pinnedLocationIDs: [String] {
        get {
            if defaults.object(forKey: Keys.pinnedLocationIDs) != nil {
                return defaults.stringArray(forKey: Keys.pinnedLocationIDs) ?? []
            }
            // 从旧格式迁移：将 pinnedRegionIDs 转为新格式
            let migrated = pinnedRegionIDs.map { "region_id:\($0)" }
            if !migrated.isEmpty {
                defaults.set(migrated, forKey: Keys.pinnedLocationIDs)
            }
            return migrated
        }
        set {
            defaults.set(newValue, forKey: Keys.pinnedLocationIDs)
        }
    }

    /// 获取指定角色的置顶资产位置ID列表
    func getPinnedAssetLocationIDs(for characterId: Int) -> [Int64] {
        let key = "\(Keys.pinnedAssetLocationIDs)_\(characterId)"
        return defaults.array(forKey: key) as? [Int64] ?? []
    }

    /// 设置指定角色的置顶资产位置ID列表
    func setPinnedAssetLocationIDs(_ locationIDs: [Int64], for characterId: Int) {
        let key = "\(Keys.pinnedAssetLocationIDs)_\(characterId)"
        defaults.set(locationIDs, forKey: key)
    }

    /// 添加置顶资产位置
    func addPinnedAssetLocation(_ locationID: Int64, for characterId: Int) {
        var pinnedIDs = getPinnedAssetLocationIDs(for: characterId)
        if !pinnedIDs.contains(locationID) {
            pinnedIDs.append(locationID)
            setPinnedAssetLocationIDs(pinnedIDs, for: characterId)
        }
    }

    /// 移除置顶资产位置
    func removePinnedAssetLocation(_ locationID: Int64, for characterId: Int) {
        var pinnedIDs = getPinnedAssetLocationIDs(for: characterId)
        pinnedIDs.removeAll { $0 == locationID }
        setPinnedAssetLocationIDs(pinnedIDs, for: characterId)
    }

    /// 检查资产位置是否已置顶
    func isAssetLocationPinned(_ locationID: Int64, for characterId: Int) -> Bool {
        let pinnedIDs = getPinnedAssetLocationIDs(for: characterId)
        return pinnedIDs.contains(locationID)
    }

    // MARK: - 军团资产置顶功能（使用corporationId）

    /// 获取指定军团的置顶资产位置ID列表
    func getPinnedAssetLocationIDs(forCorporation corporationId: Int) -> [Int64] {
        let key = "\(Keys.pinnedAssetLocationIDs)_corp_\(corporationId)"
        return defaults.array(forKey: key) as? [Int64] ?? []
    }

    /// 设置指定军团的置顶资产位置ID列表
    func setPinnedAssetLocationIDs(_ locationIDs: [Int64], forCorporation corporationId: Int) {
        let key = "\(Keys.pinnedAssetLocationIDs)_corp_\(corporationId)"
        defaults.set(locationIDs, forKey: key)
    }

    /// 添加置顶资产位置
    func addPinnedAssetLocation(_ locationID: Int64, forCorporation corporationId: Int) {
        var pinnedIDs = getPinnedAssetLocationIDs(forCorporation: corporationId)
        if !pinnedIDs.contains(locationID) {
            pinnedIDs.append(locationID)
            setPinnedAssetLocationIDs(pinnedIDs, forCorporation: corporationId)
        }
    }

    /// 移除置顶资产位置
    func removePinnedAssetLocation(_ locationID: Int64, forCorporation corporationId: Int) {
        var pinnedIDs = getPinnedAssetLocationIDs(forCorporation: corporationId)
        pinnedIDs.removeAll { $0 == locationID }
        setPinnedAssetLocationIDs(pinnedIDs, forCorporation: corporationId)
    }

    /// 检查资产位置是否已置顶
    func isAssetLocationPinned(_ locationID: Int64, forCorporation corporationId: Int) -> Bool {
        let pinnedIDs = getPinnedAssetLocationIDs(forCorporation: corporationId)
        return pinnedIDs.contains(locationID)
    }

    /// 交易记录合并设置（全局设置，对所有人物生效）
    var mergeSimilarTransactions: Bool {
        get {
            return defaults.bool(forKey: Keys.mergeSimilarTransactions)
        }
        set {
            defaults.set(newValue, forKey: Keys.mergeSimilarTransactions)
        }
    }

    /// 精炼税率设置
    var refineryTaxRate: Double {
        get {
            return defaults.double(forKey: Keys.refineryTaxRate)
        }
        set {
            defaults.set(newValue, forKey: Keys.refineryTaxRate)
        }
    }
}
