import SwiftUI
import Foundation

/// 植入体属性加成
struct ImplantAttributes {
    var charismaBonus: Int = 0
    var intelligenceBonus: Int = 0
    var memoryBonus: Int = 0
    var perceptionBonus: Int = 0
    var willpowerBonus: Int = 0
}

struct CharacterSkillsView: View {
    let characterId: Int
    let databaseManager: DatabaseManager
    @State private var skillQueue: [SkillQueueItem] = []
    @State private var skillNames: [Int: String] = [:]
    @State private var isRefreshing = false
    @State private var isLoading = true
    @State private var isLoadingInjectors = true
    @State private var skillIcon: Image?
    @State private var injectorCalculation: InjectorCalculation?
    @State private var characterTotalSP: Int = 0
    @State private var injectorPrices: (large: Double?, small: Double?) = (nil, nil)
    @State private var characterAttributes: CharacterAttributes?
    @State private var implantBonuses: ImplantAttributes?
    @State private var trainingRates: [Int: Int] = [:] // [skillId: pointsPerHour]
    @State private var hasLoadedData = false
    @State private var optimalAttributes: OptimalAttributeAllocation?
    @State private var attributeComparisons: [(name: String, icon: String, current: Int, optimal: Int, diff: Int)] = []
    
    private func updateAttributeComparisons() {
        guard let attrs = characterAttributes,
              let optimal = optimalAttributes,
              let bonuses = implantBonuses else {
            attributeComparisons = []
            return
        }
        
        // 计算基础属性（当前属性减去植入体加成）
        let baseCharisma = attrs.charisma - bonuses.charismaBonus
        let baseIntelligence = attrs.intelligence - bonuses.intelligenceBonus
        let baseMemory = attrs.memory - bonuses.memoryBonus
        let basePerception = attrs.perception - bonuses.perceptionBonus
        let baseWillpower = attrs.willpower - bonuses.willpowerBonus
        
        // Logger.debug("属性计算详情:")
        // Logger.debug("感知 - 当前总值: \(attrs.perception), 基础值: \(basePerception), 植入体加成: \(bonuses.perceptionBonus), 最优基础值: \(optimal.perception), 变化: \(optimal.perception - basePerception)")
        // Logger.debug("记忆 - 当前总值: \(attrs.memory), 基础值: \(baseMemory), 植入体加成: \(bonuses.memoryBonus), 最优基础值: \(optimal.memory), 变化: \(optimal.memory - baseMemory)")
        // Logger.debug("意志 - 当前总值: \(attrs.willpower), 基础值: \(baseWillpower), 植入体加成: \(bonuses.willpowerBonus), 最优基础值: \(optimal.willpower), 变化: \(optimal.willpower - baseWillpower)")
        // Logger.debug("智力 - 当前总值: \(attrs.intelligence), 基础值: \(baseIntelligence), 植入体加成: \(bonuses.intelligenceBonus), 最优基础值: \(optimal.intelligence), 变化: \(optimal.intelligence - baseIntelligence)")
        // Logger.debug("魅力 - 当前总值: \(attrs.charisma), 基础值: \(baseCharisma), 植入体加成: \(bonuses.charismaBonus), 最优基础值: \(optimal.charisma), 变化: \(optimal.charisma - baseCharisma)")
        
        attributeComparisons = [
            (NSLocalizedString("Character_Attribute_Perception", comment: ""), "perception", 
             attrs.perception, optimal.perception + bonuses.perceptionBonus, optimal.perception - basePerception),
            (NSLocalizedString("Character_Attribute_Memory", comment: ""), "memory", 
             attrs.memory, optimal.memory + bonuses.memoryBonus, optimal.memory - baseMemory),
            (NSLocalizedString("Character_Attribute_Willpower", comment: ""), "willpower", 
             attrs.willpower, optimal.willpower + bonuses.willpowerBonus, optimal.willpower - baseWillpower),
            (NSLocalizedString("Character_Attribute_Intelligence", comment: ""), "intelligence", 
             attrs.intelligence, optimal.intelligence + bonuses.intelligenceBonus, optimal.intelligence - baseIntelligence),
            (NSLocalizedString("Character_Attribute_Charisma", comment: ""), "charisma", 
             attrs.charisma, optimal.charisma + bonuses.charismaBonus, optimal.charisma - baseCharisma)
        ]
    }
    
    private var activeSkills: [SkillQueueItem] {
        let now = Date()
        // 找到当前时间正在训练的技能的位置
        let currentPosition = skillQueue.firstIndex { skill in
            guard let startDate = skill.start_date,
                  let finishDate = skill.finish_date else {
                return false
            }
            return now >= startDate && now <= finishDate
        } ?? 0
        
        // 从当前位置开始的所有技能
        let activeQueue = skillQueue
            .filter { $0.queue_position >= currentPosition }
            .sorted { $0.queue_position < $1.queue_position }
        
        // 如果有正在训练的技能，将其移到第一位
        if let trainingIndex = activeQueue.firstIndex(where: { $0.isCurrentlyTraining }) {
            var reorderedQueue = activeQueue
            let trainingSkill = reorderedQueue.remove(at: trainingIndex)
            reorderedQueue.insert(trainingSkill, at: 0)
            return reorderedQueue
        }
        
        return activeQueue
    }
    
    private var isQueuePaused: Bool {
        guard let firstSkill = activeSkills.first,
              let _ = firstSkill.start_date,
              let _ = firstSkill.finish_date else {
            return true
        }
        return false
    }
    
    private var totalRemainingTime: TimeInterval? {
        guard let lastSkill = activeSkills.last,
              let finishDate = lastSkill.finish_date,
              finishDate.timeIntervalSinceNow > 0 else {
            return nil
        }
        return finishDate.timeIntervalSinceNow
    }
    
    // 获取技能的当前等级（队列中最低等级-1）
    private func getCurrentLevel(for skillId: Int) -> Int {
        let minLevel = activeSkills
            .filter { $0.skill_id == skillId }
            .map { $0.finished_level }
            .min() ?? 1
        return minLevel - 1
    }
    
    // 计算注入器总价值
    private var totalInjectorCost: Double? {
        guard let calculation = injectorCalculation else {
            Logger.debug("计算总价失败 - 没有注入器计算结果")
            return nil
        }
        guard let largePrice = injectorPrices.large else {
            Logger.debug("计算总价失败 - 没有大型注入器价格")
            return nil
        }
        guard let smallPrice = injectorPrices.small else {
            Logger.debug("计算总价失败 - 没有小型注入器价格")
            return nil
        }
        
        return Double(calculation.largeInjectorCount) * largePrice + 
               Double(calculation.smallInjectorCount) * smallPrice
    }
    
    var body: some View {
        List {
            // 第一个列表 - 属性和技能目录导航
            navigationSection
            
            // 第二个列表 - 技能队列
            skillQueueSection
            
            // 第三个列表 - 注入器需求
            injectorSection
            
            // 第四个列表 - 属性对比
            attributeComparisonSection
        }
        .navigationTitle(NSLocalizedString("Main_Skills", comment: ""))
        .refreshable {
            await refreshSkillQueue()
        }
        .task {
            if !hasLoadedData {
                await loadSkillQueue()
                hasLoadedData = true
            }
        }
    }
    
    @ViewBuilder
    private var navigationSection: some View {
        Section {
            NavigationLink {
                CharacterAttributesView(characterId: characterId)
            } label: {
                HStack {
                    Image("attributes")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                        .drawingGroup()
                    Text(NSLocalizedString("Main_Skills_Attribute", comment: ""))
                }
            }
            
            NavigationLink {
                SkillCategoryView(characterId: characterId, databaseManager: databaseManager)
            } label: {
                HStack {
                    Image("skills")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .cornerRadius(6)
                        .drawingGroup()
                    Text(NSLocalizedString("Main_Skills_Category", comment: ""))
                }
            }
            
            NavigationLink {
                SkillPlanView(characterId: characterId, databaseManager: databaseManager)
            } label: {
                HStack {
                    Image("notegroup")
                        .resizable()
                        .frame(width: 32, height: 36)
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("Main_Skills_Plan", comment: ""))
                }
            }
        } header: {
            Text(NSLocalizedString("Main_Skills_Categories", comment: ""))
        }
    }
    
    @ViewBuilder
    private var skillQueueSection: some View {
        Section {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if skillQueue.isEmpty {
                Text(NSLocalizedString("Main_Skills_Queue_Empty", comment: "").replacingOccurrences(of: "$num", with: "0"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(activeSkills) { item in
                    NavigationLink {
                        ShowItemInfo(
                            databaseManager: databaseManager,
                            itemID: item.skill_id
                        )
                    } label: {
                        skillQueueItemView(item)
                    }
                }
            }
        } header: {
            skillQueueHeader
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
    }
    
    @ViewBuilder
    private var injectorSection: some View {
        if !skillQueue.isEmpty, !isLoadingInjectors, let calculation = injectorCalculation {
            Section {
                // 大型注入器
                if let largeInfo = getInjectorInfo(typeId: SkillInjectorCalculator.largeInjectorTypeId) {
                    injectorItemView(info: largeInfo, count: calculation.largeInjectorCount, typeId: SkillInjectorCalculator.largeInjectorTypeId)
                }
                
                // 小型注入器
                if let smallInfo = getInjectorInfo(typeId: SkillInjectorCalculator.smallInjectorTypeId) {
                    injectorItemView(info: smallInfo, count: calculation.smallInjectorCount, typeId: SkillInjectorCalculator.smallInjectorTypeId)
                }
                
                // 总计所需技能点和预计价格
                injectorSummaryView(calculation: calculation)
            } header: {
                Text(NSLocalizedString("Main_Skills_Required_Injectors", comment: ""))
            }
        }
    }
    
    @ViewBuilder
    private var attributeComparisonSection: some View {
        if !attributeComparisons.isEmpty {
            Section {
                ForEach(attributeComparisons, id: \.name) { attr in
                    attributeComparisonItemView(attr)
                }
                
                if let optimal = optimalAttributes {
                    Text(String(format: NSLocalizedString("Main_Skills_Optimal_Attributes_Time_Saved", comment: ""), 
                              formatTimeInterval(optimal.savedTime)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(NSLocalizedString("Main_Skills_Optimal_Attributes", comment: ""))
            }
        }
    }
    
    @ViewBuilder
    private var skillQueueHeader: some View {
        if skillQueue.isEmpty {
            Text(String(format: NSLocalizedString("Main_Skills_Queue_Count", comment: ""), 0))
        } else if isQueuePaused {
            Text(String(format: NSLocalizedString("Main_Skills_Queue_Count_Paused", comment: ""),
                      activeSkills.count))
        } else if let totalTime = totalRemainingTime {
            Text(String(format: NSLocalizedString("Main_Skills_Queue_Count_Time", comment: ""),
                      activeSkills.count,
                      formatTimeInterval(totalTime)))
        } else {
            Text(String(format: NSLocalizedString("Main_Skills_Queue_Count", comment: ""),
                      activeSkills.count))
        }
    }
    
    @ViewBuilder
    private func skillQueueItemView(_ item: SkillQueueItem) -> some View {
        HStack(spacing: 8) {
            if let icon = skillIcon {
                icon
                    .resizable()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 2) {
                    Text(skillNames[item.skill_id] ?? NSLocalizedString("Main_Database_Loading", comment: ""))
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: NSLocalizedString("Main_Skills_Level", comment: ""), item.finished_level))
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.trailing, 2)
                    SkillLevelIndicator(
                        currentLevel: getCurrentLevel(for: item.skill_id),
                        trainingLevel: item.finished_level,
                        isTraining: item.isCurrentlyTraining
                    )
                    .padding(.trailing, 4)
                }
                
                if let progress = calculateProgress(item) {
                    skillProgressView(item: item, progress: progress)
                }
            }
        }
    }
    
    @ViewBuilder
    private func skillProgressView(item: SkillQueueItem, progress: ProgressInfo) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(String(format: NSLocalizedString("Main_Skills_Points_Progress", comment: ""), 
                          formatNumber(Int(progress.current)), 
                          formatNumber(progress.total)))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let rate = trainingRates[item.skill_id] {
                    Text("(\(formatNumber(rate))/h)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                skillTimeView(item: item, progress: progress)
            }
            
            if item.isCurrentlyTraining {
                ProgressView(value: progress.percentage)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding(.top, 1)
            }
        }
    }
    
    @ViewBuilder
    private func skillTimeView(item: SkillQueueItem, progress: ProgressInfo) -> some View {
        if item.isCurrentlyTraining {
            if let remainingTime = item.remainingTime {
                Text(String(format: NSLocalizedString("Main_Skills_Time_Remaining", comment: ""), 
                          formatTimeInterval(remainingTime)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if let startDate = item.start_date,
                  let finishDate = item.finish_date {
            // 如果有服务器时间，使用服务器时间
            let trainingTime = finishDate.timeIntervalSince(startDate)
            Text(String(format: NSLocalizedString("Main_Skills_Time_Required", comment: ""), 
                      formatTimeInterval(trainingTime)))
                .font(.caption)
                .foregroundColor(.secondary)
        } else if isQueuePaused {
            // 如果队列暂停且没有服务器时间，才使用计算的时间
            if let rate = trainingRates[item.skill_id] {
                let remainingSP = progress.total - Int(progress.current)
                let trainingTimeHours = Double(remainingSP) / Double(rate)
                let trainingTime = trainingTimeHours * 3600 // 转换为秒
                
                Text(String(format: NSLocalizedString("Main_Skills_Time_Required", comment: ""), 
                          formatTimeInterval(trainingTime)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func injectorItemView(info: InjectorInfo, count: Int, typeId: Int) -> some View {
        NavigationLink {
            ShowItemInfo(
                databaseManager: databaseManager,
                itemID: typeId
            )
        } label: {
            HStack {
                IconManager.shared.loadImage(for: info.iconFilename)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                Text(info.name)
                Spacer()
                Text("\(count)")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func injectorSummaryView(calculation: InjectorCalculation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: NSLocalizedString("Main_Skills_Total_Required_SP", comment: ""), 
                      FormatUtil.format(Double(calculation.totalSkillPoints))))
            if let totalCost = totalInjectorCost {
                Text(String(format: NSLocalizedString("Main_Skills_Total_Injector_Cost", comment: ""), 
                          FormatUtil.formatISK(totalCost)))
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
    
    @ViewBuilder
    private func attributeComparisonItemView(_ attr: (name: String, icon: String, current: Int, optimal: Int, diff: Int)) -> some View {
        HStack {
            Image(attr.icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(4)
            Text(attr.name)
            Spacer()
            if attr.diff == 0 {
                Text("\(attr.current)")
                    .foregroundColor(.secondary)
            } else {
                Text("\(attr.current)(\(attr.diff > 0 ? "+" : "-")\(abs(attr.diff))) → \(attr.current + attr.diff)")
                    .foregroundColor(attr.diff > 0 ? .green : .red)
            }
        }
    }
    
    private func refreshSkillQueue() async {
        isRefreshing = true
        await loadSkillQueue(forceRefresh: true)
        isRefreshing = false
    }
    
    private func loadSkillQueue(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // 加载角色属性
            characterAttributes = try await CharacterSkillsAPI.shared.fetchAttributes(characterId: characterId)
            
            // 加载植入体加成
            implantBonuses = await SkillTrainingCalculator.getImplantBonuses(characterId: characterId)
            
            Logger.debug("开始加载技能队列...")
            // 加载技能队列
            skillQueue = try await CharacterSkillsAPI.shared.fetchSkillQueue(characterId: characterId, forceRefresh: forceRefresh)
            Logger.debug("获取到技能队列，数量: \(skillQueue.count)")
            
            // 收集所有技能ID
            let skillIds = skillQueue.map { $0.skill_id }
            
            // 批量加载技能名称
            let nameQuery = """
                SELECT type_id, name
                FROM types
                WHERE type_id IN (\(skillIds.map { String($0) }.joined(separator: ",")))
            """
            
            if case .success(let rows) = databaseManager.executeQuery(nameQuery) {
                for row in rows {
                    if let typeId = row["type_id"] as? Int,
                       let name = row["name"] as? String {
                        skillNames[typeId] = name
                    }
                }
            }
            
            // 预加载所有技能属性到缓存
            SkillTrainingCalculator.preloadSkillAttributes(skillIds: skillIds, databaseManager: databaseManager)
            
            // 计算训练速度
            if let attrs = characterAttributes {
                for skillId in skillIds {
                    if let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(skillId: skillId, databaseManager: databaseManager),
                       let rate = SkillTrainingCalculator.calculateTrainingRate(
                        primaryAttrId: primary,
                        secondaryAttrId: secondary,
                        attributes: attrs
                    ) {
                        trainingRates[skillId] = rate
                    }
                }
            }
            
            // 计算最优属性分配
            if let attrs = characterAttributes {
                let queueInfo = activeSkills.compactMap { item -> (skillId: Int, remainingSP: Int, startDate: Date?, finishDate: Date?)? in
                    guard let levelEndSp = item.level_end_sp,
                          let trainingStartSp = item.training_start_sp else {
                        return nil
                    }
                    
                    return (
                        skillId: item.skill_id,
                        remainingSP: levelEndSp - trainingStartSp,
                        startDate: item.start_date,
                        finishDate: item.finish_date
                    )
                }
                
                if let optimal = await SkillTrainingCalculator.calculateOptimalAttributes(
                    skillQueue: queueInfo,
                    databaseManager: databaseManager,
                    currentAttributes: attrs,
                    characterId: characterId
                ) {
                    await MainActor.run {
                        optimalAttributes = OptimalAttributeAllocation(
                            charisma: optimal.charisma,
                            intelligence: optimal.intelligence,
                            memory: optimal.memory,
                            perception: optimal.perception,
                            willpower: optimal.willpower,
                            totalTrainingTime: optimal.totalTrainingTime,
                            currentTrainingTime: optimal.currentTrainingTime
                        )
                        // 更新属性比较
                        updateAttributeComparisons()
                    }
                }
            }
            
            // 异步加载注入器计算结果
            Task {
                await calculateInjectors()
            }
            
        } catch {
            Logger.error("加载技能队列失败: \(error)")
        }
    }
    
    /// 计算注入器需求并加载价格
    private func calculateInjectors() async {
        isLoadingInjectors = true
        defer { isLoadingInjectors = false }
        
        // 计算队列中所需的总技能点数
        var totalRequiredSP = 0
        for item in skillQueue {
            if let endSP = item.level_end_sp,
               let startSP = item.training_start_sp {
                if item.isCurrentlyTraining {
                    // 对于正在训练的技能，从当前训练进度开始计算
                    if let finishDate = item.finish_date,
                       let startDate = item.start_date {
                        let now = Date()
                        let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                        let trainedTime = now.timeIntervalSince(startDate)
                        let progress = trainedTime / totalTrainingTime
                        let totalSP = endSP - startSP
                        let trainedSP = Int(Double(totalSP) * progress)
                        let remainingSP = totalSP - trainedSP
                        totalRequiredSP += remainingSP
                        Logger.debug("正在训练的技能 \(item.skill_id) - 总需求: \(totalSP), 已训练: \(trainedSP), 剩余: \(remainingSP)")
                    }
                } else {
                    // 对于未开始训练的技能，计算全部所需点数
                    let requiredSP = endSP - startSP
                    totalRequiredSP += requiredSP
                    Logger.debug("未训练的技能 \(item.skill_id) - 需要: \(requiredSP)")
                }
            }
        }
        Logger.debug("队列总需求技能点: \(totalRequiredSP)")
        
        // 获取角色总技能点数
        let characterTotalSP = await getCharacterTotalSP()
        
        // 计算注入器需求
        injectorCalculation = SkillInjectorCalculator.calculate(
            requiredSkillPoints: totalRequiredSP,
            characterTotalSP: characterTotalSP
        )
        if let calc = injectorCalculation {
            Logger.debug("计算结果 - 大型注入器: \(calc.largeInjectorCount), 小型注入器: \(calc.smallInjectorCount)")
        }
        
        // 获取注入器价格
        await loadInjectorPrices()
    }
    
    /// 获取角色总技能点数
    private func getCharacterTotalSP() async -> Int {
        // 从数据库获取角色当前的总技能点数
        let query = """
            SELECT total_sp, unallocated_sp
            FROM character_skills
            WHERE character_id = ?
        """
        if case .success(let rows) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [characterId]),
           let row = rows.first {
            // 处理total_sp
            let totalSP: Int
            if let value = row["total_sp"] as? Int {
                totalSP = value
            } else if let value = row["total_sp"] as? Int64 {
                totalSP = Int(value)
            } else {
                totalSP = 0
                Logger.error("无法解析total_sp")
            }
            
            // 处理unallocated_sp
            let unallocatedSP: Int
            if let value = row["unallocated_sp"] as? Int {
                unallocatedSP = value
            } else if let value = row["unallocated_sp"] as? Int64 {
                unallocatedSP = Int(value)
            } else {
                unallocatedSP = 0
                Logger.error("无法解析unallocated_sp")
            }
            
            let characterTotalSP = totalSP + unallocatedSP
            Logger.debug("角色总技能点: \(characterTotalSP) (已分配: \(totalSP), 未分配: \(unallocatedSP))")
            return characterTotalSP
        }
        
        // 如果无法从数据库获取，尝试从API获取
        do {
            let skillsInfo = try await CharacterSkillsAPI.shared.fetchCharacterSkills(characterId: characterId, forceRefresh: true)
            let characterTotalSP = skillsInfo.total_sp + skillsInfo.unallocated_sp
            Logger.debug("从API获取角色总技能点: \(characterTotalSP)")
            return characterTotalSP
        } catch {
            Logger.error("获取技能点数据失败: \(error)")
            return 0
        }
    }
    
    private func loadInjectorPrices() async {
        Logger.debug("开始加载注入器价格 - 大型注入器ID: \(SkillInjectorCalculator.largeInjectorTypeId), 小型注入器ID: \(SkillInjectorCalculator.smallInjectorTypeId)")
        
        // 获取大型和小型注入器的价格
        let prices = await MarketPriceUtil.getMarketPrices(typeIds: [
            SkillInjectorCalculator.largeInjectorTypeId,
            SkillInjectorCalculator.smallInjectorTypeId
        ])
        
        Logger.debug("获取到价格数据: \(prices)")
        
        // 确保两个价格都有值才更新
        if let largePrice = prices[SkillInjectorCalculator.largeInjectorTypeId],
           let smallPrice = prices[SkillInjectorCalculator.smallInjectorTypeId] {
            // 在主线程一次性更新两个价格
            await MainActor.run {
                injectorPrices = (large: largePrice, small: smallPrice)
            }
        } else {
            Logger.debug("价格数据不完整 - large: \(prices[SkillInjectorCalculator.largeInjectorTypeId] as Any), small: \(prices[SkillInjectorCalculator.smallInjectorTypeId] as Any)")
        }
    }
    
    private struct InjectorInfo {
        let name: String
        let iconFilename: String
    }
    
    private func getInjectorInfo(typeId: Int) -> InjectorInfo? {
        let query = """
            SELECT name, icon_filename
            FROM types
            WHERE type_id = ?
        """
        if case .success(let rows) = databaseManager.executeQuery(query, parameters: [typeId]),
           let row = rows.first,
           let name = row["name"] as? String,
           let iconFilename = row["icon_filename"] as? String {
            return InjectorInfo(name: name, iconFilename: iconFilename)
        }
        return nil
    }
    
    private struct ProgressInfo {
        let current: Double
        let total: Int
        let percentage: Double
    }
    
    private func calculateProgress(_ item: SkillQueueItem) -> ProgressInfo? {
        guard let levelEndSp = item.level_end_sp,
              let trainingStartSp = item.training_start_sp else {
            return nil
        }
        
        var currentSP = Double(trainingStartSp)
        
        // 如果技能正在训练中，计算当前进度
        if let startDate = item.start_date,
           let finishDate = item.finish_date {
            let now = Date()
            
            // 如果还没开始训练
            if now < startDate {
                currentSP = Double(trainingStartSp)
            }
            // 如果已经完成训练
            else if now > finishDate {
                currentSP = Double(levelEndSp)
            }
            // 正在训练中
            else {
                let totalTrainingTime = finishDate.timeIntervalSince(startDate)
                let trainedTime = now.timeIntervalSince(startDate)
                let timeProgress = trainedTime / totalTrainingTime
                
                let remainingSP = levelEndSp - trainingStartSp
                let trainedSP = Double(remainingSP) * timeProgress
                currentSP = Double(trainingStartSp) + trainedSP
            }
        }
        
        return ProgressInfo(
            current: currentSP,
            total: levelEndSp,
            percentage: currentSP / Double(levelEndSp)
        )
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        // 先转换为分钟
        let totalMinutes = Int(ceil(interval / 60))
        let days = totalMinutes / (24 * 60)
        let remainingMinutes = totalMinutes % (24 * 60)
        let hours = remainingMinutes / 60
        let minutes = remainingMinutes % 60
        
        if days > 0 {
            // 如果有剩余分钟，小时数要加1
            let adjustedHours = (remainingMinutes % 60 > 0) ? hours + 1 : hours
            if adjustedHours > 0 {
                return String(format: NSLocalizedString("Time_Days_Hours", comment: ""), 
                            days, adjustedHours)
            }
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        } else if hours > 0 {
            // 如果有剩余分钟，分钟数要向上取整
            if minutes > 0 {
                return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), 
                            hours, minutes)
            }
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        }
        // 分钟数已经在一开始就向上取整了
        return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
    
    private struct OptimalAttributeAllocation {
        let charisma: Int
        let intelligence: Int
        let memory: Int
        let perception: Int
        let willpower: Int
        let totalTrainingTime: TimeInterval
        let currentTrainingTime: TimeInterval
        
        var savedTime: TimeInterval {
            currentTrainingTime - totalTrainingTime
        }
    }
}
