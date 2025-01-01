import SwiftUI

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
    @State private var trainingRates: [Int: Int] = [:] // [skillId: pointsPerHour]
    
    private var activeSkills: [SkillQueueItem] {
        skillQueue.sorted { $0.queue_position < $1.queue_position }
    }
    
    private var isQueuePaused: Bool {
        guard let firstSkill = activeSkills.first,
              firstSkill.isCurrentlyTraining else {
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
            // 第一个列表 - 两个可点击单元格
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
                .frame(height: 36)
                
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
                .frame(height: 36)
            } header: {
                Text(NSLocalizedString("Main_Skills_Categories", comment: ""))
            }
            
            // 第二个列表 - 技能队列
            Section {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .frame(height: 36)
                } else if skillQueue.isEmpty {
                    Text(NSLocalizedString("Main_Skills_Queue_Empty", comment: "").replacingOccurrences(of: "$num", with: "0"))
                        .foregroundColor(.secondary)
                        .frame(height: 36)
                } else {
                    ForEach(activeSkills) { item in
                        NavigationLink {
                            ShowItemInfo(
                                databaseManager: databaseManager,
                                itemID: item.skill_id
                            )
                        } label: {
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
                                        // 添加等级指示器
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
                                            if item.isCurrentlyTraining {
                                                if let remainingTime = item.remainingTime {
                                                    Text(String(format: NSLocalizedString("Main_Skills_Time_Remaining", comment: ""), 
                                                              formatTimeInterval(remainingTime)))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            } else if let startDate = item.start_date,
                                                      let finishDate = item.finish_date {
                                                let trainingTime = finishDate.timeIntervalSince(startDate)
                                                Text(String(format: NSLocalizedString("Main_Skills_Time_Required", comment: ""), 
                                                          formatTimeInterval(trainingTime)))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        // 只对正在训练的技能显示进度条
                                        if item.isCurrentlyTraining {
                                            ProgressView(value: progress.percentage)
                                                .progressViewStyle(LinearProgressViewStyle())
                                                .padding(.top, 1)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: item.isCurrentlyTraining ? 44 : 36)
                    }
                }
            } header: {
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
            
            // 第三个列表 - 注入器需求（只在有技能队列时显示）
            if !skillQueue.isEmpty, !isLoadingInjectors, let calculation = injectorCalculation {
                Section {
                    // 大型注入器
                    if let largeInfo = getInjectorInfo(typeId: SkillInjectorCalculator.largeInjectorTypeId) {
                        NavigationLink {
                            ShowItemInfo(
                                databaseManager: databaseManager,
                                itemID: SkillInjectorCalculator.largeInjectorTypeId
                            )
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: largeInfo.iconFilename)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(largeInfo.name)
                                Spacer()
                                Text("\(calculation.largeInjectorCount)")
                                    .font(.body)
                            }
                            .frame(height: 36)
                        }
                    }
                    
                    // 小型注入器
                    if let smallInfo = getInjectorInfo(typeId: SkillInjectorCalculator.smallInjectorTypeId) {
                        NavigationLink {
                            ShowItemInfo(
                                databaseManager: databaseManager,
                                itemID: SkillInjectorCalculator.smallInjectorTypeId
                            )
                        } label: {
                            HStack {
                                IconManager.shared.loadImage(for: smallInfo.iconFilename)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)
                                Text(smallInfo.name)
                                Spacer()
                                Text("\(calculation.smallInjectorCount)")
                                    .font(.body)
                            }
                            .frame(height: 36)
                        }
                    }
                    
                    // 总计所需技能点和预计价格
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
                } header: {
                    Text(NSLocalizedString("Main_Skills_Required_Injectors", comment: ""))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Skills", comment: ""))
        .refreshable {
            await refreshSkillQueue()
        }
        .task {
            await loadSkillQueue()
        }
    }
    
    private func formatTimeComponents(_ interval: TimeInterval) -> (days: Int, hours: Int, minutes: Int) {
        let days = Int(interval) / (24 * 3600)
        let hours = Int(interval) / 3600 % 24
        let minutes = Int(interval) / 60 % 60
        return (days, hours, minutes)
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
            
            Logger.debug("开始加载技能队列...")
            // 加载技能队列
            skillQueue = try await CharacterSkillsAPI.shared.fetchSkillQueue(characterId: characterId, forceRefresh: forceRefresh)
            Logger.debug("获取到技能队列，数量: \(skillQueue.count)")
            
            // 加载技能名称和训练速度
            for item in skillQueue {
                // 加载技能名称
                let nameQuery = "SELECT name FROM types WHERE type_id = ?"
                if case .success(let rows) = databaseManager.executeQuery(nameQuery, parameters: [item.skill_id]),
                   let row = rows.first,
                   let name = row["name"] as? String {
                    skillNames[item.skill_id] = name
                }
                
                // 加载训练速度
                if let attrs = characterAttributes,
                   let (primary, secondary) = SkillTrainingCalculator.getSkillAttributes(
                       skillId: item.skill_id,
                       databaseManager: databaseManager
                   ) {
                    if let rate = SkillTrainingCalculator.calculateTrainingRate(
                        primaryAttrId: primary,
                        secondaryAttrId: secondary,
                        attributes: attrs
                    ) {
                        trainingRates[item.skill_id] = rate
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
        let components = formatTimeComponents(interval)
        
        if components.days > 0 {
            if components.hours > 0 {
                return String(format: NSLocalizedString("Time_Days_Hours", comment: ""), 
                            components.days, components.hours)
            } else {
                return String(format: NSLocalizedString("Time_Days", comment: ""), 
                            components.days)
            }
        } else if components.hours > 0 {
            if components.minutes > 0 {
                return String(format: NSLocalizedString("Time_Hours_Minutes", comment: ""), 
                            components.hours, components.minutes)
            } else {
                return String(format: NSLocalizedString("Time_Hours", comment: ""), 
                            components.hours)
            }
        } else {
            return String(format: NSLocalizedString("Time_Minutes", comment: ""), 
                        components.minutes)
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
}
