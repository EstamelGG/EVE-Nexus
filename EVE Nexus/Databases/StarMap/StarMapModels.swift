import Foundation
import SwiftUI
import UIKit

// MARK: - 主题

enum StarMapTheme {
    static let background = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let chipAccent = Color(red: 0.35, green: 0.78, blue: 0.82)
}

// MARK: - 地图数据可用性

/// 地图数据可用性：systems_data 中实际包含的星域 ID 集合
/// SDE 初始化阶段随 loaders 预载，之后纯内存同步查询
/// 用于"查看地图"入口按需显隐——虫洞等不在地图数据中的星域不显示按钮
enum StarMapRegionAvailability {
    /// 地图数据包含的星域 ID（SDE 初始化预载）
    private(set) static var availableRegionIds: Set<Int> = []

    /// 同步查询星域是否在地图数据中
    static func isAvailable(_ regionId: Int) -> Bool {
        availableRegionIds.contains(regionId)
    }

    /// 预载（读 systems_data 顶层 key，SDE 初始化 loaders 调用）
    static func preload() {
        guard
            let url = StaticResourceManager.shared.getMapDataURL(filename: "systems_data"),
            let data = try? Data(contentsOf: url),
            let allSystems = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Logger.error("无法读取地图数据 systems_data，地图入口将全部隐藏")
            return
        }

        availableRegionIds = Set(allSystems.keys.compactMap { Int($0) })
        Logger.info("地图数据包含 \(availableRegionIds.count) 个星域")
    }
}

enum StarMapColors {
    /// 入侵标记色 #889A2F
    static let incursion = UIColor(red: 136 / 255, green: 154 / 255, blue: 47 / 255, alpha: 1)

    static func regionAccent(regionId: Int, factionId: Int) -> UIColor {
        switch regionId {
        case 10_000_070:
            return UIColor(red: 175 / 255, green: 46 / 255, blue: 30 / 255, alpha: 1)
        case 10_001_000:
            return .white
        case 10_001_004:
            return UIColor(red: 65 / 255, green: 115 / 255, blue: 212 / 255, alpha: 1) // 深蓝
        default:
            switch factionId {
            case 500_001:
                return UIColor(red: 165 / 255, green: 208 / 255, blue: 225 / 255, alpha: 1)
            case 500_002, 500_007:
                return UIColor(red: 148 / 255, green: 76 / 255, blue: 50 / 255, alpha: 1)
            case 500_003, 500_008:
                return UIColor(red: 251 / 255, green: 239 / 255, blue: 156 / 255, alpha: 1)
            case 500_004:
                return UIColor(red: 122 / 255, green: 174 / 255, blue: 159 / 255, alpha: 1)
            default:
                return UIColor(red: 134 / 255, green: 57 / 255, blue: 103 / 255, alpha: 1)
            }
        }
    }

    static func security(_ trueSec: Double) -> UIColor {
        UIColor(getSecurityColor(trueSec))
    }

    static func planetFilter(_ filter: RegionSystemMapView.PlanetFilter) -> UIColor {
        UIColor(filter.color)
    }

    static func darkened(_ color: UIColor, factor: CGFloat = 0.35) -> UIColor {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * factor, green: g * factor, blue: b * factor, alpha: a)
    }
}

extension View {
    /// 系统导航栏 + 深色内容底，避免切页闪白
    func starMapChrome(title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(StarMapTheme.background.ignoresSafeArea())
    }
}

// MARK: - 共享数据模型

struct Center: Codable {
    let x: Double
    let y: Double
}

// MARK: - 全星域地图数据结构 (regions_data.json)

struct RegionData: Codable {
    let region_id: Int
    let faction_id: Int
    let center: Center
    let relations: [String]
}

// MARK: - 星域地图数据结构 (systems_data.json 中的单个星域数据)

struct SystemMapData: Codable {
    let region_id: Int
    let faction_id: Int
    let center: Center
    let relations: [String]
    let systems: [String: SystemPosition]
    let jumps: [String: [String]]
}

struct SystemPosition: Codable {
    let x: Double
    let y: Double
}

struct SystemNodeData {
    let systemId: Int
    let name: String
    let security: Double
    let regionId: Int
    let position: CGPoint
    let connections: [Int]
    let planetCounts: PlanetCounts
    /// 相邻星域的跳接星系（仅作边界显示）
    var isExternal: Bool = false
}

struct PlanetCounts {
    let gas: Int
    let temperate: Int
    let barren: Int
    let oceanic: Int
    let ice: Int
    let lava: Int
    let storm: Int
    let plasma: Int
    let jove: Int

    init(
        gas: Int = 0, temperate: Int = 0, barren: Int = 0, oceanic: Int = 0,
        ice: Int = 0, lava: Int = 0, storm: Int = 0, plasma: Int = 0, jove: Int = 0
    ) {
        self.gas = gas
        self.temperate = temperate
        self.barren = barren
        self.oceanic = oceanic
        self.ice = ice
        self.lava = lava
        self.storm = storm
        self.plasma = plasma
        self.jove = jove
    }

    func getCount(for filter: RegionSystemMapView.PlanetFilter) -> Int {
        switch filter {
        case .all:
            return gas + temperate + barren + oceanic + ice + lava + storm + plasma + jove
        case .gas:
            return gas
        case .temperate:
            return temperate
        case .barren:
            return barren
        case .oceanic:
            return oceanic
        case .ice:
            return ice
        case .lava:
            return lava
        case .storm:
            return storm
        case .plasma:
            return plasma
        case .jove:
            return jove
        }
    }
}

// MARK: - 入侵状态

enum StarMapIncursions {
    /// 获取当前所有受入侵影响的星系；集结星系一并纳入，避免其未出现在 infested 列表中时漏标
    static func fetchInvadedSystemIDs() async -> Set<Int> {
        do {
            let incursions = try await IncursionsAPI.shared.fetchIncursions()
            let systemIDs = incursions.flatMap {
                $0.infestedSolarSystems + [$0.stagingSolarSystemId]
            }
            Logger.info("星图入侵状态检查完成，受入侵影响星系数: \(Set(systemIDs).count)")
            return Set(systemIDs)
        } catch {
            Logger.error("星图入侵状态检查失败: \(error)")
            return []
        }
    }
}

// MARK: - 导航枚举

enum RegionNavigation: Hashable, Identifiable {
    case regionMap(Int, String, [Int]) // regionId, regionName, highlightSystemIds

    var id: Int {
        switch self {
        case let .regionMap(regionId, _, _):
            return regionId
        }
    }
}
