import Foundation

// 市场组节点
struct MarketGroupNode: Identifiable {
    let id: Int
    let name: String
    let description: String
    let iconName: String
    let parentGroupId: Int?
    var children: [MarketGroupNode]

    init(id: Int, name: String, description: String, iconName: String, parentGroupId: Int?) {
        self.id = id
        self.name = name
        self.description = description
        self.iconName = iconName
        self.parentGroupId = parentGroupId
        self.children = []
    }
}

// 市场组树构建器
class MarketItemGroupTreeBuilder {
    private let databaseManager: DatabaseManager
    private let allowedTypeIDs: Set<Int>
    private let parentGroupId: Int?

    init(databaseManager: DatabaseManager, allowedTypeIDs: Set<Int>, parentGroupId: Int? = nil) {
        self.databaseManager = databaseManager
        self.allowedTypeIDs = allowedTypeIDs
        self.parentGroupId = parentGroupId
    }

    // 构建目录树
    func buildGroupTree() -> [MarketGroupNode] {
        Logger.info("开始构建市场组目录树")

        // 步骤1: 构造完整的市场树
        let allGroups = fetchMarketGroups()
        Logger.info("获取到的市场组总数：\(allGroups.count)")

        let fullTree = buildFullTree(from: allGroups)
        Logger.info("构造完整市场树，根节点数：\(fullTree.count)")

        // 步骤2: 根据type_id裁剪不相关的分支
        let validGroupIDs = fetchValidMarketGroupIDs()
        Logger.info("包含有效类型的市场组ID数量：\(validGroupIDs.count)")

        let prunedByTypeID = pruneInvalidBranches(fullTree, validGroupIDs: validGroupIDs)
        Logger.info("根据type_id裁剪后的根节点数：\(prunedByTypeID.count)")

        // 步骤3: 根据parentGroupId提取子树
        let finalTree: [MarketGroupNode]
        if let parentId = parentGroupId {
            Logger.info("根据parentGroupId=\(parentId)提取子树")
            // 查找指定ID的节点
            if let parentNode = findNodeById(prunedByTypeID, id: parentId) {
                // 检查是否有子节点
                if parentNode.children.isEmpty {
                    // 如果没有子节点，返回该节点本身，而不是空数组
                    Logger.info("节点 \(parentId) 没有子节点，返回该节点本身: \(parentNode.name)")
                    finalTree = [parentNode]
                } else {
                    // 有子节点，返回其子节点
                    finalTree = parentNode.children
                    Logger.info("找到父节点：\(parentNode.name)，子节点数量：\(finalTree.count)")
                }
            } else {
                Logger.warning("未找到指定ID的父节点：\(parentId)，将保持原树结构")
                finalTree = prunedByTypeID
            }
            
            // 只有在指定了parentGroupId时才进行顶层压缩
            let compressedTree = compressTopLevelOnly(finalTree)
            Logger.info("顶层压缩后的根节点数量：\(compressedTree.count)")
            Logger.info("构建市场组目录树完成，根节点数量：\(compressedTree.count)")
            return compressedTree
        } else {
            // 当parentGroupId为nil时，直接返回完整的裁剪树，不进行顶层压缩
            Logger.info("未指定parentGroupId，展示完整树结构")
            Logger.info("构建市场组目录树完成，根节点数量：\(prunedByTypeID.count)")
            return prunedByTypeID
        }
    }

    // 从数据库获取所有市场组信息
    private func fetchMarketGroups() -> [MarketGroupNode] {
        let query = """
                SELECT group_id, name, description, icon_name, parentgroup_id
                FROM marketGroups
                WHERE show = 1
            """

        var groups: [MarketGroupNode] = []

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                if let groupId = row["group_id"] as? Int,
                    let name = row["name"] as? String
                {
                    let description = (row["description"] as? String) ?? ""
                    let iconName = (row["icon_name"] as? String) ?? ""
                    let parentId = row["parentgroup_id"] as? Int

                    // Logger.debug("市场组: ID=\(groupId), 名称=\(name), 图标=\(iconName)")

                    let node = MarketGroupNode(
                        id: groupId,
                        name: name,
                        description: description,
                        iconName: iconName,
                        parentGroupId: parentId
                    )
                    groups.append(node)
                }
            }
        }

        return groups
    }

    // 构建完整的树结构
    private func buildFullTree(from groups: [MarketGroupNode]) -> [MarketGroupNode] {
        // 1. 创建ID到节点的映射
        var nodeMap: [Int: MarketGroupNode] = [:]
        for group in groups {
            nodeMap[group.id] = group
        }

        // 2. 构建父子关系
        for group in groups {
            if let parentId = group.parentGroupId {
                if var parent = nodeMap[parentId] {
                    // 将当前节点添加为父节点的子节点
                    parent.children.append(group)
                    nodeMap[parentId] = parent
                }
            }
        }

        // 3. 确保映射中的每个节点都包含其所有子节点的最新版本
        var rootNodes: [MarketGroupNode] = []

        // 找出所有根节点
        for group in groups {
            if group.parentGroupId == nil {
                if let updatedNode = nodeMap[group.id] {
                    rootNodes.append(updatedNode)
                }
            }
        }

        // 4. 递归更新所有节点的子节点
        func updateChildrenRecursively(_ node: MarketGroupNode) -> MarketGroupNode {
            var updatedNode = node
            updatedNode.children = node.children.map { child -> MarketGroupNode in
                if let updatedChild = nodeMap[child.id] {
                    return updateChildrenRecursively(updatedChild)
                } else {
                    return updateChildrenRecursively(child)
                }
            }
            return updatedNode
        }

        // 5. 更新所有根节点
        rootNodes = rootNodes.map { updateChildrenRecursively($0) }

        return rootNodes
    }

    // 获取包含有效类型的市场组ID及其所有父节点ID
    private func fetchValidMarketGroupIDs() -> Set<Int> {
        // 1. 获取直接包含有效类型的市场组ID
        var directQuery = ""
        if !allowedTypeIDs.isEmpty {
            directQuery = """
                SELECT DISTINCT marketGroupID
                FROM types
                WHERE type_id IN (\(allowedTypeIDs.map { String($0) }.joined(separator: ",")))
                  AND marketGroupID IS NOT NULL
            """
        } else {
            directQuery = """
                SELECT DISTINCT marketGroupID
                FROM types
                WHERE marketGroupID IS NOT NULL
            """
        }
        var validGroupIDs = Set<Int>()

        if case let .success(rows) = databaseManager.executeQuery(directQuery) {
            for row in rows {
                if let groupId = row["marketGroupID"] as? Int {
                    validGroupIDs.insert(groupId)
                    // Logger.debug("有效的市场组ID: \(groupId)")
                }
            }
        }

        Logger.info("直接包含有效类型的市场组ID数量：\(validGroupIDs.count)")

        // 如果没有找到有效的市场组ID，则返回所有市场组ID
        if validGroupIDs.isEmpty {
            Logger.info("没有找到有效的市场组ID，将返回所有市场组ID")
            let allGroupsQuery = """
                SELECT group_id
                FROM marketGroups
                WHERE show = 1
            """
            
            if case let .success(rows) = databaseManager.executeQuery(allGroupsQuery) {
                for row in rows {
                    if let groupId = row["group_id"] as? Int {
                        validGroupIDs.insert(groupId)
                    }
                }
            }
            
            Logger.info("获取到所有市场组ID数量：\(validGroupIDs.count)")
            return validGroupIDs
        }

        // 2. 获取所有市场组的父子关系
        let relationsQuery = """
                SELECT group_id, parentgroup_id
                FROM marketGroups
                WHERE show = 1
            """

        var parentChildMap = [Int: Int]()  // 子ID -> 父ID

        if case let .success(rows) = databaseManager.executeQuery(relationsQuery) {
            for row in rows {
                if let groupId = row["group_id"] as? Int,
                    let parentId = row["parentgroup_id"] as? Int
                {
                    parentChildMap[groupId] = parentId
                }
            }
        }

        // 3. 递归查找所有父节点
        var currentIds = validGroupIDs
        var addedParents = Set<Int>()

        while !currentIds.isEmpty {
            var nextIds = Set<Int>()

            for id in currentIds {
                if let parentId = parentChildMap[id], !validGroupIDs.contains(parentId) {
                    nextIds.insert(parentId)
                    validGroupIDs.insert(parentId)
                    addedParents.insert(parentId)
                }
            }

            currentIds = nextIds
        }

        Logger.info("添加了 \(addedParents.count) 个父节点")

        return validGroupIDs
    }

    // 裁剪不含有效类型的分支
    private func pruneInvalidBranches(_ nodes: [MarketGroupNode], validGroupIDs: Set<Int>)
        -> [MarketGroupNode]
    {
        var totalPruned = 0
        var keptNodes = 0

        func prune(_ nodes: [MarketGroupNode]) -> [MarketGroupNode] {
            return nodes.compactMap { node in
                // 如果当前节点ID在有效集合中
                if validGroupIDs.contains(node.id) {
                    keptNodes += 1
                    // 递归处理子节点
                    var prunedNode = node
                    let originalChildCount = prunedNode.children.count
                    prunedNode.children = prune(node.children)

                    if originalChildCount != prunedNode.children.count {
                        totalPruned += (originalChildCount - prunedNode.children.count)
                    }

                    return prunedNode
                }
                totalPruned += 1
                return nil
            }
        }

        let result = prune(nodes)
        Logger.info("裁剪过程：保留了 \(keptNodes) 个节点，移除了 \(totalPruned) 个节点")
        return result
    }

    // 根据ID查找节点
    private func findNodeById(_ nodes: [MarketGroupNode], id: Int) -> MarketGroupNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            // 递归查找子节点
            if let foundNode = findNodeById(node.children, id: id) {
                return foundNode
            }
        }
        return nil
    }

    // 仅压缩顶层的单路径分支
    private func compressTopLevelOnly(_ nodes: [MarketGroupNode]) -> [MarketGroupNode] {
        Logger.info("压缩顶层单路径: \(nodes.count)个节点 : \(nodes.map { $0.name }.joined(separator: ", "))")

        // 如果只有一个节点，考虑压缩
        if nodes.count == 1 {
            let node = nodes[0]
            Logger.info("检查节点: \(node.name), 子节点数: \(node.children.count)")

            // 如果没有子节点，直接返回
            if node.children.isEmpty {
                return [node]
            }

            // 如果只有一个子节点，递归压缩
            if node.children.count == 1 {
                Logger.debug("压缩单路径: \(node.name) -> \(node.children[0].name)")
                return compressTopLevelOnly(node.children)
            }

            // 如果有多个子节点，返回这些子节点
            Logger.info("遇到分支节点: \(node.name)，返回其 \(node.children.count) 个子节点")
            return node.children
        }

        // 如果有多个节点，不压缩
        Logger.info("不压缩多节点: \(nodes.count)个节点")
        return nodes
    }
}
