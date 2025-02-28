import SwiftUI

/// 存储设施视图
struct StorageFacilityView: View {
    let pin: PlanetaryPin
    let simulatedPin: Pin?
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    let typeVolumes: [Int: Double]
    let capacity: Double
    
    var body: some View {
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
                    Text("[\(PlanetaryFacility(identifier: pin.pinId).name)] \(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))")
                        .lineLimit(1)
                }
                
                // 容量进度条
                let total = calculateStorageVolume()
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: total, total: capacity)
                        .progressViewStyle(.linear)
                        .frame(height: 6)
                        .tint(capacity > 0 ? (total / capacity >= 0.9 ? .red : .blue) : .blue) // 容量快满时标红提示
                    
                    Text("\(Int(total.rounded()))m³ / \(Int(capacity))m³")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        
        // 存储的内容物，每个内容物单独一行
        if let simPin = simulatedPin {
            ForEach(Array(simPin.contents), id: \.key.id) { (type, amount) in
                if amount > 0 {
                    NavigationLink(destination: ShowPlanetaryInfo(itemID: type.id, databaseManager: DatabaseManager.shared)) {
                        HStack(alignment: .center, spacing: 12) {
                            if let iconName = typeIcons[type.id] {
                                Image(uiImage: IconManager.shared.loadUIImage(for: iconName))
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(typeNames[type.id] ?? type.name)
                                    .font(.subheadline)
                                HStack {
                                    Text("\(amount)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    let volume = typeVolumes[type.id] ?? type.volume
                                    Text("(\(Int(Double(amount) * volume))m³)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
    }
    
    // 计算存储设施的总体积
    private func calculateStorageVolume() -> Double {
        if let simPin = simulatedPin {
            let simContents = simPin.contents.map { 
                PlanetaryContent(amount: $0.value, typeId: $0.key.id)
            }
            return calculateTotalVolume(contents: simContents)
        }
        return calculateTotalVolume(contents: pin.contents)
    }
    
    // 计算内容物的总体积
    private func calculateTotalVolume(contents: [PlanetaryContent]?) -> Double {
        guard let contents = contents else { return 0 }
        return contents.reduce(0) { sum, content in
            sum + (Double(content.amount) * (typeVolumes[content.typeId] ?? 0))
        }
    }
} 
