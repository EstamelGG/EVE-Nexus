import SwiftUI

struct PIAllInOneSystemFinderMainView: View {
    let characterId: Int?
    
    @StateObject private var databaseManager = DatabaseManager.shared
    @State private var selectedProducts: [SelectedProduct] = []
    @State private var selectedRegionID: Int? = nil
    @State private var selectedRegionName: String? = nil
    @State private var selectedSovereigntyID: Int? = nil
    @State private var selectedSovereigntyName: String? = nil
    @State private var showProductSelector = false
    @State private var showRegionSelector = false
    @State private var showSovereigntySelector = false
    @State private var isCalculating = false
    @State private var searchResults: [AllInOneSystemResult] = []
    @State private var showResults = false
    
    private let singlePlanetAnalyzer = SinglePlanetProductAnalyzer()
    private let systemCalculator = AllInOneSystemCalculator()
    
    // 判断是否可以开始计算
    private var isCalculationEnabled: Bool {
        // 如果正在计算中，按钮不可用
        if isCalculating {
            return false
        }
        
        // 必须选择至少一个产品
        guard !selectedProducts.isEmpty else {
            return false
        }
        
        // 必须选择星域或主权势力
        guard selectedRegionID != nil || selectedSovereigntyID != nil else {
            return false
        }
        
        return true
    }
    
    var body: some View {
        VStack {
            List {
                Section(
                    header: Text(NSLocalizedString("Main_Planetary_Filter_Conditions", comment: "筛选条件"))
                ) {
                    // 选择行星产品
                    Button {
                        showProductSelector = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("AllInOne_SystemFinder_Select_Products", comment: "选择产品"))
                                    .foregroundColor(.primary)
                                Text(NSLocalizedString("AllInOne_SystemFinder_Products_Description", comment: "选择要进行单星球生产的产品"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedProducts.isEmpty {
                                Text(NSLocalizedString("Main_Planetary_Not_Selected", comment: "未选择"))
                                    .foregroundColor(.gray)
                            } else {
                                Text(String(format: NSLocalizedString("AllInOne_SystemFinder_Products_Count", comment: "已选择 %d 个"), selectedProducts.count))
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // 选择星域
                    Button {
                        showRegionSelector = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Main_Planetary_Select_Region", comment: "选择星域"))
                                    .foregroundColor(.primary)
                                Text(NSLocalizedString("Planetary_Region_Description", comment: "要在哪个星域生产"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let regionName = selectedRegionName {
                                Text(regionName)
                                    .foregroundColor(.gray)
                            } else {
                                Text(NSLocalizedString("Main_Planetary_Not_Selected", comment: "未选择"))
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // 选择主权
                    Button {
                        showSovereigntySelector = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("Main_Planetary_Select_Sovereignty", comment: "选择主权"))
                                    .foregroundColor(.primary)
                                Text(NSLocalizedString("Planetary_Sovereignty_Description", comment: "要在哪个主权辖区生产"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let sovereigntyName = selectedSovereigntyName {
                                Text(sovereigntyName)
                                    .foregroundColor(.gray)
                            } else {
                                Text(NSLocalizedString("Main_Planetary_Not_Selected", comment: "未选择"))
                                    .foregroundColor(.gray)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                
                // 功能描述（当没有结果且没有选择产品时显示）
                if searchResults.isEmpty && !isCalculating && selectedProducts.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(NSLocalizedString("AllInOne_SystemFinder_Description_Title", comment: "查找单球生产星系"))
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(NSLocalizedString("AllInOne_SystemFinder_Description_Text", comment: "功能描述"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                // 已选择的产品列表
                if !selectedProducts.isEmpty {
                    Section(
                        header: Text(NSLocalizedString("AllInOne_SystemFinder_Selected_Products", comment: "已选择的产品"))
                    ) {
                        ForEach(selectedProducts) { product in
                            SelectedProductRow(
                                product: product,
                                onRemove: {
                                    selectedProducts.removeAll { $0.id == product.id }
                                }
                            )
                        }
                    }
                }
            }
            
            // 底部计算按钮
            Button(action: {
                calculateAllInOneSystems()
            }) {
                HStack {
                    if isCalculating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 8)
                    }
                    Text(NSLocalizedString("AllInOne_SystemFinder_Calculate", comment: "开始计算"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isCalculationEnabled ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!isCalculationEnabled || isCalculating)
            .padding()
        }
        .navigationTitle(NSLocalizedString("AllInOne_SystemFinder_Title", comment: "查找 All-in-One 星系"))
        .sheet(isPresented: $showProductSelector) {
            NavigationView {
                AllInOneProductSelectorView(
                    databaseManager: databaseManager,
                    selectedProducts: $selectedProducts,
                    singlePlanetAnalyzer: singlePlanetAnalyzer
                )
            }
        }
        .sheet(isPresented: $showRegionSelector) {
            NavigationView {
                RegionSearchView(
                    databaseManager: databaseManager,
                    selectedRegionID: $selectedRegionID,
                    selectedRegionName: $selectedRegionName
                )
            }
        }
        .sheet(isPresented: $showSovereigntySelector) {
            NavigationView {
                SovereigntySelectorView(
                    databaseManager: databaseManager,
                    selectedSovereigntyID: $selectedSovereigntyID,
                    selectedSovereigntyName: $selectedSovereigntyName
                )
            }
        }
        .navigationDestination(isPresented: $showResults) {
            AllInOneSystemFinderResultView(
                results: searchResults,
                selectedProducts: selectedProducts
            )
        }
    }
    
    private func calculateAllInOneSystems() {
        isCalculating = true
        searchResults = []
        showResults = false
        
        Task {
            do {
                Logger.info("开始计算 All-in-One 星系，选择了 \(selectedProducts.count) 个产品")
                
                // 分析多产品需求
                let multiProductRequirement = systemCalculator.analyzeMultiProductRequirements(
                    selectedProducts: selectedProducts
                )
                
                // 筛选符合条件的星系
                var filteredSystems = Set<Int>()
                
                // 如果选择了星域，筛选该星域内的星系
                if let regionId = selectedRegionID {
                    let query = "SELECT solarsystem_id FROM universe WHERE region_id = ?"
                    if case let .success(rows) = databaseManager.executeQuery(query, parameters: [regionId]) {
                        let systemsInRegion = Set(rows.compactMap { row in
                            row["solarsystem_id"] as? Int
                        })
                        filteredSystems = systemsInRegion
                    }
                }
                
                // 如果选择了主权，进一步筛选该主权下的星系
                if let sovereigntyId = selectedSovereigntyID {
                    let sovereigntyData = try await SovereigntyDataAPI.shared.fetchSovereigntyData(forceRefresh: false)
                    let systemsUnderSovereignty = Set(sovereigntyData.compactMap { data -> Int? in
                        if data.allianceId == sovereigntyId || data.factionId == sovereigntyId {
                            return data.systemId
                        }
                        return nil
                    })
                    
                    if filteredSystems.isEmpty {
                        filteredSystems = systemsUnderSovereignty
                    } else {
                        filteredSystems = filteredSystems.intersection(systemsUnderSovereignty)
                    }
                }
                
                // 如果没有筛选条件，使用所有星系（这种情况不应该发生，因为UI限制了）
                if filteredSystems.isEmpty {
                    Logger.warning("没有找到符合筛选条件的星系")
                    await MainActor.run {
                        isCalculating = false
                    }
                    return
                }
                
                Logger.info("筛选后有 \(filteredSystems.count) 个星系需要评估")
                
                // 计算星系评分
                let results = systemCalculator.calculateSystemScores(
                    for: filteredSystems,
                    multiProductRequirement: multiProductRequirement
                )
                
                Logger.info("计算完成，找到 \(results.count) 个符合条件的星系")
                
                // 更新UI
                await MainActor.run {
                    searchResults = Array(results.prefix(20)) // 限制结果数量
                    showResults = true
                    isCalculating = false
                }
                
            } catch {
                Logger.error("计算 All-in-One 星系失败：\(error)")
                await MainActor.run {
                    isCalculating = false
                }
            }
        }
    }
}

// 已选择产品行
struct SelectedProductRow: View {
    let product: SelectedProduct
    let onRemove: () -> Void
    
    var body: some View {
        HStack {
            // 产品图标
            Image(uiImage: IconManager.shared.loadUIImage(for: product.iconFileName))
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 4) {
                // 产品名称
                Text(product.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // 支持的行星类型
                Text(String(format: NSLocalizedString("All_in_One_Compatible_Planets", comment: "支持行星: %@"), product.compatiblePlanetTypes.map { $0.name }.joined(separator: ", ")))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // P等级标识
            Text("P\(product.productLevel)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(levelColor(for: product.productLevel))
                .cornerRadius(4)
            
            // 删除按钮
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func levelColor(for level: Int) -> Color {
        switch level {
        case 1: return .blue
        case 2: return .green
        case 3: return .orange
        case 4: return .red
        default: return .gray
        }
    }
}

// 产品选择器视图
struct AllInOneProductSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @Binding var selectedProducts: [SelectedProduct]
    let singlePlanetAnalyzer: SinglePlanetProductAnalyzer
    
    @State private var allSinglePlanetProducts: [AllInOneSinglePlanetProductResult] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var isSearchActive = false
    @Environment(\.dismiss) private var dismiss
    
    // 过滤后的产品
    private var filteredProducts: [AllInOneSinglePlanetProductResult] {
        if searchText.isEmpty {
            return allSinglePlanetProducts
        } else {
            return allSinglePlanetProducts.filter { product in
                product.productName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // 按产品等级分组
    private var groupedProducts: [Int: [AllInOneSinglePlanetProductResult]] {
        Dictionary(grouping: filteredProducts) { $0.productLevel }
    }
    
    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        .scaleEffect(0.8)
                    Text(NSLocalizedString("Misc_Loading", comment: "加载中"))
                        .foregroundColor(.blue)
                        .padding(.leading, 8)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                // 按产品等级分组显示（P4-P3-P2-P1顺序）
                ForEach([4, 3, 2, 1], id: \.self) { level in
                    if let products = groupedProducts[level], !products.isEmpty {
                        Section(header: Text("P\(level) (\(products.count) \(NSLocalizedString("Types", comment: "种类")))")) {
                            ForEach(products, id: \.productId) { product in
                                ProductSelectorRow(
                                    product: product,
                                    isSelected: selectedProducts.contains { $0.id == product.productId },
                                    onToggle: { toggleProduct(product) }
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("AllInOne_SystemFinder_Select_Products", comment: "选择产品"))
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "搜索")
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(NSLocalizedString("Misc_Cancel", comment: "取消")) {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Misc_Done", comment: "完成")) {
                    dismiss()
                }
            }
        }
        .onAppear {
            loadSinglePlanetProducts()
        }
    }
    
    private func loadSinglePlanetProducts() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let products = singlePlanetAnalyzer.getAllSinglePlanetProducts()
            
            DispatchQueue.main.async {
                allSinglePlanetProducts = products
                isLoading = false
            }
        }
    }
    
    private func toggleProduct(_ product: AllInOneSinglePlanetProductResult) {
        if let index = selectedProducts.firstIndex(where: { $0.id == product.productId }) {
            selectedProducts.remove(at: index)
        } else {
            selectedProducts.append(SelectedProduct(from: product))
        }
    }
}

// 产品选择行
struct ProductSelectorRow: View {
    let product: AllInOneSinglePlanetProductResult
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                // 产品图标
                Image(uiImage: IconManager.shared.loadUIImage(for: product.iconFileName))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                
                VStack(alignment: .leading, spacing: 4) {
                    // 产品名称
                    Text(product.productName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // 支持的行星类型
                    Text(String(format: NSLocalizedString("All_in_One_Compatible_Planets", comment: "支持行星: %@"), product.compatiblePlanetTypes.map { $0.name }.joined(separator: ", ")))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // P等级标识
                Text("P\(product.productLevel)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(levelColor(for: product.productLevel))
                    .cornerRadius(4)
                
                // 选择状态
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .font(.title2)
            }
        }
        .foregroundColor(.primary)
        .padding(.vertical, 4)
    }
    
    private func levelColor(for level: Int) -> Color {
        switch level {
        case 1: return .blue
        case 2: return .green
        case 3: return .orange
        case 4: return .red
        default: return .gray
        }
    }
} 
