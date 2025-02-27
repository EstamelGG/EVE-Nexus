import SwiftUI

struct PlanetDetailView: View {
    let characterId: Int
    let planetId: Int
    let planetName: String
    @State private var planetDetail: PlanetaryDetail?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var typeNames: [Int: String] = [:]
    @State private var typeIcons: [Int: String] = [:]
    @State private var typeGroupIds: [Int: Int] = [:]  // 存储type_id到group_id的映射
    @State private var typeVolumes: [Int: Double] = [:] // 存储type_id到体积的映射
    @State private var schematicDetails: [Int: (outputTypeId: Int, cycleTime: Int, outputValue: Int, inputs: [(typeId: Int, value: Int)])] = [:]
    @State private var simulatedColony: Colony? // 添加模拟结果状态
    @State private var currentTime = Date()
    @State private var lastCycleCheck: Int = -1
    @State private var hasInitialized = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private let storageCapacities: [Int: Double] = [
        1027: 500.0,    // 500m3
        1030: 10000.0,  // 10000m3
        1029: 12000.0   // 12000m3
    ]
    
    var body: some View {
        ZStack {
            if let error = error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else if let detail = planetDetail, !isLoading {
                List {
                    // 对设施进行排序
                    let sortedPins = detail.pins.sorted { pin1, pin2 in
                        let group1 = typeGroupIds[pin1.typeId] ?? 0
                        let group2 = typeGroupIds[pin2.typeId] ?? 0
                        
                        // 定义组的优先级
                        func getPriority(_ groupId: Int) -> Int {
                            switch groupId {
                            case 1027, 1029, 1030: return 0  // 仓库类（指挥中心、存储设施、发射台）优先级最高
                            case 1063: return 1  // 采集器次之
                            case 1028: return 2  // 工厂优先级最低
                            default: return 3
                            }
                        }
                        
                        let priority1 = getPriority(group1)
                        let priority2 = getPriority(group2)
                        
                        return priority1 < priority2
                    }
                    
                    ForEach(sortedPins, id: \.pinId) { pin in
                        if let groupId = typeGroupIds[pin.typeId] {
                            if storageCapacities.keys.contains(groupId) {
                                // 存储设施的显示方式
                                Section {
                                    // 设施名称和图标
                                    HStack(alignment: .center, spacing: 12) {
                                        if let iconName = typeIcons[pin.typeId] {
                                            Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                                .resizable()
                                                .frame(width: 40, height: 40)
                                                .cornerRadius(6)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text("[\(PlanetaryFacility(identifier: pin.pinId).name)] \(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))")
                                                    .lineLimit(1)
                                            }
                                            
                                            // 容量进度条
                                            if let capacity = storageCapacities[groupId] {
                                                let total = calculateStorageVolume(for: pin)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    ProgressView(value: total, total: capacity)
                                                        .progressViewStyle(.linear)
                                                        .frame(height: 6)
                                                        .tint(capacity > 0 ? (total / capacity >= 0.9 ? .red : .blue) : .blue) // 容量快满时标红提示
                                                    
                                                    Text("\(Int(total.rounded()))m³ / \(Int(capacity))m³")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    
                                    // 存储的内容物，每个内容物单独一行
                                    if let contents = pin.contents {
                                        ForEach(contents, id: \.typeId) { content in
                                            if let simPin = simulatedColony?.pins.first(where: { $0.id == pin.pinId }),
                                               let simAmount = simPin.contents.first(where: { $0.key.id == content.typeId })?.value,
                                               simAmount > 0 {
                                                NavigationLink(destination: ShowPlanetaryInfo(itemID: content.typeId, databaseManager: DatabaseManager.shared)) {
                                                    HStack(alignment: .center, spacing: 12) {
                                                        if let iconName = typeIcons[content.typeId] {
                                                            Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                                                .resizable()
                                                                .frame(width: 32, height: 32)
                                                                .cornerRadius(4)
                                                        }
                                                        
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(typeNames[content.typeId] ?? "")
                                                                .font(.subheadline)
                                                            HStack {
                                                                Text("\(simAmount)")
                                                                    .font(.caption)
                                                                    .foregroundColor(.secondary)
                                                                if let volume = typeVolumes[content.typeId] {
                                                                    Text("(\(Int(Double(simAmount) * volume))m³)")
                                                                        .font(.caption)
                                                                        .foregroundColor(.secondary)
                                                                }
                                                            }
                                                        }
                                                        Spacer()
                                                    }
                                                }
                                            }
                                        }
                                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                                    }
                                }
                            } else if groupId == 1028 {
                                // 加工设施
                                Section {
                                    // 设施名称和图标
                                    HStack(alignment: .center, spacing: 12) {
                                        if let iconName = typeIcons[pin.typeId] {
                                            Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                                .resizable()
                                                .frame(width: 40, height: 40)
                                                .cornerRadius(6)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            // 设施名称
                                            HStack {
                                                Text("[\(PlanetaryFacility(identifier: pin.pinId).name)] \(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))")
                                                    .lineLimit(1)
                                            }
                                            
                                            // 加工进度
                                            if let schematicId = pin.schematicId,
                                               let schematic = schematicDetails[schematicId],
                                               let simPin = simulatedColony?.pins.first(where: { $0.id == pin.pinId }) as? Pin.Factory {
                                                if let lastRunTime = simPin.lastRunTime {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        if let lastCycleStartTime = simPin.lastCycleStartTime, simPin.isActive {
                                                            // 如果有lastCycleStartTime且isActive为true，说明工厂正在生产周期中
                                                            let cycleEndTime = lastCycleStartTime.addingTimeInterval(TimeInterval(schematic.cycleTime))
                                                            let progress = calculateProgress(lastRunTime: lastRunTime, cycleTime: TimeInterval(schematic.cycleTime), hasEnoughInput: true)
                                                            
                                                            ProgressView(value: progress)
                                                                .progressViewStyle(.linear)
                                                                .frame(height: 6)
                                                                .tint(Color(red: 0.8, green: 0.6, blue: 0.0)) // 深黄色
                                                            HStack{
                                                                Text(NSLocalizedString("Factory_Processing", comment: ""))
                                                                    .font(.caption)
                                                                    .foregroundColor(.green)
                                                                Text("·")
                                                                    .font(.caption)
                                                                    .foregroundColor(.secondary)
                                                                Text(cycleEndTime, style: .relative)
                                                                    .font(.caption)
                                                                    .foregroundColor(.secondary)
                                                            }
                                                        } else {
                                                            // 没有lastCycleStartTime或isActive为false，工厂不在生产周期中
                                                            ProgressView(value: 0)
                                                                .progressViewStyle(.linear)
                                                                .frame(height: 6)
                                                                .tint(.gray)
                                                            Text(simPin.isActive ? NSLocalizedString("Factory_Waiting_Materials", comment: "") : NSLocalizedString("Factory_Stopped", comment: ""))
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                        }
                                                    }
                                                } else {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        ProgressView(value: 0)
                                                            .progressViewStyle(.linear)
                                                            .frame(height: 6)
                                                            .tint(.gray)
                                                        Text(NSLocalizedString("Factory_No_Recipe", comment: ""))
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            } else {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    ProgressView(value: 0)
                                                        .progressViewStyle(.linear)
                                                        .frame(height: 6)
                                                        .tint(.gray)
                                                    Text(NSLocalizedString("Factory_No_Recipe", comment: ""))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }
                                    
                                    // 输入和输出物品
                                    if let schematicId = pin.schematicId,
                                       let schematic = schematicDetails[schematicId] {
                                        // 输入物品
                                        ForEach(schematic.inputs, id: \.typeId) { input in
                                            NavigationLink(destination: ShowPlanetaryInfo(itemID: input.typeId, databaseManager: DatabaseManager.shared)) {
                                                HStack(alignment: .center, spacing: 12) {
                                                    if let iconName = typeIcons[input.typeId] {
                                                        Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                                            .resizable()
                                                            .frame(width: 32, height: 32)
                                                            .cornerRadius(4)
                                                    }
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack {
                                                            Text(NSLocalizedString("Factory_Input", comment: "") + " \(typeNames[input.typeId] ?? "")")
                                                        }
                                                        
                                                        // 显示当前存储量与需求量的比例
                                                        if let simPin = simulatedColony?.pins.first(where: { $0.id == pin.pinId }) {
                                                            let currentAmount = simPin.contents.first(where: { $0.key.id == input.typeId })?.value ?? 0
                                                            Text(NSLocalizedString("Factory_Inventory", comment: "") + " \(currentAmount)/\(input.value)")
                                                                .font(.caption)
                                                                .foregroundColor(currentAmount >= input.value ? .secondary : .red)
                                                        } else {
                                                            let currentAmount = pin.contents?.first(where: { $0.typeId == input.typeId })?.amount ?? 0
                                                            Text(NSLocalizedString("Factory_Inventory", comment: "") + " \(currentAmount)/\(input.value)")
                                                                .font(.caption)
                                                                .foregroundColor(currentAmount >= input.value ? .secondary : .red)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                                        
                                        // 输出物品
                                        NavigationLink(destination: ShowPlanetaryInfo(itemID: schematic.outputTypeId, databaseManager: DatabaseManager.shared)) {
                                            HStack(alignment: .center, spacing: 12) {
                                                if let iconName = typeIcons[schematic.outputTypeId] {
                                                    Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                                        .resizable()
                                                        .frame(width: 32, height: 32)
                                                        .cornerRadius(4)
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack {
                                                        Text(NSLocalizedString("Factory_Output", comment: "") + " \(typeNames[schematic.outputTypeId] ?? "")")
                                                        Spacer()
                                                        Text("× \(schematic.outputValue)")
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                                    }
                                }
                            } else if let extractor = pin.extractorDetails {
                                // 提取器设施
                            Section {
                                VStack(alignment: .leading, spacing: 0) {
                                    // 提取器基本信息
                                    HStack(alignment: .top, spacing: 12) {
                                        if let iconName = typeIcons[pin.typeId] {
                                            Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                                .resizable()
                                                .frame(width: 40, height: 40)
                                                .cornerRadius(6)
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            // 设施名称
                                            Text("[\(PlanetaryFacility(identifier: pin.pinId).name)] \(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))")
                                                .lineLimit(1)

                                            // 采集物名称
                                            if let productTypeId = extractor.productTypeId {
                                                HStack(spacing: 4) {
                                                    if let iconName = typeIcons[productTypeId] {
                                                        Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                                            .resizable()
                                                            .frame(width: 20, height: 20)
                                                            .cornerRadius(4)
                                                    }
                                                    Text(typeNames[productTypeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                    }

                                    // 提取器产量图表
                                    if let installTime = pin.installTime {
                                        ExtractorYieldChartView(
                                            extractor: extractor,
                                            installTime: installTime,
                                            expiryTime: pin.expiryTime,
                                            currentTime: currentTime
                                        )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                 .listStyle(.insetGrouped)
            } else if isLoading {
                ProgressView()
            } else {
                Text(NSLocalizedString("Planet_Detail_No_Data", comment: ""))
            }
            
            if isLoading && planetDetail == nil {
                ProgressView()
            }
        }
        .navigationTitle(planetName)
        .task {
            if !hasInitialized {
                await loadPlanetDetail()
                hasInitialized = true
            }
        }
        .refreshable {
            await loadPlanetDetail(forceRefresh: true)
        }
        .onReceive(timer) { newTime in
            let shouldUpdate = shouldUpdateView(newTime: newTime)
            if shouldUpdate {
                currentTime = newTime
            }
        }
    }
    
    private func shouldUpdateView(newTime: Date) -> Bool {
        guard let detail = planetDetail else { return false }
        
        // 检查是否有任何提取器需要更新
        for pin in detail.pins {
            if let extractor = pin.extractorDetails,
               let installTime = pin.installTime,
               let cycleTime = extractor.cycleTime,
               let expiryTime = pin.expiryTime {
                let currentCycle = ExtractorYieldCalculator.getCurrentCycle(
                    installTime: installTime,
                    expiryTime: expiryTime,
                    cycleTime: cycleTime
                )
                
                // 如果周期发生变化，需要更新视图
                if currentCycle != lastCycleCheck {
                    lastCycleCheck = currentCycle
                    return true
                }
            }
        }
        
        // 如果没有周期变化，只在整秒时更新（用于更新倒计时显示）
        return floor(newTime.timeIntervalSince1970) != floor(currentTime.timeIntervalSince1970)
    }
    
    private func loadPlanetDetail(forceRefresh: Bool = false) async {
        let task = Task { @MainActor in
        isLoading = true
        error = nil
        
        do {
                // 获取行星基本信息
                let planetaryInfo = try await CharacterPlanetaryAPI.fetchCharacterPlanetary(characterId: characterId)
                let currentPlanetInfo = planetaryInfo.first { $0.planetId == planetId }
            
            // 获取行星详情
            planetDetail = try await CharacterPlanetaryAPI.fetchPlanetaryDetail(
                characterId: characterId,
                planetId: planetId,
                forceRefresh: forceRefresh
            )
            
                // 进行殖民地模拟并保存结果
                if let detail = planetDetail, let info = currentPlanetInfo {
                    // 将PlanetaryDetail转换为Colony模型
                    let colony = PlanetaryConverter.convertToColony(
                        detail: detail,
                        characterId: characterId,
                        planetId: planetId,
                        planetName: planetName,
                        planetType: info.planetType,
                        systemId: info.solarSystemId,
                        systemName: getSystemName(systemId: info.solarSystemId),
                        upgradeLevel: info.upgradeLevel,
                        lastUpdate: info.lastUpdate
                    )
                    
                    // 使用ColonySimulationManager执行模拟
                    simulatedColony = ColonySimulationManager.shared.simulateColony(
                        colony: colony,
                        targetTime: Date()
                        // targetTime: Date().addingTimeInterval(2.2 * 60 * 60)
                    )
            }
            
            var typeIds = Set<Int>()
                var contentTypeIds = Set<Int>()
                var schematicIds = Set<Int>()
            
            planetDetail?.pins.forEach { pin in
                typeIds.insert(pin.typeId)
                if let productTypeId = pin.extractorDetails?.productTypeId {
                    typeIds.insert(productTypeId)
                }
                    if let schematicId = pin.schematicId {
                        schematicIds.insert(schematicId)
                    }
                    pin.contents?.forEach { content in
                        typeIds.insert(content.typeId)
                        contentTypeIds.insert(content.typeId)
                    }
            }
            
            if !typeIds.isEmpty {
                let typeIdsString = typeIds.map { String($0) }.joined(separator: ",")
                let query = """
                        SELECT type_id, name, icon_filename, groupID, volume
                    FROM types 
                    WHERE type_id IN (\(typeIdsString))
                """
                
                if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let name = row["name"] as? String {
                            typeNames[typeId] = name
                            if let iconFilename = row["icon_filename"] as? String {
                                typeIcons[typeId] = iconFilename
                                }
                                if let groupId = row["groupID"] as? Int {
                                    typeGroupIds[typeId] = groupId
                                }
                                if let volume = row["volume"] as? Double {
                                    typeVolumes[typeId] = volume
                                }
                            }
                        }
                    }
                }
                
                if !schematicIds.isEmpty {
                    let schematicIdsString = schematicIds.map { String($0) }.joined(separator: ",")
                    let schematicQuery = """
                        SELECT schematic_id, output_typeid, cycle_time, output_value, input_typeid, input_value
                        FROM planetSchematics
                        WHERE schematic_id IN (\(schematicIdsString))
                    """
                    
                    if case .success(let rows) = DatabaseManager.shared.executeQuery(schematicQuery) {
                        for row in rows {
                            if let schematicId = row["schematic_id"] as? Int,
                               let outputTypeId = row["output_typeid"] as? Int,
                               let cycleTime = row["cycle_time"] as? Int,
                               let outputValue = row["output_value"] as? Int,
                               let inputTypeIds = row["input_typeid"] as? String,
                               let inputValues = row["input_value"] as? String {
                                
                                let inputTypeIdArray = inputTypeIds.split(separator: ",").compactMap { Int($0) }
                                let inputValueArray = inputValues.split(separator: ",").compactMap { Int($0) }
                                
                                let inputs = zip(inputTypeIdArray, inputValueArray).map { (typeId: $0, value: $1) }
                                
                                schematicDetails[schematicId] = (
                                    outputTypeId: outputTypeId,
                                    cycleTime: cycleTime,
                                    outputValue: outputValue,
                                    inputs: inputs
                                )
                        }
                    }
                }
            }
            
        } catch {
                if (error as? CancellationError) == nil {
                self.error = error
                }
            }
            
            isLoading = false
        }
        
        await task.value
    }
    
    private func calculateTotalVolume(contents: [PlanetaryContent]?, volumes: [Int: Double]) -> Double {
        guard let contents = contents else { return 0 }
        return contents.reduce(0) { sum, content in
            sum + (Double(content.amount) * (volumes[content.typeId] ?? 0))
        }
    }
    
    private func calculateStorageVolume(for pin: PlanetaryPin) -> Double {
        if let simPin = simulatedColony?.pins.first(where: { $0.id == pin.pinId }) {
            let simContents = simPin.contents.map { 
                PlanetaryContent(amount: $0.value, typeId: $0.key.id)
            }
            return calculateTotalVolume(contents: simContents, volumes: typeVolumes)
        }
        return calculateTotalVolume(contents: pin.contents, volumes: typeVolumes)
    }
    
    private func calculateProgress(lastRunTime: Date, cycleTime: TimeInterval, hasEnoughInput: Bool = true) -> Double {
        if !hasEnoughInput {
            return 0
        }
        let elapsedTime = currentTime.timeIntervalSince(lastRunTime)
        let progress = elapsedTime / cycleTime
        return min(max(progress, 0), 1)
    }
    
    private func getTypeName(for typeId: Int) -> String {
        let query = "SELECT name FROM types WHERE type_id = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result, let row = rows.first {
            return row["name"] as? String ?? "Null"
        }
        return "Null"
    }
    
    /// 获取恒星系名称
    /// - Parameter systemId: 恒星系ID
    /// - Returns: 恒星系名称
    private func getSystemName(systemId: Int) -> String {
        let query = "SELECT solarSystemName FROM solarsystems WHERE solarSystemID = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [systemId])
        
        if case .success(let rows) = result, let row = rows.first {
            return row["solarSystemName"] as? String ?? "Unknown System"
        }
        return "Unknown System"
    }
} 
