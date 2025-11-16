import SwiftUI

// 行星信息模型
struct PlanetTypeInfo {
    let name: String
    let icon: String
}

// 最终产品模型
struct FinalProduct: Identifiable {
    let id: Int // typeId
    let typeId: Int
    let icon: String
}

// 采集器状态模型
struct ExtractorStatus {
    let totalCount: Int // 总采集器数量
    let expiredCount: Int // 已停工的采集器数量
    let expiringSoonCount: Int // 即将在1小时内停工的采集器数量
}

// 扩展CharacterPlanetaryInfo来包含角色归属信息
struct PlanetWithOwner {
    let planet: CharacterPlanetaryInfo
    let ownerId: Int // 该行星归属的角色ID
}

@MainActor
final class CharacterPlanetaryViewModel: ObservableObject {
    @Published private(set) var planets: [CharacterPlanetaryInfo] = []
    @Published private(set) var planetNames: [Int: String] = [:]
    @Published private(set) var planetTypeInfo: [Int: PlanetTypeInfo] = [:]
    @Published private(set) var systemSecurities: [Int: Double] = [:] // 星系安等信息 [systemId: security]
    @Published private(set) var earliestExtractorExpiry: [String: Date] = [:] // 每个行星的最早采集器过期时间 [key: Date]，key格式为 "characterId_planetId"
    @Published private(set) var finalProducts: [String: [FinalProduct]] = [:] // 每个行星的最终产品 [key: [FinalProduct]]，key格式为 "characterId_planetId"
    @Published private(set) var loadingPlanets: Set<String> = [] // 正在加载的行星ID集合，key格式为 "characterId_planetId"
    @Published private(set) var extractorStatus: [String: ExtractorStatus] = [:] // 每个行星的采集器状态 [key: ExtractorStatus]，key格式为 "characterId_planetId"
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var loadingProgress: (current: Int, total: Int)? = nil // 加载进度 (已加载/总数)

    // 多人物聚合相关
    @Published var multiCharacterMode = false {
        didSet {
            UserDefaults.standard.set(multiCharacterMode, forKey: "multiCharacterMode_planetary")
            if initialLoadDone {
                Task {
                    await loadPlanets(forceRefresh: true)
                }
            }
        }
    }

    @Published var selectedCharacterIds: Set<Int> = [] {
        didSet {
            UserDefaults.standard.set(
                Array(selectedCharacterIds), forKey: "selectedCharacterIds_planetary"
            )
            if initialLoadDone, multiCharacterMode {
                Task {
                    await loadPlanets(forceRefresh: true)
                }
            }
        }
    }

    @Published var availableCharacters: [(id: Int, name: String)] = []

    var planetsWithOwner: [PlanetWithOwner] = [] // 包含所有者信息的行星列表
    @Published var planetOwners: [Int: Int] = [:] // 每个行星对应的角色ID [planetId: characterId]
    @Published var maxPlanetsByCharacter: [Int: Int] = [:] // 每个角色的可支配星球数 [characterId: maxPlanets]

    private var loadingTask: Task<Void, Never>?
    private var expiryLoadingTask: Task<Void, Never>?
    private let characterId: Int?
    private var initialLoadDone = false

    init(characterId: Int?) {
        self.characterId = characterId

        // 从 UserDefaults 读取多人物聚合设置
        multiCharacterMode = UserDefaults.standard.bool(forKey: "multiCharacterMode_planetary")
        let savedCharacterIds =
            UserDefaults.standard.array(forKey: "selectedCharacterIds_planetary") as? [Int] ?? []
        selectedCharacterIds = Set(savedCharacterIds)

        // 加载可用角色列表
        availableCharacters = CharacterSkillsUtils.getAllCharacters()

        // 如果没有选中的角色，默认选择当前角色
        if selectedCharacterIds.isEmpty, let characterId = characterId {
            selectedCharacterIds.insert(characterId)
        }

        // 在初始化时立即开始加载数据
        loadingTask = Task {
            await loadPlanets()
        }
    }

    deinit {
        loadingTask?.cancel()
        expiryLoadingTask?.cancel()
    }

    private func loadPlanetTypeInfo() async throws -> [Int: PlanetTypeInfo] {
        let typeIds = Array(PlanetaryUtils.planetTypeToColumn.keys).sorted()
        let typeIdsString = typeIds.map { String($0) }.joined(separator: ",")

        var tempPlanetTypeInfo: [Int: PlanetTypeInfo] = [:]

        // 从数据库获取行星类型信息
        let typeQuery =
            "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(typeIdsString))"
        if case let .success(rows) = DatabaseManager.shared.executeQuery(typeQuery) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFilename = row["icon_filename"] as? String
                {
                    tempPlanetTypeInfo[typeId] = PlanetTypeInfo(
                        name: name, icon: iconFilename
                    )
                }
            }
        }

        return tempPlanetTypeInfo
    }

    func loadPlanets(forceRefresh: Bool = false) async {
        // 如果已经加载过且不是强制刷新，则跳过
        if initialLoadDone, !forceRefresh {
            return
        }

        // 取消之前的加载任务
        loadingTask?.cancel()

        // 创建新的加载任务
        loadingTask = Task {
            isLoading = true
            errorMessage = nil

            do {
                // 首先加载行星类型信息（静态数据）
                let planetTypeInfo = try await loadPlanetTypeInfo()

                // 确定要加载的角色ID列表
                let characterIdsToLoad: [Int]
                if multiCharacterMode, selectedCharacterIds.count > 1 {
                    characterIdsToLoad = Array(selectedCharacterIds)
                } else if multiCharacterMode, !selectedCharacterIds.isEmpty {
                    characterIdsToLoad = [selectedCharacterIds.first!]
                } else if let characterId = characterId {
                    characterIdsToLoad = [characterId]
                } else {
                    characterIdsToLoad = []
                }

                if !characterIdsToLoad.isEmpty {
                    var allPlanets: [CharacterPlanetaryInfo] = []
                    var allPlanetsWithOwner: [PlanetWithOwner] = []
                    var tempPlanetOwners: [Int: Int] = [:]
                    let totalCharacters = characterIdsToLoad.count

                    // 初始化加载进度
                    await MainActor.run {
                        self.loadingProgress = (current: 0, total: totalCharacters)
                    }

                    // 并发获取所有角色的行星信息
                    await withTaskGroup(of: (Int, Result<[CharacterPlanetaryInfo], Error>).self) { group in
                        for charId in characterIdsToLoad {
                            group.addTask {
                                do {
                                    let planetsList = try await CharacterPlanetaryAPI.fetchCharacterPlanetary(
                                        characterId: charId, forceRefresh: forceRefresh
                                    )
                                    return (charId, .success(planetsList))
                                } catch {
                                    Logger.error("获取角色\(charId)行星数据失败: \(error)")
                                    return (charId, .failure(error))
                                }
                            }
                        }

                        // 使用 Actor 来线程安全地更新进度
                        let progressActor = ProgressActor(total: totalCharacters) { current, total in
                            Task { @MainActor in
                                self.loadingProgress = (current: current, total: total)
                            }
                        }

                        // 收集结果
                        for await (charId, result) in group {
                            switch result {
                            case let .success(planetsList):
                                allPlanets.append(contentsOf: planetsList)
                                // 为每个行星添加所有者信息
                                for planet in planetsList {
                                    allPlanetsWithOwner.append(PlanetWithOwner(planet: planet, ownerId: charId))
                                    tempPlanetOwners[planet.planetId] = charId
                                }
                            case .failure:
                                // 失败时继续处理，不中断
                                break
                            }

                            // 更新进度
                            await progressActor.increment()
                        }
                    }

                    if Task.isCancelled { return }

                    // 获取所有行星ID
                    let planetIds = allPlanets.map { $0.planetId }
                    let planetIdsString = planetIds.sorted().map { String($0) }.joined(
                        separator: ",")

                    if Task.isCancelled { return }

                    var tempPlanetNames: [Int: String] = [:]
                    var tempSystemSecurities: [Int: Double] = [:]

                    // 获取所有唯一的星系ID
                    let uniqueSystemIds = Array(Set(allPlanets.map { $0.solarSystemId }))
                    if !uniqueSystemIds.isEmpty {
                        let systemIdsString = uniqueSystemIds.sorted().map { String($0) }.joined(separator: ",")

                        // 批量获取星系安等信息
                        let securityQuery = """
                            SELECT u.solarsystem_id, u.system_security
                            FROM universe u
                            WHERE u.solarsystem_id IN (\(systemIdsString))
                        """
                        if case let .success(rows) = DatabaseManager.shared.executeQuery(securityQuery) {
                            for row in rows {
                                if let systemId = row["solarsystem_id"] as? Int,
                                   let security = row["system_security"] as? Double
                                {
                                    tempSystemSecurities[systemId] = security
                                }
                            }
                        }
                    }

                    // 获取行星名称
                    if !planetIdsString.isEmpty {
                        let nameQuery =
                            "SELECT itemID, itemName FROM celestialNames WHERE itemID IN (\(planetIdsString))"
                        if case let .success(rows) = DatabaseManager.shared.executeQuery(nameQuery) {
                            for row in rows {
                                if let itemId = row["itemID"] as? Int,
                                   let itemName = row["itemName"] as? String
                                {
                                    tempPlanetNames[itemId] = itemName
                                }
                            }
                        }
                    }

                    if Task.isCancelled { return }

                    await MainActor.run {
                        self.planets = allPlanets
                        self.planetsWithOwner = allPlanetsWithOwner
                        self.planetOwners = tempPlanetOwners
                        self.planetNames = tempPlanetNames
                        self.planetTypeInfo = planetTypeInfo
                        self.systemSecurities = tempSystemSecurities
                        self.isLoading = false
                        self.initialLoadDone = true
                        // 清除加载进度
                        self.loadingProgress = nil
                    }

                    // 加载技能数据计算可支配星球数
                    await loadMaxPlanets(characterIds: characterIdsToLoad, forceRefresh: forceRefresh)

                    // 异步加载所有行星的采集器过期时间（最多6线程）
                    // 需要为每个行星传递对应的角色ID
                    await loadExtractorExpiryTimes(planetsWithOwner: allPlanetsWithOwner)
                } else {
                    // 如果没有选择角色，只加载静态数据
                    await MainActor.run {
                        self.planets = []
                        self.planetsWithOwner = []
                        self.planetOwners = [:]
                        self.planetNames = [:]
                        self.planetTypeInfo = planetTypeInfo
                        self.systemSecurities = [:]
                        self.isLoading = false
                        self.initialLoadDone = true
                    }
                }
            } catch {
                Logger.error("加载行星数据失败: \(error.localizedDescription)")
                if !Task.isCancelled {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.isLoading = false
                    }
                }
            }
        }

        // 等待任务完成
        await loadingTask?.value
    }

    func getPlanetTypeInfo(for planetType: String) -> PlanetTypeInfo? {
        // 通过columnToPlanetType找到对应的行星类型ID
        if let typeId = PlanetaryUtils.columnToPlanetType[planetType],
           let info = planetTypeInfo[typeId]
        {
            return info
        }
        return nil
    }

    func getPlanetName(for planetId: Int) -> String {
        return planetNames[planetId]
            ?? NSLocalizedString("Main_Planetary_Unknown_Planet", comment: "")
    }

    func getSystemSecurity(for systemId: Int) -> Double? {
        return systemSecurities[systemId]
    }

    /// 生成行星数据的唯一键
    private func makePlanetKey(characterId: Int, planetId: Int) -> String {
        return "\(characterId)_\(planetId)"
    }

    func getEarliestExtractorExpiry(for planetId: Int, characterId: Int? = nil) -> Date? {
        if let characterId = characterId {
            return earliestExtractorExpiry[makePlanetKey(characterId: characterId, planetId: planetId)]
        }
        // 兼容旧代码：如果没有提供characterId，尝试从planetOwners查找
        if let ownerId = planetOwners[planetId] {
            return earliestExtractorExpiry[makePlanetKey(characterId: ownerId, planetId: planetId)]
        }
        return nil
    }

    func getFinalProducts(for planetId: Int, characterId: Int? = nil) -> [FinalProduct] {
        if let characterId = characterId {
            return finalProducts[makePlanetKey(characterId: characterId, planetId: planetId)] ?? []
        }
        // 兼容旧代码：如果没有提供characterId，尝试从planetOwners查找
        if let ownerId = planetOwners[planetId] {
            return finalProducts[makePlanetKey(characterId: ownerId, planetId: planetId)] ?? []
        }
        return []
    }

    func getExtractorStatus(for planetId: Int, characterId: Int? = nil) -> ExtractorStatus? {
        if let characterId = characterId {
            return extractorStatus[makePlanetKey(characterId: characterId, planetId: planetId)]
        }
        // 兼容旧代码：如果没有提供characterId，尝试从planetOwners查找
        if let ownerId = planetOwners[planetId] {
            return extractorStatus[makePlanetKey(characterId: ownerId, planetId: planetId)]
        }
        return nil
    }

    func isLoadingPlanetDetail(for planetId: Int, characterId: Int? = nil) -> Bool {
        if let characterId = characterId {
            return loadingPlanets.contains(makePlanetKey(characterId: characterId, planetId: planetId))
        }
        // 兼容旧代码：如果没有提供characterId，尝试从planetOwners查找
        if let ownerId = planetOwners[planetId] {
            return loadingPlanets.contains(makePlanetKey(characterId: ownerId, planetId: planetId))
        }
        return false
    }

    /// 获取行星对应的角色ID
    func getPlanetOwner(for planetId: Int) -> Int? {
        return planetOwners[planetId]
    }

    /// 加载每个角色的可支配星球数（基于技能ID 2495）
    private func loadMaxPlanets(characterIds: [Int], forceRefresh: Bool = false) async {
        var tempMaxPlanets: [Int: Int] = [:]

        // 并发获取所有角色的技能数据
        await withTaskGroup(of: (Int, Int).self) { group in
            for charId in characterIds {
                group.addTask {
                    do {
                        let skillsResponse = try await CharacterSkillsAPI.shared.fetchCharacterSkills(
                            characterId: charId,
                            forceRefresh: forceRefresh
                        )

                        // 查找技能ID 2495的等级
                        var skillLevel = 0
                        for skill in skillsResponse.skills {
                            if skill.skill_id == 2495 {
                                skillLevel = skill.trained_skill_level
                                break
                            }
                        }

                        // 可支配星球数 = 技能等级 + 1
                        let maxPlanets = skillLevel + 1
                        return (charId, maxPlanets)
                    } catch {
                        Logger.error("获取角色\(charId)技能数据失败: \(error)")
                        // 如果获取失败，默认设置为1
                        return (charId, 1)
                    }
                }
            }

            // 收集结果
            for await (charId, maxPlanets) in group {
                tempMaxPlanets[charId] = maxPlanets
            }
        }

        await MainActor.run {
            self.maxPlanetsByCharacter = tempMaxPlanets
        }
    }

    /// 按人物ID分组行星（用于多人物聚合模式）
    var groupedPlanetsByCharacter: [(characterId: Int, characterName: String, planets: [CharacterPlanetaryInfo], maxPlanets: Int)] {
        guard multiCharacterMode, selectedCharacterIds.count > 1 else {
            return []
        }

        var grouped: [Int: [CharacterPlanetaryInfo]] = [:]

        // 按角色ID分组
        for planetWithOwner in planetsWithOwner {
            if grouped[planetWithOwner.ownerId] == nil {
                grouped[planetWithOwner.ownerId] = []
            }
            grouped[planetWithOwner.ownerId]?.append(planetWithOwner.planet)
        }

        // 转换为数组并排序：当前登录人物排在第一位，其他按角色ID排序
        return grouped.compactMap { charId, planets -> (characterId: Int, characterName: String, planets: [CharacterPlanetaryInfo], maxPlanets: Int)? in
            // 获取角色名称
            let characterName = availableCharacters.first(where: { $0.id == charId })?.name ?? "Unknown"
            // 获取可支配星球数，如果未加载则默认为1
            let maxPlanets = maxPlanetsByCharacter[charId] ?? 1
            return (characterId: charId, characterName: characterName, planets: planets, maxPlanets: maxPlanets)
        }
        .sorted { first, second in
            // 如果第一个是当前登录人物，排在前面
            if first.characterId == characterId {
                return true
            }
            // 如果第二个是当前登录人物，排在前面
            if second.characterId == characterId {
                return false
            }
            // 其他情况按角色ID排序
            return first.characterId < second.characterId
        }
    }

    /// 异步加载所有行星的采集器过期时间，最多6个并发线程
    private func loadExtractorExpiryTimes(planetsWithOwner: [PlanetWithOwner]) async {
        // 取消之前的任务
        expiryLoadingTask?.cancel()

        // 清理之前的加载状态
        await MainActor.run {
            self.loadingPlanets.removeAll()
        }

        expiryLoadingTask = Task {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]

            // 初始化加载状态：将所有行星标记为正在加载
            await MainActor.run {
                self.loadingPlanets = Set(planetsWithOwner.map { planetWithOwner in
                    self.makePlanetKey(characterId: planetWithOwner.ownerId, planetId: planetWithOwner.planet.planetId)
                })
            }

            // 使用 Actor 来限制并发数
            let limiter = ConcurrencyLimiter(maxConcurrent: 6)

            await withTaskGroup(of: (String, Date?, [FinalProduct], ExtractorStatus?).self) { group in
                for planetWithOwner in planetsWithOwner {
                    if Task.isCancelled { break }

                    group.addTask {
                        await limiter.waitForSlot()
                        defer {
                            Task {
                                await limiter.releaseSlot()
                            }
                        }

                        let planetKey = "\(planetWithOwner.ownerId)_\(planetWithOwner.planet.planetId)"

                        do {
                            // 获取行星详情
                            let detail = try await CharacterPlanetaryAPI.fetchPlanetaryDetail(
                                characterId: planetWithOwner.ownerId,
                                planetId: planetWithOwner.planet.planetId,
                                forceRefresh: false
                            )

                            // 查找所有采集器的最早过期时间和统计停工状态
                            var earliestExpiry: Date? = nil
                            let currentTime = Date()
                            var totalExtractors = 0
                            var expiredCount = 0
                            var expiringSoonCount = 0
                            let oneHourFromNow = currentTime.addingTimeInterval(3600) // 1小时后

                            for pin in detail.pins {
                                // 检查是否是采集器（通过extractorDetails判断）
                                if pin.extractorDetails != nil {
                                    totalExtractors += 1

                                    if let expiryTimeString = pin.expiryTime,
                                       let expiryTime = dateFormatter.date(from: expiryTimeString)
                                    {
                                        if expiryTime <= currentTime {
                                            // 已停工
                                            expiredCount += 1
                                        } else if expiryTime <= oneHourFromNow {
                                            // 即将在1小时内停工
                                            expiringSoonCount += 1
                                            // 更新最早过期时间
                                            if earliestExpiry == nil || expiryTime < earliestExpiry! {
                                                earliestExpiry = expiryTime
                                            }
                                        } else {
                                            // 更新最早过期时间
                                            if earliestExpiry == nil || expiryTime < earliestExpiry! {
                                                earliestExpiry = expiryTime
                                            }
                                        }
                                    }
                                }
                            }

                            // 计算最终产品：找出只输出，不输入到其他设施的资源
                            let finalProducts = self.calculateFinalProducts(detail: detail)

                            // 创建采集器状态
                            let extractorStatus = ExtractorStatus(
                                totalCount: totalExtractors,
                                expiredCount: expiredCount,
                                expiringSoonCount: expiringSoonCount
                            )

                            return (planetKey, earliestExpiry, finalProducts, extractorStatus)
                        } catch {
                            Logger.warning("获取行星 \(planetWithOwner.planet.planetId) (角色: \(planetWithOwner.ownerId)) 的采集器过期时间失败: \(error.localizedDescription)")
                            return (planetKey, nil, [], nil)
                        }
                    }
                }

                // 收集结果并更新UI
                var expiryResults: [String: Date] = [:]
                var productResults: [String: [FinalProduct]] = [:]
                var statusResults: [String: ExtractorStatus] = [:]
                var completedPlanetKeys = Set<String>()

                for await (planetKey, expiry, products, status) in group {
                    completedPlanetKeys.insert(planetKey)
                    if let expiry = expiry {
                        expiryResults[planetKey] = expiry
                    }
                    if !products.isEmpty {
                        productResults[planetKey] = products
                    }
                    if let status = status {
                        statusResults[planetKey] = status
                    }
                }

                if !Task.isCancelled {
                    await MainActor.run {
                        self.earliestExtractorExpiry = expiryResults
                        self.finalProducts = productResults
                        self.extractorStatus = statusResults
                        // 从加载集合中移除已完成的行星
                        self.loadingPlanets.subtract(completedPlanetKeys)
                    }
                }
            }
        }

        await expiryLoadingTask?.value
    }

    /// 计算最终产品：找出只输出，不输入到其他设施的资源
    /// 参考 RIFT：最终产品 = (生产的产品 + 采集的产品) - 消费的产品
    /// 即：所有被生产/采集的资源中，没有被工厂消费的资源就是最终产品
    private nonisolated func calculateFinalProducts(detail: PlanetaryDetail) -> [FinalProduct] {
        // 1. 获取所有生产的产品（工厂的输出）
        var producingTypeIds = Set<Int>()
        for pin in detail.pins {
            // 检查是否是工厂
            if let factoryDetails = pin.factoryDetails {
                let schematicId = factoryDetails.schematicId
                if let schematic = getSchematic(schematicId) {
                    producingTypeIds.insert(schematic.outputType.id)
                }
            } else if let schematicId = pin.schematicId {
                // 备用：直接从 pin 获取 schematicId
                if let schematic = getSchematic(schematicId) {
                    producingTypeIds.insert(schematic.outputType.id)
                }
            }
        }

        // 2. 获取所有采集的产品（采集器的输出）
        var extractingTypeIds = Set<Int>()
        for pin in detail.pins {
            if let extractorDetails = pin.extractorDetails,
               let productTypeId = extractorDetails.productTypeId
            {
                extractingTypeIds.insert(productTypeId)
            }
        }

        // 3. 合并生产和采集的产品
        let allProducedTypeIds = producingTypeIds.union(extractingTypeIds)

        // 4. 获取所有消费的产品（工厂的输入）
        var consumingTypeIds = Set<Int>()
        for pin in detail.pins {
            if let factoryDetails = pin.factoryDetails {
                let schematicId = factoryDetails.schematicId
                if let schematic = getSchematic(schematicId) {
                    for inputType in schematic.inputs.keys {
                        consumingTypeIds.insert(inputType.id)
                    }
                }
            } else if let schematicId = pin.schematicId {
                if let schematic = getSchematic(schematicId) {
                    for inputType in schematic.inputs.keys {
                        consumingTypeIds.insert(inputType.id)
                    }
                }
            }
        }

        // 5. 最终产品 = 生产/采集的产品 - 消费的产品
        let finalProductIds = allProducedTypeIds.subtracting(consumingTypeIds)

        // 从数据库获取这些资源的图标信息
        var finalProducts: [FinalProduct] = []
        if !finalProductIds.isEmpty {
            let typeIdsString = finalProductIds.sorted().map { String($0) }.joined(separator: ",")
            let query = "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(typeIdsString))"
            if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let iconFilename = row["icon_filename"] as? String
                    {
                        let name = row["name"] as? String ?? "Unknown"
                        finalProducts.append(FinalProduct(id: typeId, typeId: typeId, icon: iconFilename))
                        Logger.info("最终产品: \(name) (typeId: \(typeId))")
                    }
                }
            }
        }

        // 按typeId排序，确保显示顺序一致
        finalProducts.sort { $0.typeId < $1.typeId }

        Logger.info("找到 \(finalProducts.count) 个最终产品: \(finalProducts.map { "\($0.typeId)" }.joined(separator: ", "))")

        return finalProducts
    }

    /// 从数据库获取配方信息
    private nonisolated func getSchematic(_ schematicId: Int) -> Schematic? {
        let query = """
            SELECT schematic_id, output_typeid, name, cycle_time, output_value, input_typeid, input_value
            FROM planetSchematics
            WHERE schematic_id = ?
        """

        guard case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [schematicId]),
              let row = rows.first,
              let id = row["schematic_id"] as? Int,
              let outputTypeId = row["output_typeid"] as? Int,
              let cycleTime = row["cycle_time"] as? Int,
              let outputValue = row["output_value"] as? Int
        else {
            return nil
        }

        // 获取输出类型信息
        let outputTypeQuery = "SELECT type_id, name, volume FROM types WHERE type_id = ?"
        guard case let .success(outputRows) = DatabaseManager.shared.executeQuery(outputTypeQuery, parameters: [outputTypeId]),
              let outputRow = outputRows.first,
              let outputTypeIdFromDb = outputRow["type_id"] as? Int,
              let outputName = outputRow["name"] as? String,
              let outputVolume = outputRow["volume"] as? Double
        else {
            return nil
        }

        let outputType = Type(id: outputTypeIdFromDb, name: outputName, volume: outputVolume)

        // 解析输入类型ID和数量
        var inputs: [Type: Int64] = [:]
        if let inputTypeIdString = row["input_typeid"] as? String,
           let inputValueString = row["input_value"] as? String
        {
            let inputTypeIds = inputTypeIdString.components(separatedBy: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let inputValues = inputValueString.components(separatedBy: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            if inputTypeIds.count == inputValues.count {
                for i in 0 ..< inputTypeIds.count {
                    let typeId = inputTypeIds[i]
                    let quantity = inputValues[i]

                    let inputTypeQuery = "SELECT type_id, name, volume FROM types WHERE type_id = ?"
                    if case let .success(inputRows) = DatabaseManager.shared.executeQuery(inputTypeQuery, parameters: [typeId]),
                       let inputRow = inputRows.first,
                       let inputTypeIdFromDb = inputRow["type_id"] as? Int,
                       let inputName = inputRow["name"] as? String,
                       let inputVolume = inputRow["volume"] as? Double
                    {
                        let inputType = Type(id: inputTypeIdFromDb, name: inputName, volume: inputVolume)
                        inputs[inputType] = Int64(quantity)
                    }
                }
            }
        }

        return Schematic(
            id: id,
            cycleTime: TimeInterval(cycleTime),
            outputType: outputType,
            outputQuantity: Int64(outputValue),
            inputs: inputs
        )
    }
}

// 并发限制器 Actor
actor ConcurrencyLimiter {
    private var availableSlots: Int
    private var waitingTasks: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        availableSlots = maxConcurrent
    }

    func waitForSlot() async {
        if availableSlots > 0 {
            availableSlots -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waitingTasks.append(continuation)
        }
    }

    func releaseSlot() {
        if !waitingTasks.isEmpty {
            let next = waitingTasks.removeFirst()
            next.resume()
        } else {
            availableSlots += 1
        }
    }
}

// 进度更新 Actor（用于线程安全地更新进度）
actor ProgressActor {
    private var current: Int = 0
    private let total: Int
    private let onUpdate: (Int, Int) -> Void

    init(total: Int, onUpdate: @escaping (Int, Int) -> Void) {
        self.total = total
        self.onUpdate = onUpdate
    }

    func increment() {
        current += 1
        onUpdate(current, total)
    }
}

// 用于存储选中星球信息的结构
struct SelectedPlanet {
    let characterId: Int
    let planetId: Int
    let planetName: String
}

struct CharacterPlanetaryView: View {
    let characterId: Int?
    @StateObject private var viewModel: CharacterPlanetaryViewModel
    @State private var selectedPlanet: SelectedPlanet?
    @State private var showSettingsSheet = false

    init(characterId: Int?) {
        self.characterId = characterId
        _viewModel = StateObject(
            wrappedValue: CharacterPlanetaryViewModel(characterId: characterId))
    }

    var body: some View {
        List {
            // 行星开发计算器功能
            Section(NSLocalizedString("Main_Planetary_calc", comment: "")) {
                NavigationLink {
                    PlanetarySiteFinder(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("Main_Planetary_location_calc", comment: ""))
                }
                NavigationLink {
                    PIOutputCalculatorView(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("Main_Planetary_Output", comment: ""))
                }
                NavigationLink {
                    PIAllInOneMainView(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("Planet_All-in-One_Calc", comment: ""))
                }
                NavigationLink {
                    PIAllInOneSystemFinderMainView(characterId: characterId)
                } label: {
                    Text(
                        NSLocalizedString(
                            "AllInOne_SystemFinder_Title", comment: "查找 All-in-One 星系"
                        ))
                }
                NavigationLink {
                    PIProductionChainView(characterId: characterId)
                } label: {
                    Text(NSLocalizedString("PI_Chain_Title", comment: "生产链分析"))
                }
            }
            if viewModel.isLoading {
                Section(header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))) {
                    if let progress = viewModel.loadingProgress, progress.total > 1 {
                        Text(String(format: NSLocalizedString("Planetary_Loading_Progress", comment: "已加载人物 %d/%d"), progress.current, progress.total))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                if characterId != nil || viewModel.multiCharacterMode {
                    if viewModel.planets.isEmpty {
                        Section(
                            header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))
                        ) {
                            NoDataSection()
                        }
                    } else {
                        // 多人物聚合模式：按人物分组显示
                        if viewModel.multiCharacterMode, viewModel.selectedCharacterIds.count > 1 {
                            let groupedPlanets = viewModel.groupedPlanetsByCharacter
                            if groupedPlanets.isEmpty {
                                Section(
                                    header: Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))
                                ) {
                                    NoDataSection()
                                }
                            } else {
                                ForEach(groupedPlanets, id: \.characterId) { group in
                                    Section(
                                        header: HStack(spacing: 8) {
                                            CharacterPortraitView(characterId: group.characterId)
                                                .frame(width: 24, height: 24)
                                            Text(group.characterName)
                                                .fontWeight(.semibold)
                                                .font(.system(size: 18))
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text("\(group.planets.count)/\(group.maxPlanets)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .textCase(.none)
                                    ) {
                                        ForEach(group.planets, id: \.planetId) { planet in
                                            PlanetRow(
                                                planet: planet,
                                                viewModel: viewModel,
                                                characterId: group.characterId,
                                                onPlanetSelected: { planetId, planetName in
                                                    selectedPlanet = SelectedPlanet(
                                                        characterId: group.characterId,
                                                        planetId: planetId,
                                                        planetName: planetName
                                                    )
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                        } else {
                            // 单人物模式：保持原有显示方式
                            let currentCharacterId = viewModel.multiCharacterMode && !viewModel.selectedCharacterIds.isEmpty
                                ? viewModel.selectedCharacterIds.first!
                                : characterId
                            let maxPlanets = currentCharacterId != nil ? (viewModel.maxPlanetsByCharacter[currentCharacterId!] ?? 1) : 1

                            Section(
                                header: HStack {
                                    Text(NSLocalizedString("Main_Planetary_of_Mine", comment: ""))
                                        .fontWeight(.semibold)
                                        .font(.system(size: 18))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(viewModel.planets.count)/\(maxPlanets)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .textCase(.none)
                            ) {
                                ForEach(viewModel.planets, id: \.planetId) { planet in
                                    PlanetRow(
                                        planet: planet,
                                        viewModel: viewModel,
                                        characterId: viewModel.getPlanetOwner(for: planet.planetId) ?? characterId ?? 0,
                                        onPlanetSelected: { planetId, planetName in
                                            let planetOwnerId = viewModel.getPlanetOwner(for: planetId) ?? characterId ?? 0
                                            selectedPlanet = SelectedPlanet(
                                                characterId: planetOwnerId,
                                                planetId: planetId,
                                                planetName: planetName
                                            )
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Planetary_Title", comment: ""))
        .refreshable {
            // 清理星球详情缓存，防止数据不同步
            let characterIdsToClear: [Int]
            if viewModel.multiCharacterMode, viewModel.selectedCharacterIds.count > 1 {
                characterIdsToClear = Array(viewModel.selectedCharacterIds)
            } else if let characterId = characterId {
                characterIdsToClear = [characterId]
            } else {
                characterIdsToClear = []
            }

            for charId in characterIdsToClear {
                CharacterPlanetaryAPI.clearPlanetDetailCache(characterId: charId)
            }
            await viewModel.loadPlanets(forceRefresh: true)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showSettingsSheet = true
                }) {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            PlanetarySettingsSheet(viewModel: viewModel)
        }
        .sheet(item: $selectedPlanet) { planet in
            NavigationStack {
                PlanetDetailView(
                    characterId: planet.characterId,
                    planetId: planet.planetId,
                    planetName: planet.planetName
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            selectedPlanet = nil
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.primary)
                                .frame(width: 30, height: 30)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

// 行星设置界面
struct PlanetarySettingsSheet: View {
    @ObservedObject var viewModel: CharacterPlanetaryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(isOn: $viewModel.multiCharacterMode) {
                        VStack(alignment: .leading) {
                            Text(
                                NSLocalizedString(
                                    "Planetary_Settings_Multi_Character", comment: "多人物聚合"
                                ))
                            Text(
                                NSLocalizedString(
                                    "Planetary_Settings_Multi_Character_Description",
                                    comment: "聚合显示多个角色的行星数据"
                                )
                            )
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                // 只有在多人物模式开启时才显示角色选择
                if viewModel.multiCharacterMode {
                    Section(
                        header: Text(
                            NSLocalizedString(
                                "Planetary_Settings_Select_Characters", comment: "选择角色"
                            ))
                    ) {
                        ForEach(viewModel.availableCharacters, id: \.id) { character in
                            Button(action: {
                                if viewModel.selectedCharacterIds.contains(character.id) {
                                    viewModel.selectedCharacterIds.remove(character.id)
                                } else {
                                    viewModel.selectedCharacterIds.insert(character.id)
                                }
                            }) {
                                HStack {
                                    // 角色头像
                                    CharacterPortraitView(characterId: character.id)
                                        .padding(.trailing, 8)

                                    Text(character.name)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if viewModel.selectedCharacterIds.contains(character.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // 全选/全不选按钮
                        Button(action: {
                            if viewModel.selectedCharacterIds.count
                                == viewModel.availableCharacters.count
                            {
                                viewModel.selectedCharacterIds = []
                            } else {
                                viewModel.selectedCharacterIds = Set(
                                    viewModel.availableCharacters.map { $0.id })
                            }
                        }) {
                            HStack {
                                Text(NSLocalizedString("Planetary_Filter_Select_All", comment: "全选"))
                                Spacer()
                                if viewModel.selectedCharacterIds.count
                                    == viewModel.availableCharacters.count
                                {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Planetary_Settings_Title", comment: "设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// 让 SelectedPlanet 遵循 Identifiable 协议
extension SelectedPlanet: Identifiable {
    var id: Int { planetId }
}

// 最终产品图标网格视图
struct FinalProductsGridView: View {
    let products: [FinalProduct]

    var body: some View {
        let count = products.count
        let iconSize: CGFloat = count == 1 ? 28 : (count == 2 ? 20 : 16)
        let spacing: CGFloat = count == 1 ? 0 : 4

        VStack(spacing: spacing) {
            if count == 1 {
                // 1个：显示1个
                ProductIcon(product: products[0], size: iconSize)
            } else if count == 2 {
                // 2个：上下显示
                ProductIcon(product: products[0], size: iconSize)
                ProductIcon(product: products[1], size: iconSize)
            } else if count == 3 {
                // 3个：第一行2个，第二行1个
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[2], size: iconSize)
                    Spacer()
                }
            } else if count == 4 {
                // 4个：第一行2个，第二行2个
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[2], size: iconSize)
                    ProductIcon(product: products[3], size: iconSize)
                }
            } else if count == 5 {
                // 5个：第一行3个，第二行2个
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                    ProductIcon(product: products[2], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[3], size: iconSize)
                    ProductIcon(product: products[4], size: iconSize)
                }
            } else {
                // 6个或更多：第一行3个，第二行3个（只显示前6个）
                HStack(spacing: spacing) {
                    ProductIcon(product: products[0], size: iconSize)
                    ProductIcon(product: products[1], size: iconSize)
                    ProductIcon(product: products[2], size: iconSize)
                }
                HStack(spacing: spacing) {
                    ProductIcon(product: products[3], size: iconSize)
                    ProductIcon(product: products[4], size: iconSize)
                    if products.count > 5 {
                        ProductIcon(product: products[5], size: iconSize)
                    }
                }
            }
        }
    }
}

// 产品图标视图
struct ProductIcon: View {
    let product: FinalProduct
    let size: CGFloat

    var body: some View {
        Image(uiImage: IconManager.shared.loadUIImage(for: product.icon))
            .resizable()
            .frame(width: size, height: size)
            .cornerRadius(4)
    }
}

// 行星行组件
struct PlanetRow: View {
    let planet: CharacterPlanetaryInfo
    let viewModel: CharacterPlanetaryViewModel
    let characterId: Int
    let onPlanetSelected: (Int, String) -> Void

    var body: some View {
        Button {
            let planetName = viewModel.getPlanetName(for: planet.planetId)
            onPlanetSelected(planet.planetId, planetName)
        } label: {
            HStack {
                if let typeInfo = viewModel.getPlanetTypeInfo(for: planet.planetType) {
                    Image(uiImage: IconManager.shared.loadUIImage(for: typeInfo.icon))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        // 显示星系安等（如果有）
                        if let security = viewModel.getSystemSecurity(for: planet.solarSystemId) {
                            Text(formatSystemSecurity(security))
                                .foregroundColor(getSecurityColor(security))
                                .font(.system(.headline, design: .monospaced))
                        }
                        Text(viewModel.getPlanetName(for: planet.planetId))
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .contextMenu {
                        let planetName = viewModel.getPlanetName(for: planet.planetId)
                        Button {
                            UIPasteboard.general.string = planetName
                        } label: {
                            Label(
                                NSLocalizedString("Misc_Copy_Name", comment: ""),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }

                    if let typeInfo = viewModel.getPlanetTypeInfo(for: planet.planetType) {
                        Text(typeInfo.name)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    } else {
                        Text(NSLocalizedString("Main_Planetary_Unknown_Type", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    // 显示采集器停工状态
                    if let status = viewModel.getExtractorStatus(for: planet.planetId, characterId: characterId), status.totalCount > 0 {
                        if status.expiredCount > 0 {
                            // 显示已停工的采集器数量
                            Text(String(format: NSLocalizedString("Planet_Extractor_Expired_Count", comment: "%d/%d个采集器已停工"), status.expiredCount, status.totalCount))
                                .font(.caption2)
                                .foregroundColor(.red)
                        } else if status.expiringSoonCount > 0 {
                            // 显示即将停工的采集器数量
                            Text(String(format: NSLocalizedString("Planet_Extractor_Expiring_Soon_Count", comment: "%d/%d个采集器即将停工"), status.expiringSoonCount, status.totalCount))
                                .font(.caption2)
                                .foregroundColor(.red)
                        } else if let expiryDate = viewModel.getEarliestExtractorExpiry(for: planet.planetId, characterId: characterId) {
                            // 显示采集器最早过期时间
                            let timeRemaining = expiryDate.timeIntervalSince(Date())
                            if timeRemaining > 0 {
                                Text("\(NSLocalizedString("Planet_Detail_Extractor_Expiry_Time", comment: "")): \(formatTimeRemaining(timeRemaining))")
                                    .font(.caption2)
                                    .foregroundColor(timeRemaining < 1 * 24 * 3600 ? .red : .green)
                            } else {
                                Text(NSLocalizedString("Planet_Detail_Extractor_Expired", comment: ""))
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    } else if let expiryDate = viewModel.getEarliestExtractorExpiry(for: planet.planetId, characterId: characterId) {
                        // 兼容旧逻辑：如果没有状态信息，显示过期时间
                        let timeRemaining = expiryDate.timeIntervalSince(Date())
                        if timeRemaining > 0 {
                            Text("\(NSLocalizedString("Planet_Detail_Extractor_Expiry_Time", comment: "")): \(formatTimeRemaining(timeRemaining))")
                                .font(.caption2)
                                .foregroundColor(timeRemaining < 1 * 24 * 3600 ? .red : .green)
                        } else {
                            Text(NSLocalizedString("Planet_Detail_Extractor_Expired", comment: ""))
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                }

                Spacer()

                // 显示加载指示器或最终产品图标
                if viewModel.isLoadingPlanetDetail(for: planet.planetId, characterId: characterId) {
                    ProgressView()
                        .frame(width: 28, height: 28)
                } else {
                    let products = viewModel.getFinalProducts(for: planet.planetId, characterId: characterId)
                    if !products.isEmpty {
                        FinalProductsGridView(products: products)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// 格式化剩余时间显示
private func formatTimeRemaining(_ interval: TimeInterval) -> String {
    if interval < 0 {
        return ""
    }

    let totalSeconds = Int(interval)
    let days = totalSeconds / (24 * 3600)
    let hours = totalSeconds / 3600 % 24
    let minutes = totalSeconds / 60 % 60

    if days > 0 {
        if hours > 0 {
            return String(format: NSLocalizedString("Time_Days_Hours", comment: ""), days, hours)
        } else {
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        }
    } else if hours > 0 {
        if minutes > 0 {
            return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes)
        } else {
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        }
    } else if minutes > 0 {
        return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
    } else {
        return NSLocalizedString("Time_Just_Now", comment: "刚刚")
    }
}
