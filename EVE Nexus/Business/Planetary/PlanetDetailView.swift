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
    @State private var typeVolumes: [Int: Double] = [:]  // 存储type_id到体积的映射
    @State private var schematicDetails: [Int: SchematicInfo] = [:]
    @State private var simulatedColony: Colony?  // 添加模拟结果状态
    @State private var currentTime = Date()
    @State private var lastCycleCheck: Int = -1
    @State private var hasInitialized = false
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let storageCapacities: [Int: Double] = [
        1027: 500.0,  // 500m3
        1030: 10000.0,  // 10000m3
        1029: 12000.0,  // 12000m3
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
                            case 1027: return 0  // 指挥中心优先级最高
                            case 1029, 1030: return 1  // 仓库类（存储设施、发射台）优先级最高
                            case 1063: return 2  // 采集器次之
                            case 1028: return 3  // 工厂优先级最低
                            default: return 999
                            }
                        }

                        let priority1 = getPriority(group1)
                        let priority2 = getPriority(group2)

                        return priority1 < priority2
                    }

                    ForEach(sortedPins, id: \.pinId) { pin in
                        if let groupId = typeGroupIds[pin.typeId] {
                            // 提前获取匹配的模拟Pin
                            let matchedPin = simulatedColony?.pins.first(where: {
                                $0.id == pin.pinId
                            })

                            if storageCapacities.keys.contains(groupId) {
                                // 存储设施的显示方式
                                Section {
                                    StorageFacilityView(
                                        pin: pin,
                                        simulatedPin: matchedPin,
                                        typeNames: typeNames,
                                        typeIcons: typeIcons,
                                        typeVolumes: typeVolumes,
                                        capacity: storageCapacities[groupId] ?? 0
                                    )
                                } footer: {
                                    if groupId == 1027,
                                        let lastUpdateTime = simulatedColony?.checkpointSimTime
                                    {
                                        Text(
                                            "\(NSLocalizedString("Planet_Detail_Last_Update", comment: "")): \(formatDate(lastUpdateTime))"
                                        )
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                }
                            } else if groupId == 1028 {
                                // 加工设施
                                Section {
                                    FactoryFacilityView(
                                        pin: pin,
                                        simulatedPin: simulatedColony?.pins.first(where: {
                                            $0.id == pin.pinId
                                        }) as? Pin.Factory,
                                        typeNames: typeNames,
                                        typeIcons: typeIcons,
                                        schematic: pin.schematicId != nil
                                            ? schematicDetails[pin.schematicId!] : nil,
                                        currentTime: currentTime
                                    )
                                }
                            } else if let extractor = pin.extractorDetails {
                                // 提取器设施
                                Section {
                                    ExtractorFacilityView(
                                        pin: pin,
                                        extractor: extractor,
                                        typeNames: typeNames,
                                        typeIcons: typeIcons,
                                        currentTime: currentTime
                                    )
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
                // 立即更新当前时间，避免显示缓存的旧时间
                currentTime = Date()
                await loadPlanetDetail()
                hasInitialized = true
            }
        }
        .refreshable {
            // 立即更新当前时间，避免显示缓存的旧时间
            currentTime = Date()
            await loadPlanetDetail(forceRefresh: true)
        }
        .onReceive(timer) { newTime in
            let shouldUpdate = shouldUpdateView(newTime: newTime)
            if shouldUpdate {
                currentTime = newTime
            }
        }
        .onAppear {
            // 视图出现时立即更新当前时间
            currentTime = Date()
        }
    }

    // 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")  // 使用POSIX locale确保24小时制
        return formatter.string(from: date)
    }

    private func shouldUpdateView(newTime: Date) -> Bool {
        guard let detail = planetDetail else { return false }

        // 检查是否有任何提取器需要更新
        for pin in detail.pins {
            if let extractor = pin.extractorDetails,
                let installTime = pin.installTime,
                let cycleTime = extractor.cycleTime,
                let expiryTime = pin.expiryTime
            {
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
                let planetaryInfo = try await CharacterPlanetaryAPI.fetchCharacterPlanetary(
                    characterId: characterId, forceRefresh: forceRefresh
                )
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
                    let typeIdsString = typeIds.sorted().map { String($0) }.joined(separator: ",")
                    let query = """
                            SELECT type_id, name, icon_filename, groupID, volume
                            FROM types 
                            WHERE type_id IN (\(typeIdsString))
                        """

                    if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                        for row in rows {
                            if let typeId = row["type_id"] as? Int,
                                let name = row["name"] as? String
                            {
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
                    let schematicIdsString = schematicIds.sorted().map { String($0) }.joined(
                        separator: ",")
                    let schematicQuery = """
                            SELECT schematic_id, output_typeid, cycle_time, output_value, input_typeid, input_value
                            FROM planetSchematics
                            WHERE schematic_id IN (\(schematicIdsString))
                        """

                    if case let .success(rows) = DatabaseManager.shared.executeQuery(schematicQuery)
                    {
                        for row in rows {
                            if let schematicId = row["schematic_id"] as? Int,
                                let outputTypeId = row["output_typeid"] as? Int,
                                let cycleTime = row["cycle_time"] as? Int,
                                let outputValue = row["output_value"] as? Int,
                                let inputTypeIds = row["input_typeid"] as? String,
                                let inputValues = row["input_value"] as? String
                            {
                                // 将配方的输出类型ID添加到typeIds集合中
                                typeIds.insert(outputTypeId)

                                let inputTypeIdArray = inputTypeIds.split(separator: ",").compactMap
                                { Int($0) }
                                let inputValueArray = inputValues.split(separator: ",").compactMap {
                                    Int($0)
                                }

                                // 将配方的输入类型ID也添加到typeIds集合中
                                inputTypeIdArray.forEach { typeIds.insert($0) }

                                let inputs = zip(inputTypeIdArray, inputValueArray).map {
                                    (typeId: $0, value: $1)
                                }

                                schematicDetails[schematicId] = SchematicInfo(
                                    outputTypeId: outputTypeId,
                                    cycleTime: cycleTime,
                                    outputValue: outputValue,
                                    inputs: inputs
                                )
                            }
                        }
                    }

                    // 如果有新的类型ID被添加，重新查询类型信息
                    if !typeIds.isEmpty {
                        let typeIdsString = typeIds.sorted().map { String($0) }.joined(
                            separator: ",")
                        let query = """
                                SELECT type_id, name, icon_filename, groupID, volume
                                FROM types 
                                WHERE type_id IN (\(typeIdsString))
                            """

                        if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
                            for row in rows {
                                if let typeId = row["type_id"] as? Int,
                                    let name = row["name"] as? String
                                {
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
                }

                // 数据加载完成后，更新当前时间以确保显示最新的倒计时
                currentTime = Date()

            } catch {
                if (error as? CancellationError) == nil {
                    self.error = error
                }
            }

            isLoading = false
        }

        await task.value
    }

    /// 获取恒星系名称
    /// - Parameter systemId: 恒星系ID
    /// - Returns: 恒星系名称
    private func getSystemName(systemId: Int) -> String {
        let query = "SELECT solarSystemName FROM solarsystems WHERE solarSystemID = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [systemId])

        if case let .success(rows) = result, let row = rows.first {
            return row["solarSystemName"] as? String ?? "Unknown System"
        }
        return "Unknown System"
    }
}
