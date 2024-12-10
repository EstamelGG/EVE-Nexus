import SwiftUI

// 蓝图活动数据模型
struct BlueprintActivity {
    let materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)]
    let skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)]
    let products: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)]
    let time: Int
}

struct ShowBluePrintInfo: View {
    let blueprintID: Int
    @ObservedObject var databaseManager: DatabaseManager
    @State private var manufacturing: BlueprintActivity?
    @State private var researchMaterial: BlueprintActivity?
    @State private var researchTime: BlueprintActivity?
    @State private var copying: BlueprintActivity?
    @State private var invention: BlueprintActivity?
    
    // 加载蓝图数据
    private func loadBlueprintData() {
        // 加载制造数据
        let manufacturingMaterials = databaseManager.getBlueprintManufacturingMaterials(for: blueprintID)
        let manufacturingProducts = databaseManager.getBlueprintManufacturingOutput(for: blueprintID)
        let manufacturingTime = databaseManager.getBlueprintProcessTime(for: blueprintID)?.manufacturing_time ?? 0
        
        if !manufacturingMaterials.isEmpty || !manufacturingProducts.isEmpty {
            manufacturing = BlueprintActivity(
                materials: manufacturingMaterials,
                skills: [], // 制造不需要技能
                products: manufacturingProducts.map { ($0.typeID, $0.typeName, $0.typeIcon, $0.quantity, nil) },
                time: manufacturingTime
            )
        }
        
        // 加载材料研究数据
        let researchMaterialMaterials = databaseManager.getBlueprintResearchMaterialMaterials(for: blueprintID)
        let researchMaterialSkills = databaseManager.getBlueprintResearchMaterialSkills(for: blueprintID)
        let researchMaterialTime = databaseManager.getBlueprintProcessTime(for: blueprintID)?.research_material_time ?? 0
        
        if !researchMaterialMaterials.isEmpty || !researchMaterialSkills.isEmpty {
            researchMaterial = BlueprintActivity(
                materials: researchMaterialMaterials,
                skills: researchMaterialSkills,
                products: [],
                time: researchMaterialTime
            )
        }
        
        // 加载时间研究数据
        let researchTimeMaterials = databaseManager.getBlueprintResearchTimeMaterials(for: blueprintID)
        let researchTimeSkills = databaseManager.getBlueprintResearchTimeSkills(for: blueprintID)
        let researchTimeTime = databaseManager.getBlueprintProcessTime(for: blueprintID)?.research_time_time ?? 0
        
        if !researchTimeMaterials.isEmpty || !researchTimeSkills.isEmpty {
            researchTime = BlueprintActivity(
                materials: researchTimeMaterials,
                skills: researchTimeSkills,
                products: [],
                time: researchTimeTime
            )
        }
        
        // 加载复制数据
        let copyingMaterials = databaseManager.getBlueprintCopyingMaterials(for: blueprintID)
        let copyingSkills = databaseManager.getBlueprintCopyingSkills(for: blueprintID)
        let copyingTime = databaseManager.getBlueprintProcessTime(for: blueprintID)?.copying_time ?? 0
        
        if !copyingMaterials.isEmpty || !copyingSkills.isEmpty {
            copying = BlueprintActivity(
                materials: copyingMaterials,
                skills: copyingSkills,
                products: [],
                time: copyingTime
            )
        }
        
        // 加载发明数据
        let inventionMaterials = databaseManager.getBlueprintInventionMaterials(for: blueprintID)
        let inventionSkills = databaseManager.getBlueprintInventionSkills(for: blueprintID)
        let inventionProducts = databaseManager.getBlueprintInventionProducts(for: blueprintID)
        let inventionTime = databaseManager.getBlueprintProcessTime(for: blueprintID)?.invention_time ?? 0
        
        if !inventionMaterials.isEmpty || !inventionSkills.isEmpty || !inventionProducts.isEmpty {
            invention = BlueprintActivity(
                materials: inventionMaterials,
                skills: inventionSkills,
                products: inventionProducts.map { ($0.typeID, $0.typeName, $0.typeIcon, $0.quantity, $0.probability) },
                time: inventionTime
            )
        }
    }
    
    var body: some View {
        List {
            // 制造部分
            if let manufacturing = manufacturing {
                Section(header: Text("制造").font(.headline)) {
                    // 产出物
                    if !manufacturing.products.isEmpty {
                        NavigationLink(destination: ProductListView(title: "产出物", items: manufacturing.products)) {
                            HStack {
                                Text("产出物")
                                Spacer()
                                Text("\(manufacturing.products.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 材料
                    if !manufacturing.materials.isEmpty {
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: manufacturing.materials)) {
                            HStack {
                                Text("所需材料")
                                Spacer()
                                Text("\(manufacturing.materials.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 制造时间
                    HStack {
                        Text("制造时间")
                        Spacer()
                        Text(formatTime(manufacturing.time))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 材料研究部分
            if let researchMaterial = researchMaterial {
                Section(header: Text("材料研究").font(.headline)) {
                    // 材料
                    if !researchMaterial.materials.isEmpty {
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: researchMaterial.materials)) {
                            HStack {
                                Text("所需材料")
                                Spacer()
                                Text("\(researchMaterial.materials.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 技能
                    if !researchMaterial.skills.isEmpty {
                        NavigationLink(destination: SkillListView(title: "所需技能", skills: researchMaterial.skills)) {
                            HStack {
                                Text("所需技能")
                                Spacer()
                                Text("\(researchMaterial.skills.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 研究时间
                    HStack {
                        Text("研究时间")
                        Spacer()
                        Text(formatTime(researchMaterial.time))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 时间研究部分
            if let researchTime = researchTime {
                Section(header: Text("时间研究").font(.headline)) {
                    // 材料
                    if !researchTime.materials.isEmpty {
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: researchTime.materials)) {
                            HStack {
                                Text("所需材料")
                                Spacer()
                                Text("\(researchTime.materials.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 技能
                    if !researchTime.skills.isEmpty {
                        NavigationLink(destination: SkillListView(title: "所需技能", skills: researchTime.skills)) {
                            HStack {
                                Text("所需技能")
                                Spacer()
                                Text("\(researchTime.skills.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 研究时间
                    HStack {
                        Text("研究时间")
                        Spacer()
                        Text(formatTime(researchTime.time))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 复制部分
            if let copying = copying {
                Section(header: Text("复制").font(.headline)) {
                    // 材料
                    if !copying.materials.isEmpty {
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: copying.materials)) {
                            HStack {
                                Text("所需材料")
                                Spacer()
                                Text("\(copying.materials.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 技能
                    if !copying.skills.isEmpty {
                        NavigationLink(destination: SkillListView(title: "所需技能", skills: copying.skills)) {
                            HStack {
                                Text("所需技能")
                                Spacer()
                                Text("\(copying.skills.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 复制时间
                    HStack {
                        Text("复制时间")
                        Spacer()
                        Text(formatTime(copying.time))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // 发明部分
            if let invention = invention {
                Section(header: Text("发明").font(.headline)) {
                    // 产出物
                    if !invention.products.isEmpty {
                        NavigationLink(destination: ProductListView(title: "发明产出", items: invention.products)) {
                            HStack {
                                Text("发明产出")
                                Spacer()
                                Text("\(invention.products.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 材料
                    if !invention.materials.isEmpty {
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: invention.materials)) {
                            HStack {
                                Text("所需材料")
                                Spacer()
                                Text("\(invention.materials.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 技能
                    if !invention.skills.isEmpty {
                        NavigationLink(destination: SkillListView(title: "所需技能", skills: invention.skills)) {
                            HStack {
                                Text("所需技能")
                                Spacer()
                                Text("\(invention.skills.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 发明时间
                    HStack {
                        Text("发明时间")
                        Spacer()
                        Text(formatTime(invention.time))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("蓝图信息")
        .onAppear {
            loadBlueprintData()
        }
    }
    
    // 格式化时间显示
    private func formatTime(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)秒"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)分\(remainingSeconds)秒"
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            let remainingSeconds = seconds % 60
            return "\(hours)小时\(minutes)分\(remainingSeconds)秒"
        }
    }
}

// 材料列表视图
struct MaterialListView: View {
    let title: String
    let items: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)]
    
    var body: some View {
        List {
            ForEach(items, id: \.typeID) { item in
                HStack {
                    IconManager.shared.loadImage(for: item.typeIcon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                    
                    Text(item.typeName)
                    
                    Spacer()
                    
                    Text("\(item.quantity)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
    }
}

// 技能列表视图
struct SkillListView: View {
    let title: String
    let skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)]
    
    var body: some View {
        List {
            ForEach(skills, id: \.typeID) { skill in
                HStack {
                    IconManager.shared.loadImage(for: skill.typeIcon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                    
                    Text(skill.typeName)
                    
                    Spacer()
                    
                    Text("等级 \(skill.level)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
    }
}

// 发明产出列表视图
struct InventionProductListView: View {
    let title: String
    let products: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)]
    
    var body: some View {
        List {
            ForEach(products, id: \.typeID) { product in
                HStack {
                    IconManager.shared.loadImage(for: product.typeIcon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                    
                    VStack(alignment: .leading) {
                        Text(product.typeName)
                        if let probability = product.probability {
                            Text("成功率: \(Int(probability * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text("\(product.quantity)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
    }
}

// 新增一个专门用于显示带概率的产出物品的视图
struct ProductListView: View {
    let title: String
    let items: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)]
    
    var body: some View {
        List {
            ForEach(items, id: \.typeID) { item in
                HStack {
                    IconManager.shared.loadImage(for: item.typeIcon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)
                    
                    VStack(alignment: .leading) {
                        Text(item.typeName)
                        if let probability = item.probability {
                            Text("成功率: \(Int(probability * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text("\(item.quantity)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
    }
} 