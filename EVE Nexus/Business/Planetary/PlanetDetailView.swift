import SwiftUI

struct PlanetDetailView: View {
    let characterId: Int
    let planetId: Int
    @State private var planetDetail: PlanetaryDetail?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var typeNames: [Int: String] = [:]
    @State private var typeIcons: [Int: String] = [:]
    @State private var typeGroupIds: [Int: Int] = [:]  // 存储type_id到group_id的映射
    @State private var typeVolumes: [Int: Double] = [:] // 存储type_id到体积的映射
    @State private var schematicDetails: [Int: (outputTypeId: Int, cycleTime: Int, outputValue: Int, inputs: [(typeId: Int, value: Int)])] = [:]
    
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
            } else if let detail = planetDetail {
                List {
                    ForEach(detail.pins, id: \.pinId) { pin in
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
                                                Text(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))
                                                    .font(.headline)
                                                Text("(\(PlanetaryFacility(identifier: pin.pinId).name))")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            // 容量进度条
                                            if let capacity = storageCapacities[groupId] {
                                                let total = calculateTotalVolume(contents: pin.contents, volumes: typeVolumes)
                                                VStack(alignment: .leading, spacing: 2) {
                                                    ProgressView(value: total, total: capacity)
                                                        .progressViewStyle(.linear)
                                                        .frame(height: 6)
                                                        .tint(total > capacity ? .red : .blue)
                                                    
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
                                                        HStack {
                                                            Text("\(content.amount)")
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                            if let volume = typeVolumes[content.typeId] {
                                                                Text("(\(Int(Double(content.amount) * volume))m³)")
                                                                    .font(.caption)
                                                                    .foregroundColor(.secondary)
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
                                                Text(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))
                                                    .font(.headline)
                                                Text("(\(PlanetaryFacility(identifier: pin.pinId).name))")
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            // 加工进度
                                            if let schematicId = pin.schematicId,
                                               let schematic = schematicDetails[schematicId] {
                                                if let lastCycleStart = pin.lastCycleStart {
                                                    let startDate = ISO8601DateFormatter().date(from: lastCycleStart) ?? Date()
                                                    let cycleEndDate = startDate.addingTimeInterval(TimeInterval(schematic.cycleTime))
                                                    let progress = 1.0 - Date().timeIntervalSince(startDate) / TimeInterval(schematic.cycleTime)
                                                    
                                                    if progress > 0 && progress <= 1 {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            ProgressView(value: progress)
                                                                .progressViewStyle(.linear)
                                                                .frame(height: 6)
                                                                .tint(.blue)
                                                            Text(cycleEndDate, style: .relative)
                                                                .font(.caption)
                                                                .foregroundColor(.secondary)
                                                        }
                                                    } else {
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            ProgressView(value: 0)
                                                                .progressViewStyle(.linear)
                                                                .frame(height: 6)
                                                                .tint(.gray)
                                                            Text("已停止")
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
                                                        Text("未启动")
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
                                                    Text("无配方")
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
                                                            Text("输入: ")
                                                                .foregroundColor(.secondary)
                                                            Text(typeNames[input.typeId] ?? "")
                                                                .font(.subheadline)
                                                        }
                                                        
                                                        // 显示当前存储量与需求量的比例
                                                        let currentAmount = pin.contents?.first(where: { $0.typeId == input.typeId })?.amount ?? 0
                                                        Text("库存: \(currentAmount)/\(input.value)")
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
                                                if let iconName = typeIcons[schematic.outputTypeId] {
                                                    Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                                        .resizable()
                                                        .frame(width: 32, height: 32)
                                                        .cornerRadius(4)
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    HStack {
                                                        Text("输出: ")
                                                            .foregroundColor(.secondary)
                                                        Text(typeNames[schematic.outputTypeId] ?? "")
                                                            .font(.subheadline)
                                                        Spacer()
                                                        Text("× \(schematic.outputValue)")
                                                            .font(.subheadline)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    // 显示当前存储的输出物品数量
                                                    if let currentAmount = pin.contents?.first(where: { $0.typeId == schematic.outputTypeId })?.amount {
                                                        Text("库存: \(currentAmount)")
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
                                            ExtractorYieldChartView(extractor: extractor, 
                                                                  installTime: installTime,
                                                                  expiryTime: pin.expiryTime)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    await loadPlanetDetail(forceRefresh: true)
                }
            } else {
                Text(NSLocalizedString("Planet_Detail_No_Data", comment: ""))
            }
            
            if isLoading && planetDetail == nil {
                ProgressView()
            }
        }
        .navigationTitle(NSLocalizedString("Planet_Detail_Title", comment: ""))
        .onAppear {
            Task {
                await loadPlanetDetail()
            }
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
}

// MARK: - 子视图
struct PinView: View {
    let pin: PlanetaryPin
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    let typeGroupIds: [Int: Int]
    let typeVolumes: [Int: Double]
    
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
                    Text(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))
                        .font(.headline)
                    Text("(\(PlanetaryFacility(identifier: pin.pinId).name))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // 采集器采集物名称
                if let extractor = pin.extractorDetails,
                   let productTypeId = extractor.productTypeId,
                   let productName = typeNames[productTypeId] {
                    HStack(spacing: 4) {
                        if let iconName = typeIcons[productTypeId] {
                            Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                .resizable()
                                .frame(width: 20, height: 20)
                                .cornerRadius(4)
                        }
                        Text(productName)
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
                                    Text(typeNames[content.typeId] ?? "")
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
