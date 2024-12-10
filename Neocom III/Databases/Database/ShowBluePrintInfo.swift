import SwiftUI

// 蓝图活动数据模型
struct BlueprintActivity {
    let materials: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)]
    let skills: [(typeID: Int, typeName: String, typeIcon: String, level: Int)]
    let products: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)]
    let time: Int
}

// 产出物项视图
struct ProductItemView: View {
    let item: (typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)
    let databaseManager: DatabaseManager
    
    var body: some View {
        NavigationLink(
            destination: {
                if let categoryID = databaseManager.getCategoryID(for: item.typeID) {
                    ItemInfoMap.getItemInfoView(
                        itemID: item.typeID,
                        categoryID: categoryID,
                        databaseManager: databaseManager
                    )
                }
            }
        ) {
            HStack {
                IconManager.shared.loadImage(for: item.typeIcon.isEmpty ? "items_7_64_15.png" : item.typeIcon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                
                Text("产出物")
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(item.quantity) × \(item.typeName)")
                    .foregroundColor(.primary)
            }
        }
    }
}

// 发明产出项视图
struct InventionProductItemView: View {
    let product: (typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)
    let databaseManager: DatabaseManager
    
    var body: some View {
        NavigationLink(
            destination: {
                if let categoryID = databaseManager.getCategoryID(for: product.typeID) {
                    ItemInfoMap.getItemInfoView(
                        itemID: product.typeID,
                        categoryID: categoryID,
                        databaseManager: databaseManager
                    )
                }
            }
        ) {
            HStack {
                IconManager.shared.loadImage(for: product.typeIcon.isEmpty ? "items_7_64_15.png" : product.typeIcon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                
                VStack(alignment: .leading) {
                    Text("发明产出")
                    if let probability = product.probability {
                        Text("成功率: \(Int(probability * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Text(product.typeName)
                    .foregroundColor(.primary)
            }
        }
    }
}

// 材料列表视图
struct MaterialListView: View {
    let title: String
    let items: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int)]
    let databaseManager: DatabaseManager
    
    var body: some View {
        List {
            ForEach(items, id: \.typeID) { item in
                HStack {
                    IconManager.shared.loadImage(for: item.typeIcon.isEmpty ? "items_7_64_15.png" : item.typeIcon)
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
    let databaseManager: DatabaseManager
    
    var body: some View {
        List {
            ForEach(skills, id: \.typeID) { skill in
                HStack {
                    IconManager.shared.loadImage(for: skill.typeIcon.isEmpty ? "items_7_64_15.png" : skill.typeIcon)
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

// 产出物列表视图
struct ProductListView: View {
    let title: String
    let items: [(typeID: Int, typeName: String, typeIcon: String, quantity: Int, probability: Double?)]
    let databaseManager: DatabaseManager
    
    var body: some View {
        List {
            ForEach(items, id: \.typeID) { item in
                ProductItemView(item: item, databaseManager: databaseManager)
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
    let databaseManager: DatabaseManager
    
    var body: some View {
        List {
            ForEach(products, id: \.typeID) { product in
                InventionProductItemView(product: product, databaseManager: databaseManager)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
    }
}

// 主视图
struct ShowBluePrintInfo: View {
    let blueprintID: Int
    let databaseManager: DatabaseManager
    @State private var manufacturing: BlueprintActivity?
    @State private var researchMaterial: BlueprintActivity?
    @State private var researchTime: BlueprintActivity?
    @State private var copying: BlueprintActivity?
    @State private var invention: BlueprintActivity?
    @State private var itemDetails: ItemDetails?
    
    // 加载物品基本信息
    private func loadItemDetails() {
        itemDetails = databaseManager.getItemDetails(for: blueprintID)
    }
    
    // 格式化时间显示
    private func formatTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60
        
        var components: [String] = []
        
        if hours > 0 { components.append("\(hours)小时") }
        if minutes > 0 || (hours > 0 && remainingSeconds > 0) { components.append("\(minutes)分") }
        if remainingSeconds > 0 { components.append("\(remainingSeconds)秒") }
        
        return components.joined(separator: " ")
    }
    
    // 加载蓝图数据
    private func loadBlueprintData() {
        // 首先获取所有处理时间
        guard let processTime = databaseManager.getBlueprintProcessTime(for: blueprintID) else {
            return
        }
        
        // 制造活动
        if processTime.manufacturing_time > 0 {
            let manufacturingMaterials = databaseManager.getBlueprintManufacturingMaterials(for: blueprintID)
            let manufacturingProducts = databaseManager.getBlueprintManufacturingOutput(for: blueprintID)
            
            manufacturing = BlueprintActivity(
                materials: manufacturingMaterials,
                skills: [], // 制造不需要技能
                products: manufacturingProducts.map { ($0.typeID, $0.typeName, $0.typeIcon, $0.quantity, nil) },
                time: processTime.manufacturing_time
            )
        }
        
        // 材料研究活动
        if processTime.research_material_time > 0 {
            let researchMaterialMaterials = databaseManager.getBlueprintResearchMaterialMaterials(for: blueprintID)
            let researchMaterialSkills = databaseManager.getBlueprintResearchMaterialSkills(for: blueprintID)
            
            researchMaterial = BlueprintActivity(
                materials: researchMaterialMaterials,
                skills: researchMaterialSkills,
                products: [],
                time: processTime.research_material_time
            )
        }
        
        // 时间研究活动
        if processTime.research_time_time > 0 {
            let researchTimeMaterials = databaseManager.getBlueprintResearchTimeMaterials(for: blueprintID)
            let researchTimeSkills = databaseManager.getBlueprintResearchTimeSkills(for: blueprintID)
            
            researchTime = BlueprintActivity(
                materials: researchTimeMaterials,
                skills: researchTimeSkills,
                products: [],
                time: processTime.research_time_time
            )
        }
        
        // 复制活动
        if processTime.copying_time > 0 {
            let copyingMaterials = databaseManager.getBlueprintCopyingMaterials(for: blueprintID)
            let copyingSkills = databaseManager.getBlueprintCopyingSkills(for: blueprintID)
            
            copying = BlueprintActivity(
                materials: copyingMaterials,
                skills: copyingSkills,
                products: [],
                time: processTime.copying_time
            )
        }
        
        // 发明活动
        if processTime.invention_time > 0 {
            let inventionMaterials = databaseManager.getBlueprintInventionMaterials(for: blueprintID)
            let inventionSkills = databaseManager.getBlueprintInventionSkills(for: blueprintID)
            let inventionProducts = databaseManager.getBlueprintInventionProducts(for: blueprintID)
            
            invention = BlueprintActivity(
                materials: inventionMaterials,
                skills: inventionSkills,
                products: inventionProducts.map { ($0.typeID, $0.typeName, $0.typeIcon, $0.quantity, $0.probability) },
                time: processTime.invention_time
            )
        }
    }
    
    var body: some View {
        List {
            // 物品基本信息部分
            if let itemDetails = itemDetails {
                Section {
                    HStack {
                        IconManager.shared.loadImage(for: itemDetails.iconFileName)
                            .resizable()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(itemDetails.name)
                                .font(.title2)
                            Text("\(itemDetails.categoryName) / \(itemDetails.groupName)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // 制造部分
            if let manufacturing = manufacturing {
                Section(header: Text("制造").font(.headline)) {
                    // 产出物
                    if !manufacturing.products.isEmpty {
                        ForEach(manufacturing.products, id: \.typeID) { product in
                            ProductItemView(item: product, databaseManager: databaseManager)
                        }
                    }
                    
                    // 材料
                    if !manufacturing.materials.isEmpty {
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: manufacturing.materials, databaseManager: databaseManager)) {
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
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: researchMaterial.materials, databaseManager: databaseManager)) {
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
                        NavigationLink(destination: SkillListView(title: "所需技能", skills: researchMaterial.skills, databaseManager: databaseManager)) {
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
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: researchTime.materials, databaseManager: databaseManager)) {
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
                        NavigationLink(destination: SkillListView(title: "所需技能", skills: researchTime.skills, databaseManager: databaseManager)) {
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
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: copying.materials, databaseManager: databaseManager)) {
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
                        NavigationLink(destination: SkillListView(title: "所需技能", skills: copying.skills, databaseManager: databaseManager)) {
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
                        ForEach(invention.products, id: \.typeID) { product in
                            InventionProductItemView(product: product, databaseManager: databaseManager)
                        }
                    }
                    
                    // 材料
                    if !invention.materials.isEmpty {
                        NavigationLink(destination: MaterialListView(title: "所需材料", items: invention.materials, databaseManager: databaseManager)) {
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
                        NavigationLink(destination: SkillListView(title: "所需技能", skills: invention.skills, databaseManager: databaseManager)) {
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
            loadItemDetails()
            loadBlueprintData()
        }
    }
} 
