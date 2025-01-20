import SwiftUI

struct PlanetDetailView: View {
    let characterId: Int
    let planetId: Int
    @State private var planetDetail: PlanetaryDetail?
    @State private var isLoading = true
    @State private var error: Error?
    
    // 用于存储类型名称的缓存
    @State private var typeNames: [Int: String] = [:]
    
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
                    // 设施部分
                    Section(header: Text(NSLocalizedString("Planet_Detail_Pins", comment: ""))) {
                        ForEach(detail.pins, id: \.pinId) { pin in
                            PinView(pin: pin, typeNames: typeNames)
                        }
                    }
                    
                    // 连接部分
                    if !detail.links.isEmpty {
                        Section(header: Text(NSLocalizedString("Planet_Detail_Links", comment: ""))) {
                            ForEach(detail.links, id: \.sourcePinId) { link in
                                LinkView(link: link)
                            }
                        }
                    }
                    
                    // 路由部分
                    if !detail.routes.isEmpty {
                        Section(header: Text(NSLocalizedString("Planet_Detail_Routes", comment: ""))) {
                            ForEach(detail.routes, id: \.routeId) { route in
                                RouteView(route: route, typeNames: typeNames)
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
            
            // 从routes收集类型ID
            planetDetail?.routes.forEach { route in
                typeIds.insert(route.contentTypeId)
            }
            
            // 查询类型名称
            if !typeIds.isEmpty {
                let typeIdsString = typeIds.map { String($0) }.joined(separator: ",")
                let query = """
                    SELECT type_id, name 
                    FROM types 
                    WHERE type_id IN (\(typeIdsString))
                """
                
                if case .success(let rows) = DatabaseManager.shared.executeQuery(query) {
                    for row in rows {
                        if let typeId = row["type_id"] as? Int,
                           let name = row["name"] as? String {
                            typeNames[typeId] = name
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))
                .font(.headline)
            
            if let contents = pin.contents, !contents.isEmpty {
                Text(NSLocalizedString("Planet_Detail_Contents", comment: "") + ":")
                    .font(.subheadline)
                ForEach(contents, id: \.typeId) { content in
                    HStack {
                        Text(typeNames[content.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))
                        Spacer()
                        Text("\(content.amount)")
                    }
                    .font(.subheadline)
                    .foregroundColor(.gray)
                }
            }
            
            if let extractor = pin.extractorDetails {
                ExtractorView(extractor: extractor, typeNames: typeNames)
            }
            
            if let factory = pin.factoryDetails {
                FactoryView(factory: factory)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExtractorView: View {
    let extractor: PlanetaryExtractor
    let typeNames: [Int: String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let productTypeId = extractor.productTypeId {
                Text(NSLocalizedString("Planet_Detail_Product", comment: "") + ": " + (typeNames[productTypeId] ?? ""))
            }
            if let cycleTime = extractor.cycleTime {
                Text(NSLocalizedString("Planet_Detail_Cycle_Time", comment: "") + ": \(cycleTime)s")
            }
            if let qtyPerCycle = extractor.qtyPerCycle {
                Text(NSLocalizedString("Planet_Detail_Quantity_Per_Cycle", comment: "") + ": \(qtyPerCycle)")
            }
        }
        .font(.subheadline)
        .foregroundColor(.gray)
    }
}

struct FactoryView: View {
    let factory: PlanetaryFactory
    
    var body: some View {
        Text(NSLocalizedString("Planet_Detail_Schematic_ID", comment: "") + ": \(factory.schematicId)")
            .font(.subheadline)
            .foregroundColor(.gray)
    }
}

struct LinkView: View {
    let link: PlanetaryLink
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("Planet_Detail_Link_Level", comment: "") + ": \(link.linkLevel)")
            Text("\(link.sourcePinId) → \(link.destinationPinId)")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

struct RouteView: View {
    let route: PlanetaryRoute
    let typeNames: [Int: String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(typeNames[route.contentTypeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))
                .font(.headline)
            HStack {
                Text("\(route.sourcePinId) → \(route.destinationPinId)")
                Spacer()
                Text(String(format: "%.0f", route.quantity))
            }
            .font(.subheadline)
            .foregroundColor(.gray)
            
            if let waypoints = route.waypoints, !waypoints.isEmpty {
                Text(NSLocalizedString("Planet_Detail_Waypoints", comment: "") + ": " + waypoints.map { String($0) }.joined(separator: " → "))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
    }
} 