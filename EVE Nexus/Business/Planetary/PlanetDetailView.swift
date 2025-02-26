import SwiftUI

struct PlanetDetailView: View {
    let characterId: Int
    let planetId: Int
    let planetName: String
    let lastUpdate: String
    @State private var planetDetail: PlanetaryDetail?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var typeNames: [Int: String] = [:]
    @State private var typeIcons: [Int: String] = [:]
    @State private var currentTime = Date()
    @State private var lastCycleCheck: Int = -1
    @State private var hasInitialized = false
    @State private var loadingTask: Task<Void, Never>?
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
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
                    ForEach(detail.pins, id: \.pinId) { pin in
                        if let extractor = pin.extractorDetails {
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
                 .listStyle(.insetGrouped)
            } else if isLoading {
                ProgressView()
            } else {
                Text(NSLocalizedString("Planet_Detail_No_Data", comment: ""))
            }
        }
        .navigationTitle(planetName)
        .task {
            if !hasInitialized {
                await startLoadingPlanetDetail()
                hasInitialized = true
            }
        }
        .refreshable {
            await startLoadingPlanetDetail(forceRefresh: true)
        }
        .onReceive(timer) { newTime in
            let shouldUpdate = shouldUpdateView(newTime: newTime)
            if shouldUpdate {
                currentTime = newTime
            }
        }
        .onDisappear {
            // 取消正在进行的任务
            loadingTask?.cancel()
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
    
    private func startLoadingPlanetDetail(forceRefresh: Bool = false) async {
        // 取消之前的任务
        loadingTask?.cancel()
        
        // 创建新任务
        loadingTask = Task {
            await loadPlanetDetail(forceRefresh: forceRefresh)
        }
        
        // 等待任务完成
        await loadingTask?.value
    }
    
    private func loadPlanetDetail(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        
        do {
            // 检查任务是否已取消
            if Task.isCancelled {
                isLoading = false
                return
            }
            
            planetDetail = try await CharacterPlanetaryAPI.fetchPlanetaryDetail(
                characterId: characterId,
                planetId: planetId,
                forceRefresh: forceRefresh
            )
            
            // 再次检查任务是否已取消
            if Task.isCancelled {
                isLoading = false
                return
            }
            
            var typeIds = Set<Int>()
            
            // 只收集提取器相关的类型ID
            planetDetail?.pins.forEach { pin in
                typeIds.insert(pin.typeId)
                if let productTypeId = pin.extractorDetails?.productTypeId {
                    typeIds.insert(productTypeId)
                }
            }
            
            if !typeIds.isEmpty {
                let typeIdsString = typeIds.map { String($0) }.joined(separator: ",")
                let query = """
                    SELECT type_id, name, icon_filename
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
                        }
                    }
                }
            }
            
        } catch {
            // 只有当任务没有被取消时，才设置错误
            if !Task.isCancelled && (error as? CancellationError) == nil {
                self.error = error
                Logger.error("加载行星详情失败: \(error.localizedDescription)")
            }
        }
        
        // 只有当任务没有被取消时，才更新加载状态
        if !Task.isCancelled {
            isLoading = false
        }
    }
    
    private func getTypeName(for typeId: Int) -> String {
        let query = "SELECT name FROM types WHERE type_id = ?"
        let result = DatabaseManager.shared.executeQuery(query, parameters: [typeId])
        
        if case .success(let rows) = result, let row = rows.first {
            return row["name"] as? String ?? "Null"
        }
        return "Null"
    }
} 
