import Foundation

class CharacterContractsAPI {
    static let shared = CharacterContractsAPI()

    // 通知名称常量
    static let contractsUpdatedNotification = "ContractsUpdatedNotification"
    static let contractsUpdatedCharacterIdKey = "CharacterId"

    private let cacheTimeout: TimeInterval = 1 * 3600 // 1小时缓存有效期

    private init() {
        // 创建缓存目录
        let cacheDirectory = getContractCacheDirectory()
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            Logger.info("创建合同缓存目录: \(cacheDirectory.path)")
            try? FileManager.default.createDirectory(
                at: cacheDirectory, withIntermediateDirectories: true
            )
        }
    }

    // 获取合同缓存目录
    private func getContractCacheDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("CharContractCache")
    }

    // 获取合同缓存文件路径
    private func getContractCacheFilePath(characterId: Int) -> URL {
        let cacheDirectory = getContractCacheDirectory()
        return cacheDirectory.appendingPathComponent("CharContract_\(characterId).json")
    }

    // 获取合同物品缓存文件路径
    private func getContractItemsCacheFilePath(contractId: Int) -> URL {
        let cacheDirectory = getContractCacheDirectory()
        return cacheDirectory.appendingPathComponent("ContractItems_\(contractId).json")
    }

    // 检查合同缓存是否过期
    private func isContractCacheExpired(characterId: Int) -> Bool {
        let filePath = getContractCacheFilePath(characterId: characterId)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info("合同缓存文件不存在，需要刷新 - 文件路径: \(filePath.path)")
            return true
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: filePath.path)
            if let modificationDate = attributes[.modificationDate] as? Date {
                let timeInterval = Date().timeIntervalSince(modificationDate)
                let remainingTime = cacheTimeout - timeInterval
                let remainingHours = Int(remainingTime / 3600)
                let remainingMinutes = Int((remainingTime.truncatingRemainder(dividingBy: 3600)) / 60)
                let isExpired = timeInterval > cacheTimeout

                Logger.info(
                    "合同缓存状态检查 - 角色ID: \(characterId), 文件修改时间: \(modificationDate), 当前时间: \(Date()), 时间间隔: \(timeInterval)秒, 剩余时间: \(remainingHours)小时\(remainingMinutes)分钟, 是否过期: \(isExpired)"
                )
                return isExpired
            }
        } catch {
            Logger.error("获取合同缓存文件属性失败: \(error) - 文件路径: \(filePath.path)")
        }

        return true
    }

    // 使指定角色的合同相关缓存失效
    private func invalidateCharacterContractCache(characterId: Int) {
        let contractFilePath = getContractCacheFilePath(characterId: characterId)

        // 删除合同缓存文件
        if FileManager.default.fileExists(atPath: contractFilePath.path) {
            do {
                try FileManager.default.removeItem(at: contractFilePath)
                Logger.info("已删除角色合同缓存文件 - 角色ID: \(characterId), 文件路径: \(contractFilePath.path)")
            } catch {
                Logger.error("删除角色合同缓存文件失败 - 角色ID: \(characterId), 错误: \(error)")
            }
        }
    }

    // 从缓存文件获取合同列表
    private func getContractsFromCache(characterId: Int) -> [ContractInfo]? {
        let filePath = getContractCacheFilePath(characterId: characterId)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info("合同缓存文件不存在 - 角色ID: \(characterId), 文件路径: \(filePath.path)")
            return nil
        }

        Logger.info("开始读取合同缓存文件 - 角色ID: \(characterId), 文件路径: \(filePath.path)")

        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let contracts = try decoder.decode([ContractInfo].self, from: data)
            Logger.info(
                "成功从缓存文件读取合同 - 角色ID: \(characterId), 合同数量: \(contracts.count), 文件大小: \(data.count) bytes"
            )
            return contracts
        } catch {
            Logger.error(
                "读取合同缓存文件失败 - 角色ID: \(characterId), 错误: \(error), 文件路径: \(filePath.path)")
            return nil
        }
    }

    // 保存合同列表到缓存文件
    private func saveContractsToCache(characterId: Int, contracts: [ContractInfo]) -> Bool {
        let filePath = getContractCacheFilePath(characterId: characterId)

        Logger.info(
            "开始保存合同到缓存文件 - 角色ID: \(characterId), 合同数量: \(contracts.count), 文件路径: \(filePath.path)")

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(contracts)
            try jsonData.write(to: filePath)
            Logger.info(
                "成功保存合同到缓存文件 - 角色ID: \(characterId), 合同数量: \(contracts.count), 文件大小: \(jsonData.count) bytes, 文件路径: \(filePath.path)"
            )
            return true
        } catch {
            Logger.error(
                "保存合同到缓存文件失败 - 角色ID: \(characterId), 错误: \(error), 文件路径: \(filePath.path)")
            return false
        }
    }

    // 从缓存文件获取合同列表，如果数据过期则在后台刷新
    private func getContractsFromCacheOrRefresh(characterId: Int) async -> [ContractInfo]? {
        let contracts = getContractsFromCache(characterId: characterId)

        // 只有在有数据且数据过期的情况下才在后台刷新
        if let contracts = contracts, !contracts.isEmpty,
           isContractCacheExpired(characterId: characterId)
        {
            Logger.info("合同数据已过期，在后台刷新 - 角色ID: \(characterId)")

            // 在后台刷新数据
            Task {
                do {
                    let _ = try await fetchContractsFromServer(characterId: characterId)
                    Logger.info("后台刷新合同数据完成 - 角色ID: \(characterId)")
                } catch {
                    Logger.error("后台刷新合同数据失败 - 角色ID: \(characterId), 错误: \(error)")
                }
            }
        } else if !isContractCacheExpired(characterId: characterId) {
            Logger.info("使用有效的合同缓存数据 - 角色ID: \(characterId)")
        }

        return contracts
    }

    // 从缓存文件获取合同物品
    private func getContractItemsFromCache(contractId: Int) -> [ContractItemInfo]? {
        let filePath = getContractItemsCacheFilePath(contractId: contractId)

        guard FileManager.default.fileExists(atPath: filePath.path) else {
            Logger.info("合同物品缓存文件不存在 - 合同ID: \(contractId), 文件路径: \(filePath.path)")
            return nil
        }

        Logger.info("开始读取合同物品缓存文件 - 合同ID: \(contractId), 文件路径: \(filePath.path)")

        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            let items = try decoder.decode([ContractItemInfo].self, from: data)
            Logger.info(
                "成功从缓存文件读取合同物品 - 合同ID: \(contractId), 物品数量: \(items.count), 文件大小: \(data.count) bytes"
            )
            return items
        } catch {
            Logger.error(
                "读取合同物品缓存文件失败 - 合同ID: \(contractId), 错误: \(error), 文件路径: \(filePath.path)")
            return nil
        }
    }

    // 保存合同物品到缓存文件
    private func saveContractItemsToCache(contractId: Int, items: [ContractItemInfo]) -> Bool {
        let filePath = getContractItemsCacheFilePath(contractId: contractId)

        Logger.info(
            "开始保存合同物品到缓存文件 - 合同ID: \(contractId), 物品数量: \(items.count), 文件路径: \(filePath.path)")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(items)
            try jsonData.write(to: filePath)
            Logger.info(
                "成功保存合同物品到缓存文件 - 合同ID: \(contractId), 物品数量: \(items.count), 文件大小: \(jsonData.count) bytes, 文件路径: \(filePath.path)"
            )
            return true
        } catch {
            Logger.error(
                "保存合同物品到缓存文件失败 - 合同ID: \(contractId), 错误: \(error), 文件路径: \(filePath.path)")
            return false
        }
    }

    // 获取合同列表（公开方法）
    func fetchContracts(
        characterId: Int, forceRefresh: Bool = false, progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [ContractInfo] {
        // 如果是强制刷新，先使缓存失效
        if forceRefresh {
            Logger.info("强制刷新角色合同，使缓存失效 - 角色ID: \(characterId)")
            invalidateCharacterContractCache(characterId: characterId)
        }

        // 检查缓存中是否有数据
        let cacheExists = getContractsFromCache(characterId: characterId) != nil

        // 如果数据为空、强制刷新或缓存过期，则从网络获取
        if !cacheExists || forceRefresh || isContractCacheExpired(characterId: characterId) {
            Logger.debug("合同数据为空、强制刷新或缓存过期，从网络获取数据")
            let contracts = try await fetchContractsFromServer(
                characterId: characterId, progressCallback: progressCallback
            )
            return contracts
        }

        // 从缓存获取数据并返回
        if let contracts = await getContractsFromCacheOrRefresh(characterId: characterId) {
            return contracts
        }
        return []
    }

    // 获取合同物品（公开方法）
    func fetchContractItems(characterId: Int, contractId: Int, forceRefresh: Bool = false)
        async throws -> [ContractItemInfo]
    {
        Logger.debug("开始获取合同物品 - 角色ID: \(characterId), 合同ID: \(contractId)")

        // 如果不是强制刷新，先检查缓存
        if !forceRefresh {
            if let items = getContractItemsFromCache(contractId: contractId) {
                if !items.isEmpty {
                    Logger.debug("从缓存成功获取到\(items.count)个合同物品")
                    return items
                }
                Logger.debug("该合同没有物品内容")
                return []
            }
        }

        // 从服务器获取数据
        Logger.debug("从服务器获取合同物品")
        let items = try await fetchContractItemsFromServer(
            characterId: characterId, contractId: contractId
        )
        Logger.debug("从服务器获取到\(items.count)个合同物品")

        // 保存到缓存文件
        if !saveContractItemsToCache(contractId: contractId, items: items) {
            Logger.error("保存合同物品到缓存文件失败")
        } else {
            Logger.success("成功保存合同物品到缓存文件")
        }

        return items
    }

    // 从服务器获取合同列表
    private func fetchContractsFromServer(
        characterId: Int, progressCallback: ((Int) -> Void)? = nil
    ) async throws -> [ContractInfo] {
        let baseUrlString =
            "https://esi.evetech.net/characters/\(characterId)/contracts/?datasource=tranquility"
        guard let baseUrl = URL(string: baseUrlString) else {
            throw NetworkError.invalidURL
        }

        let contracts = try await NetworkManager.shared.fetchPaginatedData(
            from: baseUrl,
            characterId: characterId,
            maxConcurrentPages: 5, // 保持原有的最大并发数
            decoder: { data in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode([ContractInfo].self, from: data)
            },
            progressCallback: { currentPage, _ in
                progressCallback?(currentPage)
            }
        )

        // 保存到缓存文件
        if !saveContractsToCache(characterId: characterId, contracts: contracts) {
            Logger.error("保存合同到缓存文件失败")
        } else {
            // 发送数据更新通知
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name(CharacterContractsAPI.contractsUpdatedNotification),
                    object: nil,
                    userInfo: [CharacterContractsAPI.contractsUpdatedCharacterIdKey: characterId]
                )
            }
        }

        Logger.success("成功从服务器获取合同数据 - 角色ID: \(characterId), 合同数量: \(contracts.count)")

        return contracts
    }

    // 合同物品信息模型
    struct ContractItemInfo: Codable, Identifiable {
        let is_included: Bool
        let is_singleton: Bool
        let quantity: Int
        let record_id: Int64
        let type_id: Int
        let raw_quantity: Int?

        var id: Int64 { record_id }
    }

    // 从服务器获取合同物品
    private func fetchContractItemsFromServer(characterId: Int, contractId: Int) async throws
        -> [ContractItemInfo]
    {
        Logger.debug("开始从服务器获取合同物品 - 角色ID: \(characterId), 合同ID: \(contractId)")
        let url = URL(
            string:
            "https://esi.evetech.net/characters/\(characterId)/contracts/\(contractId)/items/?datasource=tranquility"
        )!
        Logger.debug("请求URL: \(url.absoluteString)")

        do {
            let data = try await NetworkManager.shared.fetchDataWithToken(
                from: url,
                characterId: characterId
            )

            let decoder = JSONDecoder()
            let items = try decoder.decode([ContractItemInfo].self, from: data)
            Logger.success("成功从服务器获取合同物品 - 合同ID: \(contractId), 物品数量: \(items.count)")

            // 打印每个物品的详细信息
            //            for item in items {
            //                Logger.debug("""
            //                    物品详情:
            //                    - 记录ID: \(item.record_id)
            //                    - 类型ID: \(item.type_id)
            //                    - 数量: \(item.quantity)
            //                    - 是否包含: \(item.is_included)
            //                    - 是否单例: \(item.is_singleton)
            //                    - 原始数量: \(item.raw_quantity ?? 0)
            //                    """)
            //            }

            return items
        } catch {
            Logger.error("从服务器获取合同物品失败 - 合同ID: \(contractId), 错误: \(error.localizedDescription)")
            throw error
        }
    }
}

// 合同信息模型
struct ContractInfo: Codable, Identifiable, Hashable {
    let acceptor_id: Int?
    let assignee_id: Int?
    let availability: String
    let buyout: Double?
    let collateral: Double?
    let contract_id: Int
    let date_accepted: Date?
    let date_completed: Date?
    let date_expired: Date
    let date_issued: Date
    let days_to_complete: Int
    let end_location_id: Int64
    let for_corporation: Bool
    let issuer_corporation_id: Int
    let issuer_id: Int
    let price: Double
    let reward: Double
    let start_location_id: Int64
    let status: String
    let title: String
    let type: String
    let volume: Double

    var id: Int { contract_id }

    // 实现 Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(contract_id)
    }

    static func == (lhs: ContractInfo, rhs: ContractInfo) -> Bool {
        return lhs.contract_id == rhs.contract_id
    }
}
