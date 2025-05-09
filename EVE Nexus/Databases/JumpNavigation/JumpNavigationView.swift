import Foundation
import SwiftUI

// 添加一个星系数据结构体，包含所有需要的字段
struct JumpSystemData {
    let id: Int
    let name: String
    let security: Double
    let region: String
    let x: Double
    let y: Double
    let z: Double

    // 静态方法：从数据库加载所有跳跃星系数据
    static func loadAllJumpSystems(databaseManager: DatabaseManager) -> [JumpSystemData] {
        var systems: [JumpSystemData] = []

        // 综合查询，获取所有满足跳跃条件的星系信息
        let query = """
                SELECT u.solarsystem_id, s.solarSystemName, 
                       u.system_security, r.regionName, u.x, u.y, u.z
                FROM universe u
                JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                JOIN regions r ON r.regionID = u.region_id
                WHERE u.hasJumpGate -- 排除没有星门的星系，一般是虫洞和GM星系
                AND NOT u.isJSpace -- 排除虫洞星系
                AND u.region_id NOT IN (10000019, 10000004, 10000017, 10000070) -- 排除朱庇特星域与波赫文星域
                AND u.solarsystem_id NOT IN (30100000) -- 排除扎尔扎克
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            Logger.info("加载跳跃星系数据：查询成功，获取到 \(rows.count) 条记录")

            for row in rows {
                if let id = row["solarsystem_id"] as? Int,
                    let name = row["solarSystemName"] as? String,
                    let security = row["system_security"] as? Double,
                    let region = row["regionName"] as? String,
                    let x = row["x"] as? Double,
                    let y = row["y"] as? Double,
                    let z = row["z"] as? Double
                {

                    // 计算显示安全等级
                    let displaySec = calculateDisplaySecurity(security)

                    systems.append(
                        JumpSystemData(
                            id: id,
                            name: name,
                            security: displaySec,
                            region: region,
                            x: x,
                            y: y,
                            z: z
                        )
                    )

                    // 只添加实际显示安全等级小于0.5的星系
                    //                    if displaySec < 0.5 {
                    //                        systems.append(
                    //                            JumpSystemData(
                    //                                id: id,
                    //                                name: name,
                    //                                security: displaySec,
                    //                                x: x,
                    //                                y: y,
                    //                                z: z
                    //                            )
                    //                        )
                    //                    }
                }
            }
            Logger.info("跳跃星系数据加载完成：符合条件的星系数量为 \(systems.count)")
        } else {
            Logger.error("跳跃星系数据查询失败")
        }

        return systems
    }
}

// 飞船数据结构
struct Ship: Identifiable {
    let id: Int
    let name: String
    let enName: String
    let iconFilename: String
    let groupId: Int
    let groupName: String
}

// 添加一个全局变量，用于缓存所有跳跃星系数据
class JumpSystemsCache {
    static let shared = JumpSystemsCache()

    private(set) var allJumpSystems: [JumpSystemData] = []
    private var isLoaded = false

    // 懒加载方法
    func loadIfNeeded(databaseManager: DatabaseManager) {
        if !isLoaded {
            allJumpSystems = JumpSystemData.loadAllJumpSystems(databaseManager: databaseManager)
            isLoaded = true
            Logger.info("JumpSystemsCache: 初始化加载了 \(allJumpSystems.count) 个星系")
        }
    }

    // 获取所有星系ID到名称的映射
    var systemIdToName: [Int: String] {
        var result: [Int: String] = [:]
        for system in allJumpSystems {
            result[system.id] = system.name
        }
        return result
    }

    // 获取所有星系ID到英文名称的映射
    var systemIdToEnName: [Int: String] {
        var result: [Int: String] = [:]
        // 查询数据库获取英文名称
        let query = """
                SELECT solarSystemID, solarSystemName_en
                FROM solarsystems
                WHERE solarSystemID IN (\(allJumpSystems.map { String($0.id) }.joined(separator: ",")))
            """

        if case let .success(rows) = DatabaseManager.shared.executeQuery(query) {
            for row in rows {
                if let systemId = row["solarSystemID"] as? Int,
                    let enName = row["solarSystemName_en"] as? String
                {
                    result[systemId] = enName
                }
            }
            Logger.info("已加载 \(result.count) 个星系的英文名称")
        } else {
            Logger.error("加载星系英文名称失败")
        }

        return result
    }

    // 获取所有星系ID到安全等级的映射
    var systemIdToSecurity: [Int: Double] {
        var result: [Int: Double] = [:]
        for system in allJumpSystems {
            result[system.id] = system.security
        }
        return result
    }

    // 获取符合条件的星系列表（用于选择器）
    var jumpableSystems: [(id: Int, name: String, security: Double, region: String)] {
        return allJumpSystems.map {
            (id: $0.id, name: $0.name, security: $0.security, region: $0.region)
        }
        .sorted { $0.name < $1.name }
    }

    private init() {}
}

struct JumpNavigationView: View {
    @State private var isLoading = false
    @State private var progressMessage: String = ""
    @State private var progressValue: Double = 0.0
    @State private var showingConfirmation = false
    @State private var loadingState: LoadingState = .processing
    @State private var didInitialCheck = false

    // 修改UI相关状态
    @State private var selectedShip: Int = 0  // 修改为Int类型
    @State private var JDCLv: Int = 5
    @State private var startPointId: Int? = nil  // 修改为星系ID
    @State private var waypointIds: [Int] = []  // 修改为星系ID数组
    @State private var avoidSystemIds: [Int] = []  // 修改为星系ID数组
    @State private var avoidIncursionSystems: Bool = true  // 添加避开入侵星系状态

    // 添加星系名称映射
    @State private var systemIdToName: [Int: String] = [:]
    @State private var systemIdToEnName: [Int: String] = [:]

    // 添加飞船数据状态
    @State private var ships: [Int: [Ship]]

    // Sheet控制状态
    @State private var showingShipSelector = false
    @State private var showingStartPointSelector = false
    @State private var showingWaypointSelector = false
    @State private var showingAvoidSystemSelector = false

    // 添加结果相关状态
    @State private var pathResults: [PathResult] = []
    @State private var showingPathResults = false
    @State private var systemIdToSecurity: [Int: Double] = [:]

    // 添加状态变量来控制数据加载
    @State private var hasLoadedSystemNames = false

    // 添加状态变量来控制计算按钮状态
    @State private var isCalculating = false

    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager

        // 初始化加载跳跃星系数据
        JumpSystemsCache.shared.loadIfNeeded(databaseManager: databaseManager)

        // 在初始化时就加载飞船数据
        _ships = State(initialValue: JumpNavigationView.loadShips(databaseManager: databaseManager))

        // 使用缓存的星系数据
        _systemIdToName = State(initialValue: JumpSystemsCache.shared.systemIdToName)
        _systemIdToSecurity = State(initialValue: JumpSystemsCache.shared.systemIdToSecurity)
        _systemIdToEnName = State(initialValue: JumpSystemsCache.shared.systemIdToEnName)
        _hasLoadedSystemNames = State(initialValue: !JumpSystemsCache.shared.systemIdToName.isEmpty)

        Logger.info(
            "JumpNavigationView初始化完成，已加载飞船数据和\(JumpSystemsCache.shared.systemIdToName.count)个星系名称")
    }

    var body: some View {
        VStack {
            if isLoading {
                VStack(spacing: 15) {
                    CustomLoadingView(
                        loadingState: $loadingState,
                        progress: progressValue,
                        loadingText: progressMessage,
                        onComplete: {
                            isLoading = false
                        }
                    )
                }
                .padding()
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                // 加载完成后显示导航计算UI
                NavigationCalculationUI
            }
        }
        .navigationTitle(NSLocalizedString("Main_Jump_Navigation", comment: ""))
        .navigationBarItems(
            trailing:
                Button(action: {
                    showingConfirmation = true
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
        )
        .alert(
            NSLocalizedString("Jump_Navigation_Recalculate_Title", comment: ""),
            isPresented: $showingConfirmation
        ) {
            Button(
                NSLocalizedString("Jump_Navigation_Recalculate_Confirm", comment: ""),
                role: .destructive
            ) {
                recalculateJumpMap()
            }
            Button(NSLocalizedString("Main_Setting_Cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("Jump_Navigation_Recalculate_Message", comment: ""))
        }
        .sheet(isPresented: $showingPathResults) {
            if !pathResults.isEmpty {
                NavigationView {
                    JumpPathResultView(
                        pathResult: mergePathResults(pathResults),
                        systemIdToName: systemIdToName,
                        systemIdToSecurity: systemIdToSecurity,
                        shipEnName: ships.values.flatMap({ $0 }).first(where: {
                            $0.id == selectedShip
                        })?.enName ?? "",
                        jdcLevel: JDCLv,
                        systemIdToEnName: systemIdToEnName,
                        startPointId: startPointId,
                        waypointIds: waypointIds,
                        avoidSystemIds: avoidSystemIds,
                        avoidIncursions: avoidIncursionSystems
                    )
                }
            }
        }
        .task {
            if !didInitialCheck {
                checkAndInitializeJumpMap()
                didInitialCheck = true
            }
        }
        .sheet(isPresented: $showingShipSelector) {
            ShipSelectorView(selectedShip: $selectedShip, ships: ships)
        }
        .sheet(isPresented: $showingStartPointSelector) {
            SystemSelectorSheet(
                title: NSLocalizedString("Jump_Navigation_Select_Start", comment: ""),
                currentSelection: startPointId,
                onlyLowSec: false,  // 起点可以选择所有星系
                onSelect: { systemId in
                    startPointId = systemId
                    showingStartPointSelector = false
                },
                onCancel: {
                    showingStartPointSelector = false
                }
            )
        }
        .sheet(isPresented: $showingWaypointSelector) {
            SystemSelectorSheet(
                title: NSLocalizedString("Jump_Navigation_Add_Waypoint", comment: ""),
                currentSelection: waypointIds.last,
                onlyLowSec: true,  // 路径点只能选择低安全等级星系
                onSelect: { systemId in
                    waypointIds.append(systemId)
                    showingWaypointSelector = false
                },
                onCancel: {
                    showingWaypointSelector = false
                }
            )
        }
        .sheet(isPresented: $showingAvoidSystemSelector) {
            SystemSelectorSheet(
                title: NSLocalizedString("Jump_Navigation_Add_Avoid", comment: ""),
                currentSelection: nil,
                onSelect: { systemId in
                    if !avoidSystemIds.contains(systemId) {
                        avoidSystemIds.append(systemId)
                    }
                    showingAvoidSystemSelector = false
                },
                onCancel: {
                    showingAvoidSystemSelector = false
                }
            )
        }
    }

    // 导航计算UI
    private var NavigationCalculationUI: some View {
        VStack {
            List {
                // 第一个section：飞船和技能
                Section {
                    // 选择飞船 - 使用Button和sheet
                    Button(action: {
                        showingShipSelector = true
                    }) {
                        HStack {
                            Text(NSLocalizedString("Jump_Navigation_Ship_Selection", comment: ""))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(getShipName())
                                .foregroundColor(.gray)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }

                    // 技能A等级 - 使用下拉菜单
                    Picker(
                        NSLocalizedString("Jump_Navigation_JDC_Skill", comment: ""),
                        selection: $JDCLv
                    ) {
                        ForEach(1...5, id: \.self) { level in
                            Text(
                                String(
                                    format: NSLocalizedString("Misc_Level", comment: "lv%d"), level)
                            ).tag(level)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Jump_Navigation_Ship_And_Skills", comment: ""))
                } footer: {
                    HStack {
                        Spacer()
                        Text(
                            "\(NSLocalizedString("Jump_Navigation_Max_Jump_Range", comment: "")): \(String(format: "%.1f Ly", calculateMaxJumpRange()))"
                        )
                        .foregroundColor(.secondary)
                    }
                }

                // 安全设置
                Section {
                    Toggle(isOn: $avoidIncursionSystems) {
                        Text(
                            NSLocalizedString("Jump_Navigation_Avoid_Incursion", comment: "避开入侵星系"))
                    }
                } header: {
                    Text(NSLocalizedString("Jump_Navigation_Safety_Settings", comment: "安全设置"))
                }

                // 第二个section：路径规划
                Section {
                    // 选择起点 - 使用Button和sheet
                    Button(action: {
                        showingStartPointSelector = true
                    }) {
                        HStack {
                            Text(NSLocalizedString("Jump_Navigation_Start_Point", comment: ""))
                                .foregroundColor(.blue)
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            Spacer()
                            Text(getSystemName(startPointId))
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    // 显示已添加的路径点
                    ForEach(Array(waypointIds.enumerated()), id: \.element) { index, waypointId in
                        HStack {
                            Text(
                                String(
                                    format: NSLocalizedString(
                                        "Jump_Navigation_Waypoint", comment: ""), index + 1)
                            )
                            .foregroundColor(.green)
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)

                            Spacer()

                            Text(getSystemName(waypointId))
                                .foregroundColor(.primary)

                            Button(action: {
                                if let idx = waypointIds.firstIndex(of: waypointId) {
                                    waypointIds.remove(at: idx)
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    // 添加路径点 - 仅在已选择起点时显示
                    if startPointId != nil {
                        Button(action: {
                            showingWaypointSelector = true
                        }) {
                            HStack {
                                Text(NSLocalizedString("Jump_Navigation_Add_Waypoint", comment: ""))
                                    .foregroundColor(.blue)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Jump_Navigation_Route_Planning", comment: ""))
                }

                // 第三个section：安全规避
                Section {
                    // 显示已添加的规避星系
                    ForEach(avoidSystemIds, id: \.self) { systemId in
                        HStack {
                            Text(NSLocalizedString("Jump_Navigation_Avoid", comment: ""))
                                .foregroundColor(.red)
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)

                            Spacer()

                            Text(getSystemName(systemId))
                                .foregroundColor(.primary)

                            Button(action: {
                                if let idx = avoidSystemIds.firstIndex(of: systemId) {
                                    avoidSystemIds.remove(at: idx)
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    // 添加规避星系
                    Button(action: {
                        showingAvoidSystemSelector = true
                    }) {
                        HStack {
                            Text(NSLocalizedString("Jump_Navigation_Add_Avoid", comment: ""))
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Jump_Navigation_Safety_Avoidance", comment: ""))
                }
            }

            // 底部寻路计算按钮
            Button(action: {
                calculatePath()
            }) {
                HStack {
                    if progressMessage
                        == NSLocalizedString("Jump_Navigation_Calculating", comment: "")
                    {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 8)
                    }
                    Text(NSLocalizedString("Jump_Navigation_Calculate", comment: ""))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isPathCalculationEnabled ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(
                !isPathCalculationEnabled
                    || progressMessage
                        == NSLocalizedString("Jump_Navigation_Calculating", comment: "")
            )
            .padding()
        }
    }

    // 计算按钮是否可用
    private var isPathCalculationEnabled: Bool {
        // 如果正在计算中，按钮不可用
        if isCalculating {
            return false
        }

        // 检查飞船选择
        guard selectedShip != 0 else {
            // Logger.info("未选择飞船")
            return false
        }

        // 检查起点选择
        guard startPointId != nil else {
            // Logger.info("未选择起点")
            return false
        }

        // 检查路径点
        guard !waypointIds.isEmpty else {
            // Logger.info("未添加路径点")
            return false
        }

        // Logger.info("所有条件满足：selectedShip=\(selectedShip), startPointId=\(String(describing: startPointId)), waypointIds=\(waypointIds)")
        return true
    }

    // 寻路计算函数
    private func calculatePath() {
        Logger.info("开始寻路计算")

        // 设置计算状态
        isCalculating = true

        // 显示计算中的提示，但不使用进度条UI
        progressMessage = NSLocalizedString("Jump_Navigation_Calculating", comment: "")

        // 获取所选飞船的type_id
        let shipTypeId = selectedShip
        Logger.info("所选飞船ID: \(shipTypeId)")

        // 获取星系ID映射（星系名称到ID的映射）
        var systemNameToIdMap: [String: Int] = [:]

        // 在后台线程加载星系ID
        Task {
            Logger.info("开始加载所有可跳跃星系")

            // 获取所有入侵星系（如果需要）
            var incursionSystems: [Int] = []
            if avoidIncursionSystems {
                do {
                    Logger.info("正在获取入侵星系数据...")
                    let incursions = try await IncursionsAPI.shared.fetchIncursions()
                    for incursion in incursions {
                        incursionSystems.append(contentsOf: incursion.infestedSolarSystems)
                    }
                    Logger.info("成功获取入侵星系数据，共 \(incursionSystems.count) 个受影响星系")

                    // 检查起点和终点是否在入侵区域内
                    var routePointsInIncursion: [Int] = []

                    if let startId = startPointId, incursionSystems.contains(startId) {
                        routePointsInIncursion.append(startId)
                    }

                    for waypointId in waypointIds {
                        if incursionSystems.contains(waypointId) {
                            routePointsInIncursion.append(waypointId)
                        }
                    }

                    if !routePointsInIncursion.isEmpty {
                        Logger.info("注意：您的路径中包含 \(routePointsInIncursion.count) 个入侵星系：")
                        for systemId in routePointsInIncursion {
                            Logger.info("  • \(getSystemName(systemId)) (ID: \(systemId))")
                        }
                        Logger.info("这些星系将不会被规避")
                    }
                } catch {
                    Logger.error("获取入侵星系数据失败: \(error.localizedDescription)")
                    // 使用空数组继续，不会避开任何入侵星系
                }
            }

            // 使用JumpNavigationHandler获取所有可跳跃星系
            let allSystems = JumpNavigationHandler.getAllJumpableSystems(
                databaseManager: self.databaseManager)
            Logger.info("加载完成，总共加载了 \(allSystems.count) 个可跳跃星系")

            // 创建名称到ID的映射
            for system in allSystems {
                systemNameToIdMap[system.name] = system.id
            }

            // 获取起点和路径点的ID
            let startSystemId: Int? = self.startPointId
            var waypointIds: [Int] = []

            for waypoint in self.waypointIds {
                if let id = systemNameToIdMap[self.getSystemName(waypoint)] {
                    waypointIds.append(id)
                }
            }

            // 获取规避星系的ID
            var avoidSystemIds: [Int] = []
            for avoidSystem in self.avoidSystemIds {
                if let id = systemNameToIdMap[self.getSystemName(avoidSystem)] {
                    avoidSystemIds.append(id)
                }
            }

            // 在主线程中记录数据
            await MainActor.run {
                // 记录参数信息
                Logger.info("寻路计算参数准备完成：")
                Logger.info("飞船ID: \(shipTypeId)")
                Logger.info("跳跃技能等级: \(self.JDCLv)")
                Logger.info("避开入侵星系: \(self.avoidIncursionSystems)")

                if self.avoidIncursionSystems {
                    Logger.info("入侵星系数量: \(incursionSystems.count)")
                }

                if let startId = startSystemId {
                    Logger.info("起点星系ID: \(startId), 名称: \(self.getSystemName(startId))")
                    Logger.info(
                        "路径点: \(waypointIds.map { "\($0)(\(self.getSystemName($0)))" }.joined(separator: ", "))"
                    )
                } else {
                    Logger.error("起点星系ID无效")
                }

                // 如果有规避星系，也记录下来
                if !avoidSystemIds.isEmpty {
                    Logger.info(
                        "避开星系: \(avoidSystemIds.map { "\($0)(\(self.getSystemName($0)))" }.joined(separator: ", "))"
                    )
                } else {
                    Logger.info("没有手动规避星系")
                }

                // 执行实际路径计算
                if let startId = startSystemId {
                    self.performPathFinding(
                        startSystemId: startId,
                        waypointIds: waypointIds,
                        shipTypeId: shipTypeId,
                        skillLevel: self.JDCLv,
                        avoidSystems: avoidSystemIds,
                        avoidIncursions: self.avoidIncursionSystems,
                        incursionSystems: incursionSystems
                    )
                } else {
                    Logger.error("无法计算路径：起点ID无效")
                    self.isCalculating = false
                }
            }
        }
    }

    // 执行路径寻找
    private func performPathFinding(
        startSystemId: Int,
        waypointIds: [Int],
        shipTypeId: Int,
        skillLevel: Int,
        avoidSystems: [Int],
        avoidIncursions: Bool,
        incursionSystems: [Int] = []
    ) {
        Logger.info("开始执行A*寻路计算")

        // 在后台线程执行路径寻找
        DispatchQueue.global(qos: .userInitiated).async {
            // 初始化路径寻找器
            let pathFinder = JumpPathFinder(databaseManager: self.databaseManager)
            Logger.info("初始化路径寻找器完成")

            // 执行A*寻路
            Logger.info("开始从 \(startSystemId) 到 \(waypointIds) 的路径计算")

            // 传递入侵星系列表到路径寻找器
            let results = pathFinder.findPath(
                from: startSystemId,
                to: waypointIds,
                shipTypeId: shipTypeId,
                skillLevel: skillLevel,
                avoidSystems: avoidSystems,
                avoidIncursions: avoidIncursions,
                incursionSystems: incursionSystems
            )
            Logger.info("路径计算完成，获得 \(results.count) 个路径段")

            // 获取星系ID到名称的映射，用于显示路径信息
            Logger.info("加载星系名称和安全等级信息")
            let systems = JumpNavigationHandler.getAllJumpableSystems(
                databaseManager: self.databaseManager)
            var systemIdToName: [Int: String] = [:]
            var systemIdToSecurity: [Int: Double] = [:]

            for system in systems {
                systemIdToName[system.id] = system.name
                systemIdToSecurity[system.id] = system.security
            }

            // 确保有英文名称映射
            var systemIdToEnName: [Int: String] = [:]
            if self.systemIdToEnName.isEmpty {
                Logger.info("获取英文名称映射")
                systemIdToEnName = JumpSystemsCache.shared.systemIdToEnName
            } else {
                systemIdToEnName = self.systemIdToEnName
            }

            // 在主线程更新UI
            DispatchQueue.main.async {
                Logger.info("路径计算完成，更新UI显示结果")

                // 记录每个路径段的详细信息
                for (index, result) in results.enumerated() {
                    Logger.info("路径段 \(index+1):")
                    Logger.info("  跳跃次数: \(result.path.count - 1)")
                    Logger.info("  总距离: \(result.totalDistance)光年")
                    Logger.info(
                        "  星系路径: \(result.path.map { "\($0)(\(systemIdToName[$0] ?? "未知"))" }.joined(separator: " -> "))"
                    )
                }

                self.pathResults = results
                self.systemIdToName = systemIdToName
                self.systemIdToSecurity = systemIdToSecurity
                self.systemIdToEnName = systemIdToEnName
                self.showingPathResults = true
                self.progressMessage = ""
                self.isCalculating = false
                Logger.info("路径结果已准备好显示")
            }
        }
    }

    private func checkAndInitializeJumpMap() {
        Logger.info("开始检查跳跃地图是否需要初始化")
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let jumpMapFile = documentsPath.appendingPathComponent("jump_map/jump_map.json")

        // 获取当前应用版本
        let currentAppVersion = AppConfiguration.Version.fullVersion
        // 从UserDefaults获取保存的版本
        let savedVersion = UserDefaults.standard.string(forKey: "jump_map_app_version")

        let needsRecalculation =
            !fileManager.fileExists(atPath: jumpMapFile.path) || savedVersion == nil
            || savedVersion != currentAppVersion

        if needsRecalculation {
            Logger.info(
                "需要初始化跳跃地图：文件存在状态=\(fileManager.fileExists(atPath: jumpMapFile.path))，保存的版本=\(savedVersion ?? "nil")，当前版本=\(currentAppVersion)"
            )
            isLoading = true
            progressMessage = NSLocalizedString(
                "Jump_Navigation_Calculating_Jump_Distance", comment: "")
            progressValue = 0.0
            loadingState = .processing

            // 使用带进度回调的方法
            DispatchQueue.global(qos: .userInitiated).async {
                Logger.info("开始处理跳跃导航数据")
                JumpNavigationHandler.processJumpNavigationData(
                    databaseManager: self.databaseManager,
                    progressUpdate: { message, progress in
                        // 在主线程更新UI
                        DispatchQueue.main.async {
                            self.progressMessage = message
                            self.progressValue = progress
                            // Logger.info("跳跃导航数据处理进度: \(Int(progress * 100))%, 消息: \(message)")

                            // 当进度为1.0时，表示处理完成
                            if progress >= 1.0 {
                                Logger.info("跳跃导航数据处理完成")
                                // 保存当前版本到UserDefaults
                                UserDefaults.standard.set(
                                    currentAppVersion, forKey: "jump_map_app_version")
                                self.loadingState = .complete
                            }
                        }
                    }
                )
            }
        } else {
            Logger.info(
                "\(jumpMapFile.path) 文件已存在，且应用版本(\(currentAppVersion))与保存的版本(\(savedVersion ?? ""))一致，无需重新计算"
            )
        }
    }

    private func recalculateJumpMap() {
        Logger.info("开始重新计算跳跃地图")
        // 如果已经在加载中，则不执行
        if isLoading {
            Logger.info("当前正在加载中，取消重新计算")
            return
        }

        // 开始加载
        isLoading = true
        progressMessage = NSLocalizedString("Jump_Navigation_Preparing_Jump_Data", comment: "")
        progressValue = 0.0
        loadingState = .processing

        // 删除旧的json文件
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let jumpMapFile = documentsPath.appendingPathComponent("jump_map/jump_map.json")

        if fileManager.fileExists(atPath: jumpMapFile.path) {
            do {
                try fileManager.removeItem(at: jumpMapFile)
                Logger.info("已删除旧的jump_map.json文件")
            } catch {
                Logger.error("删除旧的jump_map.json文件失败: \(error.localizedDescription)")
            }
        }

        // 获取当前应用版本
        let currentAppVersion = AppConfiguration.Version.fullVersion

        // 使用带进度回调的方法
        DispatchQueue.global(qos: .userInitiated).async {
            Logger.info("开始重新处理跳跃导航数据")
            JumpNavigationHandler.processJumpNavigationData(
                databaseManager: self.databaseManager,
                progressUpdate: { message, progress in
                    // 在主线程更新UI
                    DispatchQueue.main.async {
                        self.progressMessage = message
                        self.progressValue = progress
                        // Logger.info("重新计算进度: \(Int(progress * 100))%, 消息: \(message)")

                        // 当进度为1.0时，表示处理完成
                        if progress >= 1.0 {
                            Logger.info("重新计算跳跃导航数据完成")
                            // 保存当前版本到UserDefaults
                            UserDefaults.standard.set(
                                currentAppVersion, forKey: "jump_map_app_version")
                            self.loadingState = .complete
                        }
                    }
                }
            )
        }
    }

    // 合并多个路径结果为一个完整的路径结果
    private func mergePathResults(_ results: [PathResult]) -> PathResult {
        Logger.info("开始合并 \(results.count) 个路径结果")

        // 合并所有路径
        var mergedPath: [Int] = []
        var mergedSegments: [PathSegment] = []
        var totalDistance: Double = 0.0

        // 遍历每个路径结果
        for (index, result) in results.enumerated() {
            // 添加路径点
            if index == 0 {
                // 第一个路径，添加所有点
                mergedPath.append(contentsOf: result.path)
                Logger.info("添加第一个路径的所有点: \(result.path.count) 个")
            } else {
                // 后续路径，跳过第一个点（因为它是前一个路径的终点）
                mergedPath.append(contentsOf: result.path.dropFirst())
                Logger.info("添加第 \(index+1) 个路径的点(跳过第一个): \(result.path.count-1) 个")
            }

            // 添加路径段
            mergedSegments.append(contentsOf: result.segments)
            Logger.info("添加第 \(index+1) 个路径的 \(result.segments.count) 个路径段")

            // 累加总距离
            totalDistance += result.totalDistance
            Logger.info("累计总距离: \(totalDistance) 光年")
        }

        // 创建合并后的路径结果
        let mergedResult = PathResult(
            path: mergedPath,
            segments: mergedSegments,
            totalDistance: totalDistance
        )

        Logger.info(
            "路径合并完成: 总长度 \(mergedPath.count) 个星系, \(mergedSegments.count) 个路径段, 总距离 \(totalDistance) 光年"
        )
        return mergedResult
    }

    // 计算最大跳跃距离
    private func calculateMaxJumpRange() -> Double {
        // 获取所选飞船的type_id
        guard selectedShip != 0 else {
            Logger.info("未选择飞船，最大跳跃距离为0")
            return 0
        }

        // 从数据库查询飞船基础跳跃范围 (attribute_id 867 表示跳跃范围)
        var baseRange: Double = 5.0  // 默认值为5光年

        // 尝试从数据库获取实际跳跃范围
        let query = """
                SELECT value FROM typeAttributes 
                WHERE type_id = \(selectedShip) AND attribute_id = 867
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            if let row = rows.first, let jumpRange = row["value"] as? Double {
                baseRange = jumpRange
                Logger.info("从数据库获取到飞船(ID: \(selectedShip))基础跳跃范围: \(baseRange)光年")
            } else {
                Logger.info("未找到飞船(ID: \(selectedShip))的基础跳跃范围，使用默认值: \(baseRange)光年")
            }
        } else {
            Logger.error("查询飞船跳跃范围失败，使用默认值: \(baseRange)光年")
        }

        // 技能等级影响 (每级增加20%)
        let skillMultiplier = 1.0 + Double(JDCLv) * 0.2
        let finalRange = baseRange * skillMultiplier

        Logger.info("技能等级: \(JDCLv), 技能乘数: \(skillMultiplier)")
        Logger.info("计算后的最终跳跃范围: \(finalRange)光年")

        return finalRange
    }

    // 获取飞船名称
    private func getShipName() -> String {
        guard selectedShip != 0 else {
            return NSLocalizedString("Jump_Navigation_Select_Ship", comment: "")
        }

        // 遍历所有船只找到匹配的ID
        for (_, shipGroup) in ships {
            if let ship = shipGroup.first(where: { $0.id == selectedShip }) {
                return "\(ship.name) (\(ship.enName))"
            }
        }

        return NSLocalizedString("Jump_Navigation_Select_Ship", comment: "")
    }

    // 获取星系名称
    private func getSystemName(_ id: Int?) -> String {
        guard let id = id else {
            return NSLocalizedString("Jump_Navigation_Select_Start", comment: "")
        }
        return systemIdToName[id] ?? NSLocalizedString("Jump_Navigation_Select_Start", comment: "")
    }

    // 加载飞船数据
    private static func loadShips(databaseManager: DatabaseManager) -> [Int: [Ship]] {
        Logger.info("加载跳跃飞船数据")
        var ships: [Int: [Ship]] = [:]

        // 查询所有可跳跃的飞船
        let query = """
            SELECT t.type_id, t.name, t.en_name, 
                               g.group_id, g.name as groupName, t.icon_filename 
                        FROM types t
                        JOIN groups g ON t.groupID  = g.group_id
                        WHERE t.published = 1 
                        AND g.categoryID  = 6  -- 飞船类别
                        AND EXISTS (
                            SELECT 1 FROM typeAttributes ta 
                            WHERE ta.type_id = t.type_id 
                            AND ta.attribute_id = 867  -- 跳跃范围属性
                        )
                        ORDER BY g.group_id, t.name
            """

        if case let .success(rows) = databaseManager.executeQuery(query) {
            for row in rows {
                guard let typeId = row["type_id"] as? Int,
                    let typeName = row["name"] as? String,
                    let typeNameEN = row["en_name"] as? String,
                    let groupId = row["group_id"] as? Int,
                    let groupName = row["groupName"] as? String,
                    let iconFileName = row["icon_filename"] as? String
                else {
                    Logger.error("加载飞船数据时字段缺失: \(row)")
                    continue
                }

                let ship = Ship(
                    id: typeId,
                    name: typeName,
                    enName: typeNameEN,
                    iconFilename: iconFileName,
                    groupId: groupId,
                    groupName: groupName
                )

                // 按群组ID分类
                if ships[groupId] == nil {
                    ships[groupId] = []
                }
                ships[groupId]?.append(ship)
            }

            Logger.info("已加载 \(ships.values.flatMap { $0 }.count) 艘跳跃飞船")
        } else {
            Logger.error("加载跳跃飞船数据失败")
        }

        return ships
    }
}

// 星系选择器Sheet
struct SystemSelectorSheet: View {
    let title: String
    let onSelect: (Int) -> Void  // 修改为接收星系ID
    let onCancel: () -> Void
    let currentSelection: Int?  // 修改为星系ID
    let onlyLowSec: Bool  // 添加新参数，控制是否只显示低安全等级星系

    @State private var searchText: String = ""
    @State private var systems: [(id: Int, name: String, security: Double, region: String)] = []
    @State private var selectedSystemId: Int?  // 修改为星系ID
    @State private var isLoading = true

    init(
        title: String,
        currentSelection: Int? = nil,
        onlyLowSec: Bool = false,  // 添加新参数，默认为false
        onSelect: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.currentSelection = currentSelection
        self.onlyLowSec = onlyLowSec
        _selectedSystemId = State(initialValue: currentSelection)
    }

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    Text(NSLocalizedString("Jump_Navigation_Loading_Systems", comment: ""))
                        .foregroundColor(.gray)
                } else {
                    List {
                        // 显示星系列表
                        ForEach(filteredSystems, id: \.id) { system in
                            Button(action: {
                                selectedSystemId = system.id
                                onSelect(system.id)
                            }) {
                                HStack {
                                    // 安全等级
                                    Text(formatSystemSecurity(system.security))
                                        .foregroundColor(getSecurityColor(system.security))
                                        .font(.system(.body, design: .monospaced))

                                    // 星系名称
                                    Text("\(system.name) / ")
                                        .foregroundColor(.primary)
                                        + Text(system.region)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    // 选中状态
                                    if selectedSystemId == system.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: NSLocalizedString("Main_Search", comment: "")
                    )
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(
                        NSLocalizedString("Main_Setting_Cancel", comment: ""),
                        action: {
                            onCancel()
                        })
                }
            }
            .onAppear {
                loadSystems()
            }
        }
    }

    // 过滤后的星系列表
    private var filteredSystems: [(id: Int, name: String, security: Double, region: String)] {
        if searchText.isEmpty {
            return systems
        } else {
            return systems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.name < $1.name }
        }
    }

    // 加载星系数据
    private func loadSystems() {
        isLoading = true

        // 使用全局缓存的星系数据
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedSystems = JumpSystemsCache.shared.jumpableSystems

            // 根据onlyLowSec参数过滤星系
            let filteredSystems =
                onlyLowSec ? loadedSystems.filter { $0.security < 0.5 } : loadedSystems

            // 在主线程更新UI
            DispatchQueue.main.async {
                systems = filteredSystems.sorted { $0.name < $1.name }
                isLoading = false
            }
        }
    }
}

// 自定义LoadingView，添加loadingText参数
struct CustomLoadingView: View {
    @Binding var loadingState: LoadingState
    let progress: Double
    let loadingText: String
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // 背景圆圈
                Circle()
                    .stroke(lineWidth: 4)
                    .opacity(0.3)
                    .foregroundColor(.gray)
                    .frame(width: 80, height: 80)

                // 进度圈
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .foregroundColor(.green)
                    .frame(width: 80, height: 80)
                    .rotationEffect(Angle(degrees: -90))

                // 进度文本
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.green)
            }

            // 加载文本
            Text(loadingText)
                .font(.headline)
        }
        .onChange(of: loadingState) { _, newState in
            if newState == .complete {
                onComplete()
            }
        }
    }
}

// 飞船选择器视图
struct ShipSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedShip: Int  // 修改为Int类型
    let ships: [Int: [Ship]]

    @State private var searchText = ""
    @State private var isSearchActive = false

    var filteredShips: [Int: [Ship]] {
        if searchText.isEmpty {
            return ships
        }

        var filtered: [Int: [Ship]] = [:]
        for (groupId, groupShips) in ships {
            let filteredGroupShips = groupShips.filter { ship in
                ship.name.localizedCaseInsensitiveContains(searchText)
            }
            if !filteredGroupShips.isEmpty {
                filtered[groupId] = filteredGroupShips
            }
        }
        return filtered
    }

    var body: some View {
        NavigationView {
            contentView
                .navigationTitle(NSLocalizedString("Jump_Navigation_Select_Ship", comment: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(
                            NSLocalizedString("Main_Setting_Cancel", comment: ""),
                            action: {
                                dismiss()
                            })
                    }
                }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if ships.isEmpty {
            VStack {
                Text(NSLocalizedString("Jump_Navigation_No_Jumpable_Ships", comment: ""))
                    .foregroundColor(.gray)
            }
        } else {
            shipListView
        }
    }

    @ViewBuilder
    private var shipListView: some View {
        List {
            ForEach(filteredShips.keys.sorted(), id: \.self) { groupId in
                if let groupShips = filteredShips[groupId] {
                    Section(header: Text(groupShips.first?.groupName ?? "Unknown Group")) {
                        ForEach(groupShips) { ship in
                            shipRow(ship)
                        }
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Search", comment: "")
        )
        .overlay {
            if searchText.isEmpty && isSearchActive {
                Button(action: {
                    isSearchActive = false
                }) {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                }
            }
        }
    }

    private func shipRow(_ ship: Ship) -> some View {
        Button(action: {
            selectedShip = ship.id
            dismiss()
        }) {
            HStack {
                // 使用IconManager加载飞船图标
                IconManager.shared.loadImage(for: ship.iconFilename)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)

                // 飞船名称
                Text(ship.name)
                    .foregroundColor(.primary)

                Spacer()

                // 选中标记
                if selectedShip == ship.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }
}
