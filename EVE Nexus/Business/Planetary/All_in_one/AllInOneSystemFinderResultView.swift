import SwiftUI

struct AllInOneSystemFinderResultView: View {
    let results: [AllInOneSystemResult]
    let selectedProducts: [SelectedProduct]
    
    @StateObject private var viewModel = AllInOneSystemFinderResultViewModel()
    
    var body: some View {
        List {
            // 提示信息
            if !results.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("AllInOne_SystemFinder_Result_Tip_1", comment: "以下星系可以支持您选择的所有产品进行单星球生产"))
                            .font(.footnote)
                        Text(NSLocalizedString("AllInOne_SystemFinder_Result_Tip_2", comment: "评分越高的星系拥有更多可用行星和更好的资源分布"))
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            
            if results.isEmpty {
                // 无结果提示
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.yellow)
                            .padding(.top, 20)
                        
                        Text(NSLocalizedString("AllInOne_SystemFinder_No_Results", comment: "没有找到能够支持所有选定产品的星系"))
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        
                        Text(NSLocalizedString("AllInOne_SystemFinder_No_Results_Tips", comment: "请考虑以下调整方案:\n• 减少选择的产品数量\n• 选择其他星域或主权\n• 选择兼容性更好的产品组合"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            } else {
                // 结果列表
                ForEach(results.prefix(20)) { result in
                    SystemResultSection(
                        result: result,
                        selectedProducts: selectedProducts,
                        viewModel: viewModel
                    )
                }
            }
        }
        .navigationTitle(NSLocalizedString("AllInOne_SystemFinder_Results", comment: "系统查找结果"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let systemIds = results.map { $0.systemId }
            viewModel.loadSovereigntyData(forSystemIds: systemIds)
        }
    }
}

// 单个星系结果区域
struct SystemResultSection: View {
    let result: AllInOneSystemResult
    let selectedProducts: [SelectedProduct]
    let viewModel: AllInOneSystemFinderResultViewModel
    
    var body: some View {
        Section {
            // 星系基本信息
            SystemHeaderRow(result: result, viewModel: viewModel)
            
            // 产品支持信息
            ProductSupportSection(result: result, selectedProducts: selectedProducts)
            
            // 行星类型分布
            PlanetDistributionSection(result: result, selectedProducts: selectedProducts)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

// 星系头部信息行
struct SystemHeaderRow: View {
    let result: AllInOneSystemResult
    let viewModel: AllInOneSystemFinderResultViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // 主权图标
            if viewModel.isLoadingIconForSystem(result.systemId) {
                ProgressView()
                    .frame(width: 36, height: 36)
            } else if let icon = viewModel.getIconForSystem(result.systemId) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .cornerRadius(6)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：安全等级和星系名称
                HStack(spacing: 4) {
                    Text(formatSystemSecurity(result.security))
                        .foregroundColor(getSecurityColor(result.security))
                        .font(.system(.body, design: .monospaced))
                    Text(result.systemName)
                        .fontWeight(.medium)
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = result.systemName
                            } label: {
                                Label(NSLocalizedString("Misc_Copy", comment: ""), systemImage: "doc.on.doc")
                            }
                        }
                    Text("（\(result.regionName)）")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // 第二行：联盟/派系名称
                if let ownerName = viewModel.getOwnerNameForSystem(result.systemId) {
                    Text(ownerName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 第三行：评分
                HStack {
                    Text(NSLocalizedString("AllInOne_SystemFinder_Score", comment: "评分"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f", result.score))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
            
            Spacer()
        }
    }
}

// 产品支持区域
struct ProductSupportSection: View {
    let result: AllInOneSystemResult
    let selectedProducts: [SelectedProduct]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("AllInOne_SystemFinder_Product_Support", comment: "产品支持情况"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            ForEach(selectedProducts, id: \.id) { product in
                if let supportInfo = result.productSupport[product.id] {
                    ProductSupportRow(product: product, supportInfo: supportInfo)
                }
            }
        }
    }
}

// 单个产品支持行
struct ProductSupportRow: View {
    let product: SelectedProduct
    let supportInfo: ProductSupportInfo
    
    var body: some View {
        HStack(spacing: 8) {
            // 产品图标
            Image(uiImage: IconManager.shared.loadUIImage(for: product.iconFileName))
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                // 产品名称和支持状态
                HStack {
                    Text(product.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if supportInfo.canSupport {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                // 可用行星数量
                if supportInfo.canSupport {
                    Text(String(format: NSLocalizedString("AllInOne_SystemFinder_Available_Planets", comment: "可用行星: %d 颗"), supportInfo.availablePlanetCount))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// 行星分布区域
struct PlanetDistributionSection: View {
    let result: AllInOneSystemResult
    let selectedProducts: [SelectedProduct]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("AllInOne_SystemFinder_Planet_Distribution", comment: "行星分布"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            ForEach(result.planetTypeSummary, id: \.typeId) { planetSummary in
                PlanetTypeRow(planetSummary: planetSummary, selectedProducts: selectedProducts)
            }
        }
    }
}

// 单个行星类型行
struct PlanetTypeRow: View {
    let planetSummary: PlanetTypeSummary
    let selectedProducts: [SelectedProduct]
    
    var body: some View {
        HStack(spacing: 8) {
            // 行星类型图标
            Image(uiImage: IconManager.shared.loadUIImage(for: planetSummary.iconFileName))
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(planetSummary.typeName)
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Text(String(format: NSLocalizedString("AllInOne_SystemFinder_Planet_Count", comment: "%d 颗"), planetSummary.count))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // 显示使用该行星类型的具体产品
                if !planetSummary.usedByProducts.isEmpty {
                    let productNames = planetSummary.usedByProducts.compactMap { productId in
                        selectedProducts.first { $0.id == productId }?.name
                    }.joined(separator: ", ")
                    
                    if !productNames.isEmpty {
                        Text(NSLocalizedString("AllInOne_SystemFinder_Used_By_Products", comment: "") + "\(productNames)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// 结果视图模型
@MainActor
class AllInOneSystemFinderResultViewModel: ObservableObject {
    @Published var sovereigntyData: [SovereigntyData] = []
    @Published var isLoadingSovereignty: Bool = false
    @Published var allianceIcons: [Int: Image] = [:]
    @Published var factionIcons: [Int: Image] = [:]
    @Published var allianceNames: [Int: String] = [:]
    @Published var factionNames: [Int: String] = [:]
    @Published var loadingSystemIcons: Set<Int> = []
    
    private var allianceToSystems: [Int: [Int]] = [:]
    private var factionToSystems: [Int: [Int]] = [:]
    private var loadingTasks: [Int: Task<Void, Never>] = [:]
    
    func loadSovereigntyData(forSystemIds systemIds: [Int]) {
        Task {
            isLoadingSovereignty = true
            
            do {
                let data = try await SovereigntyDataAPI.shared.fetchSovereigntyData(forceRefresh: false)
                sovereigntyData = data
                setupSovereigntyMapping(systemIds: systemIds)
                await loadAllIcons()
                isLoadingSovereignty = false
            } catch {
                Logger.error("无法获取主权数据: \(error)")
                isLoadingSovereignty = false
            }
        }
    }
    
    private func setupSovereigntyMapping(systemIds: [Int]) {
        allianceToSystems.removeAll()
        factionToSystems.removeAll()
        
        for systemId in systemIds {
            if let systemData = sovereigntyData.first(where: { $0.systemId == systemId }) {
                loadingSystemIcons.insert(systemId)
                
                if let allianceId = systemData.allianceId {
                    allianceToSystems[allianceId, default: []].append(systemId)
                } else if let factionId = systemData.factionId {
                    factionToSystems[factionId, default: []].append(systemId)
                } else {
                    loadingSystemIcons.remove(systemId)
                }
            }
        }
    }
    
    private func loadAllIcons() async {
        // 加载联盟图标
        for (allianceId, systems) in allianceToSystems {
            let task = Task {
                do {
                    if let allianceInfo = try? await AllianceAPI.shared.fetchAllianceInfo(allianceId: allianceId) {
                        await MainActor.run {
                            allianceNames[allianceId] = allianceInfo.name
                        }
                    }
                    
                    let uiImage = try await AllianceAPI.shared.fetchAllianceLogo(allianceID: allianceId, size: 64)
                    await MainActor.run {
                        allianceIcons[allianceId] = Image(uiImage: uiImage)
                        for systemId in systems {
                            loadingSystemIcons.remove(systemId)
                        }
                    }
                } catch {
                    await MainActor.run {
                        for systemId in systems {
                            loadingSystemIcons.remove(systemId)
                        }
                    }
                }
            }
            loadingTasks[allianceId] = task
        }
        
        // 加载派系图标
        for (factionId, systems) in factionToSystems {
            let task = Task {
                let query = "SELECT iconName, name FROM factions WHERE id = ?"
                if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [factionId]),
                   let row = rows.first,
                   let iconName = row["iconName"] as? String {
                    
                    let icon = IconManager.shared.loadImage(for: iconName)
                    let factionName = row["name"] as? String
                    
                    await MainActor.run {
                        factionIcons[factionId] = icon
                        if let name = factionName {
                            factionNames[factionId] = name
                        }
                        for systemId in systems {
                            loadingSystemIcons.remove(systemId)
                        }
                    }
                }
            }
            loadingTasks[factionId] = task
        }
        
        // 等待所有任务完成
        for task in loadingTasks.values {
            _ = await task.value
        }
    }
    
    func getSovereigntyForSystem(_ systemId: Int) -> SovereigntyData? {
        return sovereigntyData.first(where: { $0.systemId == systemId })
    }
    
    func isLoadingIconForSystem(_ systemId: Int) -> Bool {
        return loadingSystemIcons.contains(systemId)
    }
    
    func getIconForSystem(_ systemId: Int) -> Image? {
        if let sovereignty = getSovereigntyForSystem(systemId) {
            if let allianceId = sovereignty.allianceId {
                return allianceIcons[allianceId]
            } else if let factionId = sovereignty.factionId {
                return factionIcons[factionId]
            }
        }
        return nil
    }
    
    func getOwnerNameForSystem(_ systemId: Int) -> String? {
        if let sovereignty = getSovereigntyForSystem(systemId) {
            if let allianceId = sovereignty.allianceId {
                return allianceNames[allianceId]
            } else if let factionId = sovereignty.factionId {
                return factionNames[factionId]
            }
        }
        return nil
    }
    
    deinit {
        loadingTasks.values.forEach { $0.cancel() }
    }
}
