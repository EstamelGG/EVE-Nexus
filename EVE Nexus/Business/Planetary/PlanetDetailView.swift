import SwiftUI

struct PlanetDetailView: View {
    let characterId: Int
    let planetId: Int
    @State private var planetDetail: PlanetaryDetail?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var typeNames: [Int: String] = [:]
    @State private var typeIcons: [Int: String] = [:]
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
            } else if let error = error {
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
                        Section {
                            VStack(spacing: 0) {
                                PinView(pin: pin, typeNames: typeNames, typeIcons: typeIcons)
                                
                                // 如果是提取器，添加图表部分
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
                .refreshable {
                    await loadPlanetDetail(forceRefresh: true)
                }
            } else {
                Text(NSLocalizedString("Planet_Detail_No_Data", comment: ""))
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
            // 获取行星详情
            planetDetail = try await CharacterPlanetaryAPI.fetchPlanetaryDetail(
                characterId: characterId,
                planetId: planetId,
                forceRefresh: forceRefresh
            )
            
            // 收集所有需要查询的类型ID
            var typeIds = Set<Int>()
            
            // 从pins收集类型ID
            planetDetail?.pins.forEach { pin in
                typeIds.insert(pin.typeId)
                if let productTypeId = pin.extractorDetails?.productTypeId {
                    typeIds.insert(productTypeId)
                }
                pin.contents?.forEach { content in
                    typeIds.insert(content.typeId)
                }
            }
            
            // 查询类型名称和图标
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
            self.error = error
        }
        
        isLoading = false
    }
}

// MARK: - 子视图
struct PinView: View {
    let pin: PlanetaryPin
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    
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
                Text(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))
                    .font(.headline)
                
                // 工厂信息
                if let factory = pin.factoryDetails {
                    Text(NSLocalizedString("Planet_Detail_Schematic_ID", comment: "") + ": \(factory.schematicId)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // 存储的内容
                if let contents = pin.contents, !contents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(contents, id: \.typeId) { content in
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
                    .padding(.top, 4)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
} 