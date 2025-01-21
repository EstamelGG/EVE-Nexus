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
                        if let groupId = typeGroupIds[pin.typeId],
                           storageCapacities.keys.contains(groupId) {
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
                        } else {
                            // 非存储设施使用原有的PinView
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
            
            planetDetail?.pins.forEach { pin in
                typeIds.insert(pin.typeId)
                if let productTypeId = pin.extractorDetails?.productTypeId {
                    typeIds.insert(productTypeId)
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
