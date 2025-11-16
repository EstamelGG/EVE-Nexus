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
    @State private var typeGroupIds: [Int: Int] = [:] // 存储type_id到group_id的映射（用于判断设施类型）
    @State private var typeMarketGroupIds: [Int: Int] = [:] // 存储type_id到marketGroupID的映射（用于排序仓储内容）
    @State private var typeVolumes: [Int: Double] = [:] // 存储type_id到体积的映射
    @State private var typeEnNames: [Int: String] = [:] // 存储type_id到en_name的映射（用于识别工厂类型）
    @State private var schematicDetails: [Int: SchematicInfo] = [:]
    @State private var simulatedColony: Colony? // 添加模拟结果状态
    @State private var hourlySnapshots: [Int: Colony] = [:] // 快照 [分钟数: 殖民地状态]，使用分钟数作为key以保留精度
    @State private var selectedMinutes: Int = 0 // 当前选中的分钟数（0 = 当前时间）
    @State private var isGeneratingSnapshots = false // 是否正在生成快照
    @State private var storageVolumeCache: [Int64: [Int: Double]] = [:] // 存储设施体积缓存 [pinId: [分钟数: 体积]]
    @State private var simulationProgress: Double = 0.0 // 模拟进度（0.0 到 1.0）
    @State private var isSimulatingInitial = false // 是否正在执行初始模拟
    @State private var currentTime = Date()
    @State private var lastCycleCheck: Int = -1
    @State private var hasInitialized = false
    @State private var isRealtimeMode: Bool = false // 实时模式状态
    @State private var lastSimulationTime: Date? // 上次模拟的时间，用于防抖
    @State private var isSimulating: Bool = false // 是否正在模拟中，避免重复触发
    @State private var checkpointTime: Date? // 存储 checkpoint 时间，用于计算进度
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // 计算要显示的殖民地
    // - 如果selectedMinutes == 0，显示实时模拟结果（simulatedColony）
    // - 如果selectedMinutes > 0，显示对应分钟数的快照
    private var displayColony: Colony? {
        if selectedMinutes == 0 {
            return simulatedColony
        } else if let snapshot = hourlySnapshots[selectedMinutes] {
            return snapshot
        }
        return simulatedColony
    }

    // 判断当前现实时间的殖民地是否已停工（用于禁用控件和显示提示）
    private var isRealtimeColonyStopped: Bool {
        // 只有在实时模式（selectedMinutes == 0）时才检查
        guard selectedMinutes == 0, let colony = simulatedColony else { return false }
        return !ColonySimulation.isColonyStillWorking(colony: colony)
    }

    // 计算最大分钟数
    private var maxMinutes: Int {
        hourlySnapshots.keys.max() ?? 0
    }

    // 获取所有可用的快照分钟数（排序后）
    private var availableSnapShot: [Int] {
        hourlySnapshots.keys.sorted()
    }

    // 获取当前选中分钟数在采样点序列中的索引
    private var selectedSnapshotIndex: Int {
        let sorted = availableSnapShot
        return sorted.firstIndex(of: selectedMinutes) ?? 0
    }

    // 根据索引获取对应的分钟数
    private func getMinutesAtIndex(_ index: Int) -> Int {
        let sorted = availableSnapShot
        guard index >= 0 && index < sorted.count else {
            return index < 0 ? 0 : (sorted.last ?? 0)
        }
        return sorted[index]
    }

    // 找到下一个可用的快照时间点（分钟数）
    private func nextAvailableMinutes(after minutes: Int) -> Int? {
        let sorted = availableSnapShot
        return sorted.first { $0 > minutes }
    }

    // 找到上一个可用的快照时间点（分钟数）
    private func previousAvailableMinutes(before minutes: Int) -> Int? {
        let sorted = availableSnapShot
        return sorted.last { $0 < minutes }
    }

    private let storageCapacities: [Int: Double] = [
        1027: 500.0, // 500m3
        1030: 10000.0, // 10000m3
        1029: 12000.0, // 12000m3
    ]

    var body: some View {
        ZStack {
            if let error = error {
                // 错误状态
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error.localizedDescription)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else if let detail = planetDetail, !isLoading {
                // 数据已加载，显示列表
                List {
                    // 对设施进行排序
                    let sortedPins = detail.pins.sorted { pin1, pin2 in
                        let group1 = typeGroupIds[pin1.typeId] ?? 0
                        let group2 = typeGroupIds[pin2.typeId] ?? 0

                        // 定义组的优先级
                        func getPriority(_ groupId: Int) -> Int {
                            switch groupId {
                            case 1027: return 0 // 指挥中心优先级最高
                            case 1029, 1030: return 1 // 仓库类（存储设施、发射台）
                            case 1063: return 2 // 采集器
                            case 1028: return 3 // 工厂
                            default: return 999
                            }
                        }

                        let priority1 = getPriority(group1)
                        let priority2 = getPriority(group2)

                        // 如果优先级不同，按优先级排序
                        if priority1 != priority2 {
                            return priority1 < priority2
                        }

                        // 如果都是工厂（groupId == 1028），按输入物品种类数量排序
                        if group1 == 1028 && group2 == 1028 {
                            let inputCount1 = getFactoryInputCount(pin: pin1)
                            let inputCount2 = getFactoryInputCount(pin: pin2)

                            // 输入物品种类多的排在前面
                            if inputCount1 != inputCount2 {
                                return inputCount1 > inputCount2
                            }

                            // 输入物品种类数量相同，按设施id排序
                            return pin1.pinId < pin2.pinId
                        }

                        // 其他情况保持原顺序
                        return false
                    }

                    ForEach(sortedPins, id: \.pinId) { pin in
                        if let groupId = typeGroupIds[pin.typeId] {
                            // 提前获取匹配的模拟Pin
                            let _ = simulatedColony?.pins.first(where: {
                                $0.id == pin.pinId
                            })

                            if storageCapacities.keys.contains(groupId) {
                                // 存储设施的显示方式
                                Section {
                                    StorageFacilityView(
                                        pin: pin,
                                        simulatedPin: displayColony?.pins.first(where: { $0.id == pin.pinId }),
                                        typeNames: typeNames,
                                        typeIcons: typeIcons,
                                        typeVolumes: typeVolumes,
                                        typeGroupIds: typeMarketGroupIds,
                                        capacity: storageCapacities[groupId] ?? 0,
                                        hourlySnapshots: hourlySnapshots,
                                        selectedMinutes: selectedMinutes,
                                        realtimeColony: simulatedColony,
                                        isSnapshotsReady: !hourlySnapshots.isEmpty && !isGeneratingSnapshots,
                                        storageVolumeCache: storageVolumeCache,
                                        isColonyStopped: isRealtimeColonyStopped
                                    )

                                } footer: {
                                    HStack {
                                        if groupId == 1027 {
                                            VStack(alignment: .leading, spacing: 4) {
                                                if let lastUpdateTime = simulatedColony?.checkpointSimTime {
                                                    Text(
                                                        "\(NSLocalizedString("Planet_Detail_Last_Update", comment: "")): \(formatRelativeTime(from: lastUpdateTime, currentTime: currentTime))"
                                                    )
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                }

                                                if isSimulatingInitial {
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        HStack {
                                                            ProgressView(value: simulationProgress)
                                                                .progressViewStyle(.linear)
                                                                .frame(height: 4)
                                                            Text("\(Int(simulationProgress * 100))%")
                                                                .font(.caption2)
                                                                .foregroundColor(.secondary)
                                                                .frame(width: 40)
                                                        }
                                                        Text(NSLocalizedString("Planet_Detail_Simulating", comment: "正在模拟..."))
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }

                                                // 如果当前现实时间的殖民地已停工，显示红色提示
                                                if isRealtimeColonyStopped {
                                                    Text(NSLocalizedString("Planet_Colony_Stopped", comment: "星球已停工"))
                                                        .font(.caption)
                                                        .foregroundColor(.red)
                                                }
                                            }
                                        }
                                        Spacer()
                                        Text(PlanetaryFacility(identifier: pin.pinId).name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else if groupId == 1028 {
                                // 加工设施
                                Section {
                                    FactoryFacilityView(
                                        pin: pin,
                                        simulatedPin: displayColony?.pins.first(where: {
                                            $0.id == pin.pinId
                                        }) as? Pin.Factory,
                                        typeNames: typeNames,
                                        typeIcons: typeIcons,
                                        typeEnNames: typeEnNames,
                                        schematic: pin.schematicId != nil
                                            ? schematicDetails[pin.schematicId!] : nil,
                                        currentTime: selectedMinutes == 0 ? currentTime : (displayColony?.currentSimTime ?? currentTime)
                                    )
                                } footer: {
                                    HStack {
                                        Spacer()
                                        Text(PlanetaryFacility(identifier: pin.pinId).name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else if let extractor = pin.extractorDetails {
                                // 提取器设施
                                Section {
                                    ExtractorFacilityView(
                                        pin: pin,
                                        extractor: extractor,
                                        typeNames: typeNames,
                                        typeIcons: typeIcons,
                                        currentTime: selectedMinutes == 0 ? currentTime : (displayColony?.currentSimTime ?? currentTime)
                                    )
                                } footer: {
                                    HStack {
                                        Spacer()
                                        Text(PlanetaryFacility(identifier: pin.pinId).name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .transition(.opacity)
            } else if isLoading {
                // 加载状态 - 显示模拟进度
                VStack(spacing: 16) {
                    if isSimulatingInitial && simulationProgress > 0 {
                        VStack(spacing: 12) {
                            ProgressView(value: simulationProgress)
                                .progressViewStyle(.linear)
                                .frame(height: 8)

                            HStack {
                                Text("\(Int(simulationProgress * 100))%")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                if let checkpoint = checkpointTime {
                                    let targetTime = Date()
                                    let timeDiff = targetTime.timeIntervalSince(checkpoint)
                                    let currentSimTime = checkpoint.addingTimeInterval(timeDiff * simulationProgress)
                                    Text(formatDate(currentSimTime))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text(NSLocalizedString("Planet_Detail_Simulating", comment: "正在模拟..."))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 40)
                    } else {
                        ProgressView()
                    }
                }
                .transition(.opacity)
            } else {
                // 无数据状态
                Text(NSLocalizedString("Planet_Detail_No_Data", comment: ""))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .animation(.easeInOut(duration: 0.3), value: isSimulatingInitial)
        .safeAreaInset(edge: .bottom) {
            // 底部悬浮窗 - 时间滑动条（延伸到底部，毛玻璃背景）
            // 显示条件：无异常、有快照数据，或者正在生成快照
            if error == nil, let _ = planetDetail, !isLoading, !hourlySnapshots.isEmpty || isGeneratingSnapshots {
                VStack(spacing: 0) {
                    // 顶部分隔线
                    Divider()
                        .opacity(0.2)

                    timeSliderFloatingView
                        .padding(.top, 14)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(alignment: .top) {
                            // 磨玻璃效果背景，顶部圆角，底部延伸到边缘
                            UnevenRoundedRectangle(cornerRadii: .init(
                                topLeading: 20,
                                bottomLeading: 0,
                                bottomTrailing: 0,
                                topTrailing: 20
                            ), style: .continuous)
                                .fill(.regularMaterial)
                                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: -2)
                                .ignoresSafeArea(edges: .bottom)
                        }
                }
            }
        }
        .navigationTitle(planetName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !hasInitialized {
                // 延迟一小段时间，确保视图层级完全建立
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                // 立即更新当前时间，避免显示缓存的旧时间
                currentTime = Date()
                let didInitialSimulation = await loadPlanetDetail()
                // 如果执行了初始模拟，等待0.5秒再显示详情页面
                // 这样可以让用户看到进度条达到100%的状态
                if didInitialSimulation {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                    // 延迟后使用动画同时设置 isSimulatingInitial = false 和 isLoading = false
                    // 以隐藏进度条并显示详情页面，使用渐出渐入动画
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isSimulatingInitial = false
                            isLoading = false
                        }
                    }
                }
                hasInitialized = true
            }
        }
        .refreshable {
            // 立即更新当前时间，避免显示缓存的旧时间
            currentTime = Date()
            let didInitialSimulation = await loadPlanetDetail(forceRefresh: true)
            // 刷新时如果执行了初始模拟，也需要延迟后设置
            if didInitialSimulation {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
                // 延迟后使用动画同时设置 isSimulatingInitial = false 和 isLoading = false
                withAnimation(.easeInOut(duration: 0.3)) {
                    isSimulatingInitial = false
                    isLoading = false
                }
            }
        }
        .onReceive(timer) { newTime in
            let shouldUpdate = shouldUpdateView(newTime: newTime)
            if shouldUpdate {
                currentTime = newTime
            }

            // 检查是否有工厂周期完成，需要重新模拟
            // 防抖机制：如果正在模拟中，或者距离上次模拟时间太近（1秒内），则跳过
            if !isSimulating, shouldResimulate(newTime: newTime) {
                // 检查距离上次模拟的时间
                if let lastSimTime = lastSimulationTime {
                    let timeSinceLastSim = newTime.timeIntervalSince(lastSimTime)
                    // 如果距离上次模拟超过1秒，则触发模拟
                    if timeSinceLastSim >= 1.0 {
                        Task {
                            await resimulateColony()
                        }
                    }
                } else {
                    // 如果没有上次模拟时间，立即模拟
                    Task {
                        await resimulateColony()
                    }
                }
            }
        }
        .onAppear {
            // 视图出现时立即更新当前时间
            currentTime = Date()
        }
        .onChange(of: selectedMinutes) { _, newValue in
            // 当滑动条位置变化时，自动更新实时模式状态
            isRealtimeMode = (newValue == 0)
        }
    }

    /// 底部悬浮窗 - 时间滑动条视图
    @ViewBuilder
    private var timeSliderFloatingView: some View {
        // 显示条件：有快照数据，或者正在生成快照
        if !hourlySnapshots.isEmpty || isGeneratingSnapshots {
            timeSliderControlsView
        } else {
            EmptyView()
        }
    }

    /// 时间滑动条控制组件（包含正在生成快照、实时按钮、滑动条、停工文本、查看时间）
    private var timeSliderControlsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 如果正在生成快照，显示生成进度
            if isGeneratingSnapshots {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text(NSLocalizedString("Planet_Detail_Generating_Snapshots", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 32)
                .padding(.trailing, 32)
            } else if !hourlySnapshots.isEmpty {
                // 第一行：减号按钮、实时按钮、滑动条、停工按钮、加号按钮
                HStack(spacing: 8) {
                    // 减号按钮 - 跳转到上一个快照点
                    Button(action: {
                        if let prev = previousAvailableMinutes(before: selectedMinutes) {
                            selectedMinutes = prev
                        } else {
                            selectedMinutes = 0
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundColor(isRealtimeColonyStopped ? .gray : (selectedMinutes > 0 ? .blue : .gray))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRealtimeColonyStopped || selectedMinutes == 0)
                    .padding(.leading, 32)

                    // 实时按钮 - 激活状态与滑动条位置关联
                    let isRealtimeActive = selectedMinutes == 0
                    Button(action: {
                        // 点击实时按钮，将滑动条移到最左侧
                        selectedMinutes = 0
                    }) {
                        Text(NSLocalizedString("Planet_Detail_Realtime", comment: "实时"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(isRealtimeColonyStopped ? .gray : (isRealtimeActive ? .white : .blue))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isRealtimeColonyStopped ? Color.clear : (isRealtimeActive ? Color.blue : Color.clear))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRealtimeColonyStopped ? Color.gray : Color.blue, lineWidth: isRealtimeActive ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRealtimeColonyStopped)

                    // 滑动条，左右距离实时和停工组件各4单位
                    // 滑动条直接操作采样点的索引，在离散的采样点之间移动
                    // 注意：滑动条内部使用索引（0到count-1），但时间显示使用formatDate保持秒级精度
                    let snapshotCount = availableSnapShot.count
                    Slider(value: Binding(
                        get: {
                            // 返回当前选中采样点的索引（0到count-1）
                            Double(selectedSnapshotIndex)
                        },
                        set: { newIndex in
                            // 根据索引找到对应的采样点
                            let index = Int(newIndex.rounded())
                            selectedMinutes = getMinutesAtIndex(index)
                        }
                    ), in: 0 ... Double(max(0, snapshotCount - 1)), step: 1.0)
                        .disabled(isRealtimeColonyStopped)

                    // 停工按钮 - 激活状态与滑动条位置关联
                    let isExpireActive = selectedMinutes == maxMinutes
                    Button(action: {
                        // 点击停工按钮，将滑动条移到最右侧
                        selectedMinutes = maxMinutes
                    }) {
                        Text(NSLocalizedString("Planet_Detail_Expire", comment: "停工"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(isRealtimeColonyStopped ? .gray : (isExpireActive ? .white : .orange))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isRealtimeColonyStopped ? Color.clear : (isExpireActive ? Color.orange : Color.clear))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRealtimeColonyStopped ? Color.gray : Color.orange, lineWidth: isExpireActive ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRealtimeColonyStopped)

                    // 加号按钮 - 跳转到下一个快照点
                    Button(action: {
                        if let next = nextAvailableMinutes(after: selectedMinutes) {
                            selectedMinutes = next
                        } else {
                            selectedMinutes = maxMinutes
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundColor(isRealtimeColonyStopped ? .gray : (selectedMinutes < maxMinutes ? .blue : .gray))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRealtimeColonyStopped || selectedMinutes == maxMinutes)
                    .padding(.trailing, 32)
                }

                // 第二行：当前查看时间或停工提示（显示在滚动条下方）
                if isRealtimeColonyStopped {
                    // 如果当前现实时间的殖民地已停工，显示红色提示
                    Text(NSLocalizedString("Planet_Colony_Stopped", comment: "星球已停工"))
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.leading, 64)
                        .padding(.trailing, 64)
                } else if let colony = displayColony {
                    // 显示采样点的实际时间，保持秒级精度（yyyy-MM-dd HH:mm:ss）
                    // 计算模拟时间点与原始数据基准时间的差值
                    let timeDiff = colony.currentSimTime.timeIntervalSince(colony.checkpointSimTime)
                    HStack {
                        Text(NSLocalizedString("Planet_Detail_View_Time", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatDate(colony.currentSimTime))
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("(+\(formatTimeDiff(timeDiff)))")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    .padding(.leading, 64)
                    .padding(.trailing, 64)
                }
            }
        }
    }

    /// 获取工厂的输入物品种类数量
    /// - Parameter pin: 工厂pin
    /// - Returns: 输入物品种类数量，如果没有配方则返回0
    private func getFactoryInputCount(pin: PlanetaryPin) -> Int {
        // 获取配方ID，首先尝试从factoryDetails获取，如果不存在则直接使用schematicId
        let schematicId: Int?
        if let factoryDetails = pin.factoryDetails {
            schematicId = factoryDetails.schematicId
        } else {
            schematicId = pin.schematicId
        }

        guard let id = schematicId,
              let schematic = schematicDetails[id]
        else {
            return 0
        }
        return schematic.inputs.count
    }

    // 格式化日期
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX") // 使用POSIX locale确保24小时制
        return formatter.string(from: date)
    }

    // 格式化相对时间（如"x 分钟前"、"x 小时前"、"x 天 x 小时前"）
    private func formatRelativeTime(from date: Date, currentTime: Date) -> String {
        let interval = currentTime.timeIntervalSince(date)

        // 如果时间在未来，返回"刚刚"
        if interval < 0 {
            return NSLocalizedString("Time_Just_Now", comment: "刚刚")
        }

        let totalSeconds = Int(interval)
        let days = totalSeconds / (24 * 3600)
        let hours = totalSeconds / 3600 % 24
        let minutes = totalSeconds / 60 % 60

        if days > 0 {
            // 如果有小时，显示"x 天 x 小时前"
            if hours > 0 {
                return String(format: NSLocalizedString("Time_Days_Hours_Ago", comment: "%d天%d小时前"), days, hours)
            } else {
                // 只有天数
                return String(format: NSLocalizedString("Time_Days_Ago", comment: ""), days)
            }
        } else if hours > 0 {
            // 如果有分钟，显示"x 小时 x 分钟前"
            if minutes > 0 {
                return String(format: NSLocalizedString("Time_Hours_Minutes_Ago", comment: "%d小时%d分钟前"), hours, minutes)
            } else {
                // 只有小时
                return String(format: NSLocalizedString("Time_Hours_Ago", comment: ""), hours)
            }
        } else if minutes > 0 {
            // 只有分钟
            return String(format: NSLocalizedString("Time_Minutes_Ago", comment: ""), minutes)
        } else {
            // 小于30秒，显示"刚刚"
            return NSLocalizedString("Time_Just_Now", comment: "刚刚")
        }
    }

    // 格式化时间差（使用本地化字符串）
    private func formatTimeDiff(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return String(format: NSLocalizedString("Time_Seconds", comment: ""), 0)
        }

        let totalSeconds = interval
        let days = Int(totalSeconds) / (24 * 3600)
        var hours = Int(totalSeconds) / 3600 % 24
        var minutes = Int(totalSeconds) / 60 % 60
        let seconds = Int(totalSeconds) % 60

        // 当显示两个单位时，对第二个单位进行四舍五入
        if days > 0 {
            // 对小时进行四舍五入
            if minutes >= 30 {
                hours += 1
                if hours == 24 { // 如果四舍五入后小时数达到24
                    return String(format: NSLocalizedString("Time_Days", comment: ""), days + 1)
                }
            }
            if hours > 0 {
                return String(
                    format: NSLocalizedString("Time_Days_Hours", comment: ""), days, hours
                )
            }
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        } else if hours > 0 {
            // 对分钟进行四舍五入
            if seconds >= 30 {
                minutes += 1
                if minutes == 60 { // 如果四舍五入后分钟数达到60
                    return String(format: NSLocalizedString("Time_Hours", comment: ""), hours + 1)
                }
            }
            if minutes > 0 {
                return String(
                    format: NSLocalizedString("Time_Hours_Minutes", comment: ""), hours, minutes
                )
            }
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        } else if minutes > 0 {
            // 对秒进行四舍五入
            if seconds >= 30 {
                return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes + 1)
            }
            if seconds > 0 {
                return String(
                    format: NSLocalizedString("Time_Minutes_Seconds", comment: ""), minutes, seconds
                )
            }
            return String(format: NSLocalizedString("Time_Minutes", comment: ""), minutes)
        }
        return String(format: NSLocalizedString("Time_Seconds", comment: ""), seconds)
    }

    private func shouldUpdateView(newTime: Date) -> Bool {
        guard let detail = planetDetail else { return false }

        // 实时模式下（滑动条在最左侧），总是更新视图以确保进度条实时更新
        if selectedMinutes == 0 {
            return true
        }

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
                    cycleTime: cycleTime,
                    currentTime: displayColony?.currentSimTime ?? currentTime
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

    // 计算存储设施体积缓存
    private func calculateStorageVolumeCache(snapshots: [Int: Colony], currentColony _: Colony) async {
        // 预先计算并缓存每个存储设施在每个时间点的体积数据
        var volumeCache: [Int64: [Int: Double]] = [:]

        // 获取当前主线程的 typeVolumes 和 typeGroupIds 副本
        let (volumes, groupIds, planetDetailPins) = await MainActor.run {
            (self.typeVolumes, self.typeGroupIds, self.planetDetail?.pins ?? [])
        }

        // 从 planetDetail 中找出所有存储设施的 pinId（与 UI 判断逻辑一致）
        let storagePinIds = Set(planetDetailPins.compactMap { pin -> Int64? in
            if let groupId = groupIds[pin.typeId],
               storageCapacities.keys.contains(groupId)
            {
                return pin.pinId
            }
            return nil
        })

        Logger.info("找到 \(storagePinIds.count) 个存储设施 pinId: \(storagePinIds)")

        // 处理所有快照数据（只包含实际采样点，不包含每一分钟的数据）
        // 例如：采样间隔0.2小时（12分钟），则只保存0、12、24、36...分钟的数据
        for (minutes, snapshot) in snapshots {
            for pin in snapshot.pins {
                // 使用 pinId 判断，而不是类型判断，确保与 UI 逻辑一致
                if storagePinIds.contains(pin.id) {
                    let totalVolume = pin.contents.reduce(0.0) { sum, pair in
                        sum + (Double(pair.value) * (volumes[pair.key.id] ?? pair.key.volume))
                    }
                    if volumeCache[pin.id] == nil {
                        volumeCache[pin.id] = [:]
                    }
                    volumeCache[pin.id]?[minutes] = totalVolume
                }
            }
        }

        await MainActor.run {
            self.storageVolumeCache = volumeCache
            Logger.info("存储设施体积缓存计算完成，共 \(volumeCache.count) 个存储设施")
        }
    }

    /// 检查是否有工厂或提取器周期完成需要重新模拟
    /// - Parameter newTime: 新时间
    /// - Returns: 是否需要重新模拟
    private func shouldResimulate(newTime: Date) -> Bool {
        guard let colony = simulatedColony else { return false }

        // 检查所有工厂
        for pin in colony.pins {
            if let factory = pin as? Pin.Factory,
               factory.isActive,
               let lastCycleStartTime = factory.lastCycleStartTime,
               let schematic = factory.schematic
            {
                let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematic.cycleTime)

                // 如果工厂周期已完成且超过了模拟时间，需要重新模拟
                if newTime >= cycleEndTime && cycleEndTime > colony.currentSimTime {
                    Logger.info("检测到工厂(\(factory.id))周期完成，触发重新模拟")
                    return true
                }
            }

            // 检查提取器周期
            if let extractor = pin as? Pin.Extractor,
               extractor.isActive,
               let lastRunTime = extractor.lastRunTime,
               let cycleTime = extractor.cycleTime
            {
                let cycleEndTime = lastRunTime.addingTimeInterval(cycleTime)

                // 如果提取器周期已完成且超过了模拟时间，需要重新模拟
                if newTime >= cycleEndTime && cycleEndTime > colony.currentSimTime {
                    Logger.info("检测到提取器(\(extractor.id))周期完成，触发重新模拟")
                    return true
                }
            }
        }

        return false
    }

    private func loadPlanetDetail(forceRefresh: Bool = false) async -> Bool {
        var didInitialSimulation = false // 跟踪是否执行了初始模拟
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
                    // 保存 checkpoint 时间，用于显示进度
                    // lastUpdate 是 ISO8601 格式的字符串，需要转换为 Date
                    let dateFormatter = ISO8601DateFormatter()
                    dateFormatter.formatOptions = [.withInternetDateTime]
                    checkpointTime = dateFormatter.date(from: info.lastUpdate) ?? Date()

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

                    // 使用ColonySimulationManager执行模拟到当前时间
                    // 在后台线程执行，避免阻塞主线程和 UI 交互
                    isSimulatingInitial = true
                    simulationProgress = 0.0
                    let simulatedColonyResult = await Task.detached(priority: .userInitiated) {
                        ColonySimulationManager.shared.simulateColony(
                            colony: colony,
                            targetTime: Date()
                        ) { progress in
                            // 在主线程更新进度
                            Task { @MainActor in
                                self.simulationProgress = progress
                            }
                        }
                    }.value
                    await MainActor.run {
                        self.simulatedColony = simulatedColonyResult
                        // 保持 isSimulatingInitial = true，让进度条继续显示100%
                        // 延迟后会在 .task 中设置为 false
                        self.simulationProgress = 1.0
                    }
                    didInitialSimulation = true

                    // 生成每小时快照（在后台执行）
                    // 注意：从已模拟到当前时间的殖民地开始生成快照
                    // 如果是强制刷新，清空旧快照并重新生成
                    if forceRefresh {
                        await MainActor.run {
                            self.hourlySnapshots = [:]
                            self.storageVolumeCache = [:]
                            self.selectedMinutes = 0
                        }
                    }

                    if hourlySnapshots.isEmpty, let currentColony = simulatedColony {
                        isGeneratingSnapshots = true
                        Task.detached(priority: .utility) {
                            // 第一步：生成所有快照
                            let snapshots = ColonySimulationManager.shared.generateHourlySnapshots(colony: currentColony)

                            await MainActor.run {
                                self.hourlySnapshots = snapshots
                                self.isGeneratingSnapshots = false
                                // 设置初始选中小时为0（当前时间）
                                self.selectedMinutes = 0
                                // 输出快照数据点数量日志
                                Logger.info("快照计算完成，共有 \(snapshots.count) 个数据点位")

                                // 如果 typeVolumes 已经加载，立即计算缓存
                                if !self.typeVolumes.isEmpty {
                                    Task.detached(priority: .utility) {
                                        await self.calculateStorageVolumeCache(snapshots: snapshots, currentColony: currentColony)
                                    }
                                }
                            }
                        }
                    }
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
                        SELECT type_id, name, en_name, icon_filename, groupID, marketGroupID, volume
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
                                // 存储 groupID（用于判断设施类型）
                                if let groupId = row["groupID"] as? Int {
                                    typeGroupIds[typeId] = groupId
                                }
                                // 存储 marketGroupID（用于排序仓储内容）
                                if let marketGroupId = row["marketGroupID"] as? Int {
                                    typeMarketGroupIds[typeId] = marketGroupId
                                }
                                if let volume = row["volume"] as? Double {
                                    typeVolumes[typeId] = volume
                                }
                                // 存储 en_name（用于识别工厂类型）
                                if let enName = row["en_name"] as? String {
                                    typeEnNames[typeId] = enName
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

                    if case let .success(rows) = DatabaseManager.shared.executeQuery(schematicQuery) {
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
                            SELECT type_id, name, en_name, icon_filename, groupID, marketGroupID, volume
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
                                    // 存储 groupID（用于判断设施类型）
                                    if let groupId = row["groupID"] as? Int {
                                        typeGroupIds[typeId] = groupId
                                    }
                                    // 存储 marketGroupID（用于排序仓储内容）
                                    if let marketGroupId = row["marketGroupID"] as? Int {
                                        typeMarketGroupIds[typeId] = marketGroupId
                                    }
                                    if let volume = row["volume"] as? Double {
                                        typeVolumes[typeId] = volume
                                    }
                                    // 存储 en_name（用于识别工厂类型）
                                    if let enName = row["en_name"] as? String {
                                        typeEnNames[typeId] = enName
                                    }
                                }
                            }
                        }
                    }

                    // typeVolumes 加载完成后，如果快照已生成，立即计算存储设施体积缓存
                    if !hourlySnapshots.isEmpty, let currentColony = simulatedColony, !typeVolumes.isEmpty {
                        Task.detached(priority: .utility) {
                            await self.calculateStorageVolumeCache(snapshots: self.hourlySnapshots, currentColony: currentColony)
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

            // 如果没有执行初始模拟，立即设置 isLoading = false
            // 如果执行了初始模拟，由调用者控制延迟后设置
            if !didInitialSimulation {
                isLoading = false
            }
        }

        await task.value
        return didInitialSimulation
    }

    /// 重新模拟殖民地到当前时间
    private func resimulateColony() async {
        // 检查并设置模拟中标志（在主线程上执行，避免竞态条件）
        let shouldProceed = await MainActor.run {
            // 如果正在模拟中，跳过
            if isSimulating {
                return false
            }
            // 设置模拟中标志
            isSimulating = true
            return true
        }

        guard shouldProceed else { return }
        guard let colony = simulatedColony else {
            await MainActor.run {
                isSimulating = false
            }
            return
        }

        // 立即更新当前时间
        let now = Date()
        await MainActor.run {
            currentTime = now
        }

        // 如果当前时间早于或等于模拟时间，不需要重新模拟
        if now <= colony.currentSimTime {
            await MainActor.run {
                isSimulating = false
            }
            return
        }

        Logger.info("重新模拟殖民地到当前时间: \(now)")

        // 使用ColonySimulationManager执行模拟
        let newSimulatedColony = await Task.detached(priority: .userInitiated) {
            ColonySimulationManager.shared.simulateColony(
                colony: colony,
                targetTime: now
            )
        }.value

        // 更新模拟结果和防抖状态
        await MainActor.run {
            self.simulatedColony = newSimulatedColony
            self.isSimulating = false
            self.lastSimulationTime = now
        }
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
