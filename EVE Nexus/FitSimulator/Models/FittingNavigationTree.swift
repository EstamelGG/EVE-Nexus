import Foundation

// MARK: - 预构造导航树（VM 加载时构建：排序、单装配拍平一次完成，视图纯渲染）

/// 装配行节点：与装配 ref 关联
struct FittingItemNode: Hashable, Identifiable {
    let ref: FittingRef
    let name: String
    let shipTypeId: Int

    var id: String {
        ref.debugDescription
    }

    static func == (lhs: FittingItemNode, rhs: FittingItemNode) -> Bool {
        lhs.ref == rhs.ref
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ref)
    }
}

/// 飞船节点：骨架为 typeID，携带该飞船全部装配
struct FittingShipNode: Hashable, Identifiable {
    let typeId: Int
    let shipInfo: FittingShipInfo
    let fittings: [FittingItemNode]

    var id: Int {
        typeId
    }

    static func == (lhs: FittingShipNode, rhs: FittingShipNode) -> Bool {
        lhs.typeId == rhs.typeId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(typeId)
    }
}

/// 组节点子项：多装配飞船进装配页；单装配飞船构建时拍平为装配行直达详情
enum FittingGroupChild: Hashable, Identifiable {
    case ship(FittingShipNode)
    case fitting(FittingItemNode)

    var id: String {
        switch self {
        case let .ship(node): return "ship-\(node.typeId)"
        case let .fitting(node): return "fitting-\(node.ref.debugDescription)"
        }
    }

    static func == (lhs: FittingGroupChild, rhs: FittingGroupChild) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// 组节点
struct FittingGroupNode: Hashable, Identifiable {
    let groupID: Int
    let groupName: String
    let firstIconFileName: String? // 组行图标：组内第一个装配的飞船图标
    let fittingCount: Int // 组内装配总数
    let children: [FittingGroupChild]

    var id: Int {
        groupID
    }

    static func == (lhs: FittingGroupNode, rhs: FittingGroupNode) -> Bool {
        lhs.groupID == rhs.groupID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(groupID)
    }
}

/// 装配目录条目：本地/在线统一的扁平输入（供 `FittingTreeBuilder.catalog` 构建目录与树）
typealias FittingCatalogEntry = (ref: FittingRef, name: String, shipTypeId: Int)

/// 装配列表用的飞船展示信息（全语种可搜）
struct FittingShipInfo {
    let names: LocalizedText
    let iconFileName: String

    var name: String {
        names.resolved()
    }

    func matches(_ query: String) -> Bool {
        names.matchesSearch(query)
    }
}

/// 导航树构建器：本地/在线 VM 共用
enum FittingTreeBuilder {
    /// 由扁平装配条目构建目录（SDE 查询舰船信息与所属组索引）；SDE 缺失的条目返回到 skipped
    static func catalog(from entries: [FittingCatalogEntry]) -> (
        shipInfo: [Int: FittingShipInfo],
        groupByType: [Int: (groupID: Int, groupName: String)],
        items: [FittingItemNode],
        skipped: [FittingCatalogEntry]
    ) {
        var shipInfo: [Int: FittingShipInfo] = [:]
        var groupByType: [Int: (groupID: Int, groupName: String)] = [:]
        var items: [FittingItemNode] = []
        var skipped: [FittingCatalogEntry] = []

        for entry in entries {
            guard let type = SDEMemoryStore.type(for: entry.shipTypeId),
                  let groupID = type.groupID,
                  let group = SDEMemoryStore.group(for: groupID)
            else {
                skipped.append(entry)
                continue
            }

            if shipInfo[entry.shipTypeId] == nil {
                shipInfo[entry.shipTypeId] = FittingShipInfo(
                    names: type.names,
                    iconFileName: type.iconFilename
                )
                groupByType[entry.shipTypeId] = (groupID, group.name)
            }

            items.append(
                FittingItemNode(ref: entry.ref, name: entry.name, shipTypeId: entry.shipTypeId)
            )
        }

        return (shipInfo, groupByType, items, skipped)
    }

    /// 搜索：匹配飞船本地化名称 / 装配名称 / 飞船 typeID，按飞船名、装配名排序
    static func searchMatches(
        tree: [FittingGroupNode], shipInfo: [Int: FittingShipInfo], query: String
    ) -> [FittingItemNode] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }

        let all: [FittingItemNode] = tree.flatMap { node in
            node.children.flatMap { child in
                switch child {
                case let .ship(ship): return ship.fittings
                case let .fitting(fitting): return [fitting]
                }
            }
        }

        return all.filter { fitting in
            guard let info = shipInfo[fitting.shipTypeId] else { return false }
            return info.matches(query)
                || fitting.name.localizedCaseInsensitiveContains(query)
                || String(fitting.shipTypeId).contains(query)
        }
        .sorted { a, b in
            let nameA = shipInfo[a.shipTypeId]?.name ?? ""
            let nameB = shipInfo[b.shipTypeId]?.name ?? ""
            if nameA != nameB {
                return nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// 由扁平装配行构建三级树：装配按名排序、单装配飞船拍平、子项按飞船名排序、组按组名排序
    static func build(
        items: [FittingItemNode],
        shipInfo: [Int: FittingShipInfo],
        groupByType: [Int: (groupID: Int, groupName: String)]
    ) -> [FittingGroupNode] {
        // 按飞船归类并生成子节点
        var groups: [Int: (name: String, children: [FittingGroupChild], count: Int)] = [:]

        for (typeId, fittings) in Dictionary(grouping: items, by: \.shipTypeId) {
            guard let info = shipInfo[typeId],
                  let group = groupByType[typeId]
            else { continue }

            let sorted = fittings.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            let child: FittingGroupChild =
                sorted.count == 1
                    ? .fitting(sorted[0])
                    : .ship(FittingShipNode(typeId: typeId, shipInfo: info, fittings: sorted))

            groups[group.groupID, default: (group.groupName, [], 0)].children.append(child)
            groups[group.groupID]!.count += sorted.count
        }

        // 组装组节点：子项按显示的飞船名排序
        return groups.map { groupID, value in
            let children = value.children.sorted { a, b in
                displayShipName(a, shipInfo: shipInfo)
                    .localizedCaseInsensitiveCompare(displayShipName(b, shipInfo: shipInfo))
                    == .orderedAscending
            }
            let firstIcon = children.first.flatMap { iconName($0, shipInfo: shipInfo) }

            return FittingGroupNode(
                groupID: groupID,
                groupName: value.name,
                firstIconFileName: firstIcon,
                fittingCount: value.count,
                children: children
            )
        }
        .sorted {
            $0.groupName.localizedCaseInsensitiveCompare($1.groupName) == .orderedAscending
        }
    }

    /// 子项用于排序/图标的飞船名
    private static func displayShipName(
        _ child: FittingGroupChild, shipInfo: [Int: FittingShipInfo]
    ) -> String {
        switch child {
        case let .ship(node): return node.shipInfo.name
        case let .fitting(node): return shipInfo[node.shipTypeId]?.name ?? ""
        }
    }

    /// 子项图标
    private static func iconName(
        _ child: FittingGroupChild, shipInfo: [Int: FittingShipInfo]
    ) -> String? {
        switch child {
        case let .ship(node): return node.shipInfo.iconFileName
        case let .fitting(node): return shipInfo[node.shipTypeId]?.iconFileName
        }
    }
}
