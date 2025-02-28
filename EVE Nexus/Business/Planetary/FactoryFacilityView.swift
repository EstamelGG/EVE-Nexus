import SwiftUI

/// 工厂设施视图
struct FactoryFacilityView: View {
    let pin: PlanetaryPin
    let simulatedPin: Pin.Factory?
    let typeNames: [Int: String]
    let typeIcons: [Int: String]
    let schematic: SchematicInfo?
    let currentTime: Date
    
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
                // 设施名称
                HStack {
                    Text("[\(PlanetaryFacility(identifier: pin.pinId).name)] \(typeNames[pin.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))")
                        .lineLimit(1)
                }
                
                // 加工进度
                if let _ = schematic,
                   let simPin = simulatedPin {
                    VStack(alignment: .leading, spacing: 2) {
                        if let schematicObj = simPin.schematic {
                            let progress = calculateFactoryProgress(factory: simPin, currentTime: currentTime)
                            
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(height: 6)
                                .tint(simPin.isActive ? Color(red: 0.8, green: 0.6, blue: 0.0) : .gray)
                            
                            if simPin.isActive, let lastCycleStartTime = simPin.lastCycleStartTime {
                                let cycleEndTime = lastCycleStartTime.addingTimeInterval(schematicObj.cycleTime)
                                HStack {
                                    Text(NSLocalizedString("Factory_Processing", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                    Text("·")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.secondary)
                                    Text(cycleEndTime, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else if simPin.hasEnoughInputs() {
                                Text(NSLocalizedString("Factory_Ready", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(NSLocalizedString("Factory_Waiting_Materials", comment: ""))
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                        } else {
                            ProgressView(value: 0)
                                .progressViewStyle(.linear)
                                .frame(height: 6)
                                .tint(.gray)
                            Text(NSLocalizedString("Factory_No_Recipe", comment: ""))
                                .font(.caption)
                                .fontWeight(.bold)
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
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        
        // 输入和输出物品
        if let schematic = schematic {
            // 输入物品
            ForEach(schematic.inputs, id: \.typeId) { input in
                NavigationLink(destination: ShowPlanetaryInfo(itemID: input.typeId, databaseManager: DatabaseManager.shared)) {
                    HStack(alignment: .center, spacing: 12) {
                        if let iconName = typeIcons[input.typeId] {
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
                                Text(NSLocalizedString("Factory_Input", comment: "") + " \(typeNames[input.typeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))")
                            }
                            
                            // 显示当前存储量与需求量的比例
                            if let simPin = simulatedPin {
                                let currentAmount = simPin.contents.first(where: { $0.key.id == input.typeId })?.value ?? 0
                                Text(NSLocalizedString("Factory_Inventory", comment: "") + " \(currentAmount)/\(input.value)")
                                    .font(.caption)
                                    .foregroundColor(
                                        currentAmount >= input.value ? .secondary :
                                        currentAmount > 0 ? .blue : .red
                                    )
                            } else {
                                let currentAmount = pin.contents?.first(where: { $0.typeId == input.typeId })?.amount ?? 0
                                Text(NSLocalizedString("Factory_Inventory", comment: "") + " \(currentAmount)/\(input.value)")
                                    .font(.caption)
                                    .foregroundColor(
                                        currentAmount >= input.value ? .secondary :
                                        currentAmount > 0 ? .blue : .red
                                    )
                            }
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            
            // 输出物品
            NavigationLink(destination: ShowPlanetaryInfo(itemID: schematic.outputTypeId, databaseManager: DatabaseManager.shared)) {
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
                            Text(NSLocalizedString("Factory_Output", comment: "") + " \(typeNames[schematic.outputTypeId] ?? NSLocalizedString("Planet_Detail_Unknown_Type", comment: ""))")
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
              let lastCycleStartTime = factory.lastCycleStartTime else {
            return 0
        }
        
        // 计算已经过去的时间与周期时间的比例
        let elapsed = currentTime.timeIntervalSince(lastCycleStartTime)
        let progress = elapsed / schematic.cycleTime
        
        // 确保进度在0到1之间
        return min(max(progress, 0), 1)
    }
} 
