import SwiftUI

struct PlanetDetailView: View {
    let characterId: Int
    let planetId: Int
    let planetName: String
    let lastUpdate: String  // 添加lastUpdate参数
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
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var hasInitialized = false  // 添加初始化标记
    
    private let storageCapacities: [Int: Double] = [
        1027: 500.0,    // 500m3
        1030: 10000.0,  // 10000m3
        1029: 12000.0   // 12000m3
    ]
    
    private func getTypeName(for typeId: Int) -> String {
        let query = "SELECT groupID, volume, capacity, name, icon_filename FROM types WHERE type_id = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result, let row = rows.first {
            return row["name"] as? String ?? "Null"
        }
        return "Null"
    }
    
    private func getTypeIcon(for typeId: Int) -> String {
        let query = "SELECT groupID, volume, capacity, name, icon_filename FROM types WHERE type_id = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result, let row = rows.first {
            return row["icon_filename"] as? String ?? "icon_0_64.png"
        }
        return "icon_0_64.png"
    }
    
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
                                                        if let simPin = simulatedColony?.pins.first(where: { $0.id == pin.pinId }),
                                                           let simAmount = simPin.contents.first(where: { $0.key.id == content.typeId })?.value {
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
                                                    }
                                                    Spacer()
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
                                               let simPin = simulatedColony?.pins.first(where: { $0.id == pin.pinId }) as? FactoryPin {
                                                if let lastRunTime = simPin.lastRunTime {
                                                    let cycleEndTime = lastRunTime.addingTimeInterval(TimeInterval(schematic.cycleTime))
                                                    let hasEnoughInput = schematic.inputs.allSatisfy { input in
                                                        let currentAmount = pin.contents?.first(where: { $0.typeId == input.typeId })?.amount ?? 0
                                                        return currentAmount >= input.value
                                                    }
                                                    let progress = calculateProgress(lastRunTime: lastRunTime, cycleTime: TimeInterval(schematic.cycleTime), hasEnoughInput: hasEnoughInput)
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        if simPin.isActive && progress > 0 && progress <= 1 {
                                                            ProgressView(value: progress)
                                                                .progressViewStyle(.linear)
                                                                .frame(height: 6)
                                                                .tint(Color(red: 0.8, green: 0.6, blue: 0.0)) // 深黄色
                                                            HStack {
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
                                                        Text(NSLocalizedString("Factory_Not_Started", comment: ""))
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
                                                    Image(uiImage: IconManager.shared.loadUIImage(for: getTypeIcon(for: input.typeId)))
                                                        .resizable()
                                                        .frame(width: 32, height: 32)
                                                        .cornerRadius(4)
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack {
                                                            Text(NSLocalizedString("Factory_Input", comment: "") + " \(getTypeName(for: input.typeId))")
                                                        }
                                                        
                                                        // 显示当前存储量与需求量的比例
                                                        let currentAmount = pin.contents?.first(where: { $0.typeId == input.typeId })?.amount ?? 0
                                                        Text(NSLocalizedString("Factory_Inventory", comment: "") + " \(currentAmount)/\(input.value)")
                                                            .font(.caption)
                                                            .foregroundColor(currentAmount >= input.value ? .secondary : .red)
                                                    }
                                                }
                                            }
                                        }
                                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                                        
                                        // 输出物品
                                        NavigationLink(destination: ShowPlanetaryInfo(itemID: schematic.outputTypeId, databaseManager: DatabaseManager.shared)) {
                                            HStack(alignment: .center, spacing: 12) {
                                                Image(uiImage: IconManager.shared.loadUIImage(for: getTypeIcon(for: schematic.outputTypeId)))
                                                    .resizable()
                                                    .frame(width: 32, height: 32)
                                                    .cornerRadius(4)
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack {
                                                        Text(NSLocalizedString("Factory_Output", comment: "") + " \(getTypeName(for: schematic.outputTypeId))")
                                                        Spacer()
                                                        Text("× \(schematic.outputValue)")
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    // 显示当前存储的输出物品数量
                                                    if let currentAmount = pin.contents?.first(where: { $0.typeId == schematic.outputTypeId })?.amount {
                                                        Text(NSLocalizedString("Factory_Inventory", comment: "") + " \(currentAmount)")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                            }
                                        }
                                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                                    }
                                }
                            } else {
                                // 非存储和非加工设施使用原有的PinView
                                Section {
                                    VStack(spacing: 0) {
                                        PinView(pin: pin, typeNames: typeNames, typeIcons: typeIcons, typeGroupIds: typeGroupIds, typeVolumes: typeVolumes)
                                        
                                        if let extractor = pin.extractorDetails,
                                           let installTime = pin.installTime {
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
            // 只在第一次加载时初始化数据
            if !hasInitialized {
                await loadPlanetDetail()
                hasInitialized = true
            }
        }
        .refreshable {
            await loadPlanetDetail(forceRefresh: true)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    private func loadPlanetDetail(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        
        do {
            planetDetail = try await CharacterPlanetaryAPI.fetchPlanetaryDetail(
                characterId: characterId,
                planetId: planetId,
                forceRefresh: forceRefresh
            )
            
            // 进行殖民地模拟并保存结果，使用lastUpdate作为起始时间
            if let detail = planetDetail {
                simulatedColony = PlanetaryManager.shared.simulateColony(
                    characterId: characterId,
                    planetId: planetId,
                    esiResponse: detail,
                    startTime: lastUpdate  // 使用传入的 lastUpdate 参数
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
                    SELECT type_id, name, icon_filename, groupID
                    FROM types 
                    WHERE type_id IN (\(typeIdsString))
                """
                
                if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let name = row["name"] as? String,
                           let groupId = row["groupID"] as? Int {
                            typeNames[typeId] = name
                            typeGroupIds[typeId] = groupId
                            if let iconFilename = row["icon_filename"] as? String {
                                typeIcons[typeId] = iconFilename
                            }
                        }
                    }
                }
            }
            
            if !contentTypeIds.isEmpty {
                let contentTypeIdsString = contentTypeIds.map { String($0) }.joined(separator: ",")
                let volumeQuery = """
                    SELECT type_id, volume
                    FROM types
                    WHERE type_id IN (\(contentTypeIdsString))
                """
                
                if case .success(let rows) = DatabaseManager.shared.executeQuery(volumeQuery) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let volume = row["volume"] as? Double {
                            typeVolumes[typeId] = volume
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
}

// MARK: - 子视图
struct PinView: View {
    let pin: PlanetaryPin
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    let typeGroupIds: [Int: Int]
    let typeVolumes: [Int: Double]
    
    private func getTypeName(for typeId: Int) -> String {
        let query = "SELECT groupID, volume, capacity, name, icon_filename FROM types WHERE type_id = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result, let row = rows.first {
            return row["name"] as? String ?? "Null"
        }
        return "Null"
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // 图标
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
                
                // 采集器采集物名称
                if let extractor = pin.extractorDetails,
                   let productTypeId = extractor.productTypeId {
                    HStack(spacing: 4) {
                        if let iconName = typeIcons[productTypeId] {
                            Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                .resizable()
                                .frame(width: 20, height: 20)
                                .cornerRadius(4)
                        }
                        Text(getTypeName(for: productTypeId))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 工厂信息
                if let factory = pin.factoryDetails {
                    Text(NSLocalizedString("Planet_Detail_Schematic_ID", comment: "") + ": \(factory.schematicId)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // 内容显示
                if let contents = pin.contents, !contents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(contents, id: \.typeId) { content in
                            NavigationLink(destination: ShowPlanetaryInfo(itemID: content.typeId, databaseManager: DatabaseManager.shared)) {
                                HStack {
                                    if let iconName = typeIcons[content.typeId] {
                                        Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .cornerRadius(4)
                                    }
                                    Text(getTypeName(for: content.typeId))
                                    Spacer()
                                    Text("\(content.amount)")
                                }
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
} 
