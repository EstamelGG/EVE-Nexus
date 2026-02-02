import SwiftUI

/// 工厂设施视图
struct FactoryFacilityView: View {
    let pin: PlanetaryPin
    let simulatedPin: Pin.Factory?
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    let typeGroupIds: [Int: Int]
    let typeEnNames: [Int: String]
    let schematic: SchematicInfo?
    let currentTime: Date

    /// 获取工厂类型对应的进度条颜色
    private var factoryProgressColor: Color {
        let enName = typeEnNames[pin.typeId]
        let factoryType = FactoryTypeClassifier.classifyFactory(enName: enName)
        let isActive = simulatedPin?.isActive ?? false
        return FactoryTypeClassifier.getProgressColor(for: factoryType, isActive: isActive)
    }

    // 获取设施图标文件名
    // 优先级：1. 根据 groupID 和 en_name 映射的图标 2. typeid 对应的图标（兜底）
    private func getFacilityIconName() -> String? {
        // 尝试使用映射规则获取图标
        if let groupId = typeGroupIds[pin.typeId] {
            let enName = typeEnNames[pin.typeId]
            let mappedIconName = PlanetaryUtils.getFacilityIconName(groupId: groupId, enName: enName)
            // 如果映射返回了有效的图标名称，使用它
            if !mappedIconName.isEmpty {
                return mappedIconName
            }
        }
        // 兜底：使用 typeid 对应的图标
        return typeIcons[pin.typeId]
    }

    var body: some View {
        // 设施名称和图标
        HStack(alignment: .center, spacing: 12) {
            if let iconName = getFacilityIconName() {
                IconManager.shared.loadImage(for: iconName)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 6) {
                // 设施名称
                HStack {
                    Text(
                        typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: "")
                    )
                    .fontWeight(.semibold)
                    .lineLimit(1)
                }

                // 加工进度
                if schematic != nil,
                   let simPin = simulatedPin
                {
                    VStack(alignment: .leading, spacing: 2) {
                        if let schematicObj = simPin.schematic {
                            let progress = calculateFactoryProgress(
                                factory: simPin, currentTime: currentTime
                            )

                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(height: 6)
                                .tint(factoryProgressColor)

                            if simPin.isActive, let lastCycleStartTime = simPin.lastCycleStartTime {
                                let cycleEndTime = lastCycleStartTime.addingTimeInterval(
                                    schematicObj.cycleTime)
                                // 计算相对于模拟时间的时间差，而不是系统当前时间
                                let timeRemaining = cycleEndTime.timeIntervalSince(currentTime)
                                HStack {
                                    Text(NSLocalizedString("Factory_Processing", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.green)
                                    Text("·")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                    Text(formatTimeInterval(timeRemaining))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else if simPin.hasEnoughInputs() {
                                Text(NSLocalizedString("Factory_Ready", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(NSLocalizedString("Factory_Waiting_Materials", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            ProgressView(value: 0)
                                .progressViewStyle(.linear)
                                .frame(height: 6)
                                .tint(.gray)
                            Text(NSLocalizedString("Factory_No_Recipe", comment: ""))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
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
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
            }
        }

        // 输入和输出物品
        if let schematic = schematic {
            // 输入物品
            ForEach(Array(schematic.inputs.enumerated()), id: \.offset) { _, input in
                // 计算库存占比（在 ViewBuilder 外部计算）
                let currentAmount: Int = {
                    if let simPin = simulatedPin {
                        return Int(simPin.contents.first(where: { $0.key.id == input.typeId })?.value ?? 0)
                    } else {
                        return Int(pin.contents?.first(where: { $0.typeId == input.typeId })?.amount ?? 0)
                    }
                }()
                let requiredAmount = input.value
                let inventoryRatio = requiredAmount > 0 ? min(Double(currentAmount) / Double(requiredAmount), 1.0) : 0.0

                NavigationLink(
                    destination: ShowPlanetaryInfo(
                        itemID: input.typeId, databaseManager: DatabaseManager.shared
                    )
                ) {
                    HStack(alignment: .center, spacing: 12) {
                        // 图标容器，带背景颜色和库存占比显示
                        // 使用外层圆角作为蒙版，内部元素无需圆角
                        ZStack(alignment: .leading) {
                            // 深色底色
                            Rectangle()
                                .fill(PlanetaryFacilityColors.factoryInputIconBackgroundDark)
                                .frame(width: 32, height: 32)

                            // 浅色，根据库存占比从左向右覆盖
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(PlanetaryFacilityColors.factoryInputIconBackgroundLight)
                                    .frame(width: geometry.size.width * inventoryRatio, height: geometry.size.height)
                            }
                            .frame(width: 32, height: 32)

                            // 图标覆盖在背景上
                            Group {
                                if let iconName = typeIcons[input.typeId] {
                                    Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                } else {
                                    // 如果没有图标，显示一个占位符
                                    Image("not_found")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                }
                            }
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(
                                    NSLocalizedString("Factory_Input", comment: "")
                                        + " \(typeNames[input.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))"
                                )
                            }

                            // 显示当前存储量与需求量的比例
                            if let simPin = simulatedPin {
                                let currentAmount =
                                    simPin.contents.first(where: { $0.key.id == input.typeId })?
                                        .value ?? 0
                                Text(
                                    NSLocalizedString("Factory_Inventory", comment: "")
                                        + " \(currentAmount)/\(input.value)"
                                )
                                .font(.caption)
                                .foregroundColor(
                                    currentAmount >= input.value
                                        ? .secondary : currentAmount > 0 ? .blue : .red
                                )
                            } else {
                                let currentAmount =
                                    pin.contents?.first(where: { $0.typeId == input.typeId })?
                                        .amount ?? 0
                                Text(
                                    NSLocalizedString("Factory_Inventory", comment: "")
                                        + " \(currentAmount)/\(input.value)"
                                )
                                .font(.caption)
                                .foregroundColor(
                                    currentAmount >= input.value
                                        ? .secondary : currentAmount > 0 ? .blue : .red
                                )
                            }
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

            // 输出物品
            NavigationLink(
                destination: ShowPlanetaryInfo(
                    itemID: schematic.outputTypeId, databaseManager: DatabaseManager.shared
                )
            ) {
                HStack(alignment: .center, spacing: 12) {
                    if let iconName = typeIcons[schematic.outputTypeId] {
                        Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                    } else {
                        // 如果没有图标，显示一个占位符
                        Image("not_found")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(
                                NSLocalizedString("Factory_Output", comment: "")
                                    + " \(typeNames[schematic.outputTypeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))"
                            )
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

    /// 计算工厂进度
    /// - Parameters:
    ///   - factory: 工厂设施
    ///   - currentTime: 当前时间
    /// - Returns: 进度值（0-1）
    private func calculateFactoryProgress(factory: Pin.Factory, currentTime: Date) -> Double {
        // 如果工厂没有配方或不处于活跃状态，进度为0
        guard let schematic = factory.schematic,
              factory.isActive,
              let lastCycleStartTime = factory.lastCycleStartTime
        else {
            return 0
        }

        // 计算已经过去的时间与周期时间的比例
        let elapsed = currentTime.timeIntervalSince(lastCycleStartTime)
        let progress = elapsed / schematic.cycleTime

        // 确保进度在0到1之间
        return min(max(progress, 0), 1)
    }

    /// 格式化时间间隔（相对于模拟时间）
    /// - Parameter interval: 时间间隔（秒），正数表示未来，负数表示过去
    /// - Returns: 格式化后的时间字符串
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let absInterval = abs(interval)

        if absInterval < 60 {
            return String.localizedStringWithFormat(NSLocalizedString("Time_Seconds", comment: ""), Int(absInterval))
        } else if absInterval < 3600 {
            let minutes = Int(absInterval) / 60
            let seconds = Int(absInterval) % 60
            if seconds >= 30 {
                return String.localizedStringWithFormat(NSLocalizedString("Time_Minutes", comment: ""), minutes + 1)
            }
            return String.localizedStringWithFormat(NSLocalizedString("Time_Minutes", comment: ""), minutes)
        } else if absInterval < 86400 {
            let hours = Int(absInterval) / 3600
            let minutes = Int(absInterval) / 60 % 60
            if minutes >= 30 {
                return String.localizedStringWithFormat(NSLocalizedString("Time_Hours", comment: ""), hours + 1)
            }
            if hours > 0 {
                return String.localizedStringWithFormat(NSLocalizedString("Time_Hours", comment: ""), hours)
            }
            return String.localizedStringWithFormat(NSLocalizedString("Time_Minutes", comment: ""), minutes)
        } else {
            let days = Int(absInterval) / 86400
            let hours = Int(absInterval) / 3600 % 24
            if hours >= 12 {
                return String.localizedStringWithFormat(NSLocalizedString("Time_Days", comment: ""), days + 1)
            }
            if days > 0 {
                if hours > 0 {
                    return String.localizedStringWithFormat(NSLocalizedString("Time_Days_Hours", comment: ""), days, hours)
                }
                return String.localizedStringWithFormat(NSLocalizedString("Time_Days", comment: ""), days)
            }
            return String.localizedStringWithFormat(NSLocalizedString("Time_Hours", comment: ""), hours)
        }
    }
}
