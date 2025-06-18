import SwiftUI

// 全局本地化映射字典
private let localizationMap: [String: String] = [
    // 等级映射
    "High-grade": "Implant_High_grade",
    "Mid-grade": "Implant_Mid_grade",
    "Low-grade": "Implant_Low_grade",
    
    // 套装映射
    "Snake": "Implant_Snake",
    "Crystal": "Implant_Crystal",
    "Amulet": "Implant_Amulet",
    "Ascendancy": "Implant_Ascendancy",
    "Asklepian": "Implant_Asklepian",
    "Nirvana": "Implant_Nirvana",
    "Rapture": "Implant_Rapture",
    "Virtue": "Implant_Virtue"
]

// 套装对应的属性ID映射
private let implantSetAttributeMap: [String: Int] = [
    "Snake": 315,      // 速度加成
    "Crystal": 548,    // 护盾加成
    "Amulet": 335,     // 装甲加成
    "Ascendancy": 624, // 扫描强度加成
    "Asklepian": 2457, // 护盾回复加成
    "Nirvana": 3015,   // 装甲回复加成
    "Rapture": 314,    // 电容回复加成
    "Virtue": 846      // 扫描强度加成
]

// 全局本地化函数
func localizedImplantString(_ key: String) -> String {
    if let localizedKey = localizationMap[key] {
        return NSLocalizedString(localizedKey, comment: "")
    }
    return key
}

struct ImplantPresetView: View {
    @Environment(\.dismiss) private var dismiss
    let databaseManager: DatabaseManager
    let onSelectPreset: ([Int]) -> Void
    
    // 预设数据
    private let grade_list = ["High-grade", "Mid-grade", "Low-grade"]
    private let implantSet_list = ["Snake", "Crystal", "Amulet", "Ascendancy", "Asklepian", "Nirvana", "Rapture", "Virtue"]
    private let type_list = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Omega"]
    
    @State private var isLoading = true
    @State private var presetData: [String: [String: [ImplantPresetItem]]] = [:]
    @State private var attributeDisplayNames: [Int: String] = [:]
    
    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                } else {
                    // 第一层：等级列表
                    ForEach(grade_list, id: \.self) { grade in
                        NavigationLink(destination: GradeDetailView(
                            grade: grade,
                            implantSets: presetData[grade] ?? [:],
                            attributeDisplayNames: attributeDisplayNames,
                            onSelectPreset: onSelectPreset
                        )) {
                            HStack {
                                Text(localizedImplantString(grade))
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Implant_Select_Preset", comment: "植入体预设"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadAttributeDisplayNames()
                loadImplantPresets()
            }
        }
    }
    
    // 加载属性显示名称
    private func loadAttributeDisplayNames() {
        let attributeIds = Array(implantSetAttributeMap.values)
        let placeholders = attributeIds.map { _ in "?" }.joined(separator: ",")
        
        let query = """
            SELECT attribute_id, display_name 
            FROM dogmaAttributes 
            WHERE attribute_id IN (\(placeholders))
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: attributeIds) {
            var tempAttributeNames: [Int: String] = [:]
            
            for row in rows {
                if let attributeId = row["attribute_id"] as? Int,
                   let displayName = row["display_name"] as? String {
                    tempAttributeNames[attributeId] = displayName
                }
            }
            
            attributeDisplayNames = tempAttributeNames
        }
    }
    
    private func loadImplantPresets() {
        isLoading = true
        
        // 生成所有可能的植入体名称
        var implantNames: [String] = []
        
        for grade in grade_list {
            for setName in implantSet_list {
                for typeName in type_list {
                    let fullName = "\(grade) \(setName) \(typeName)"
                    implantNames.append(fullName)
                }
            }
        }
        
        // 构建查询参数
        let placeholders = implantNames.map { _ in "?" }.joined(separator: ",")
        
        let query = """
            SELECT type_id, name, en_name, icon_filename 
            FROM types 
            WHERE en_name IN (\(placeholders))
            AND published = 1
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: implantNames) {
            var tempPresetData: [String: [String: [ImplantPresetItem]]] = [:]
            
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let enName = row["en_name"] as? String,
                   let iconFile = row["icon_filename"] as? String {
                    
                    // 解析英文名称以获取级别、套装名称和类型
                    let components = enName.components(separatedBy: " ")
                    if components.count >= 3 {
                        let grade = components[0]
                        let setName = components[1]
                        let type = components.last ?? ""
                        
                        // 检查是否为我们支持的预设
                        if grade_list.contains(grade) && implantSet_list.contains(setName) && type_list.contains(type) {
                            // 初始化字典
                            if tempPresetData[grade] == nil {
                                tempPresetData[grade] = [:]
                            }
                            if tempPresetData[grade]?[setName] == nil {
                                tempPresetData[grade]?[setName] = []
                            }
                            
                            // 添加植入体项
                            let presetItem = ImplantPresetItem(
                                typeId: typeId,
                                name: name,
                                enName: enName,
                                iconFileName: iconFile,
                                type: type
                            )
                            
                            tempPresetData[grade]?[setName]?.append(presetItem)
                        }
                    }
                }
            }
            
            // 为每个套装按类型排序
            for grade in grade_list {
                for setName in implantSet_list {
                    tempPresetData[grade]?[setName]?.sort { item1, item2 in
                        let index1 = type_list.firstIndex(of: item1.type) ?? Int.max
                        let index2 = type_list.firstIndex(of: item2.type) ?? Int.max
                        return index1 < index2
                    }
                }
            }
            
            presetData = tempPresetData
        }
        
        isLoading = false
    }
}

// 等级详情视图 - 第二层
struct GradeDetailView: View {
    let grade: String
    let implantSets: [String: [ImplantPresetItem]]
    let attributeDisplayNames: [Int: String]
    let onSelectPreset: ([Int]) -> Void
    
    var body: some View {
        List {
            ForEach(implantSet_list, id: \.self) { setName in
                if let setItems = implantSets[setName], !setItems.isEmpty {
                    NavigationLink(destination: ImplantSetDetailView(
                        setName: setName,
                        grade: grade,
                        implants: setItems,
                        onSelectPreset: onSelectPreset
                    )) {
                        HStack {
                            if let firstItem = setItems.first {
                                IconManager.shared.loadImage(for: firstItem.iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 32)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(localizedImplantString(setName))
                                    .font(.body)
                                
                                if let attributeId = implantSetAttributeMap[setName],
                                   let displayName = attributeDisplayNames[attributeId] {
                                    Text(displayName)
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
        .navigationTitle(localizedImplantString(grade))
    }
    
    // 植入体套装列表
    private var implantSet_list: [String] {
        // 按字母顺序排序，只包含有植入体的套装
        return implantSets.keys.sorted()
    }
}

// 植入体预设项模型
struct ImplantPresetItem: Identifiable {
    let id = UUID()
    let typeId: Int
    let name: String
    let enName: String
    let iconFileName: String
    let type: String
}

// 植入体套装详情视图 - 第三层
struct ImplantSetDetailView: View {
    let setName: String
    let grade: String
    let implants: [ImplantPresetItem]
    let onSelectPreset: ([Int]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItemID: Int? = nil
    @State private var showingItemInfo = false
    
    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Implant_Set_Items", comment: "套装物品"))) {
                ForEach(implants) { item in
                    HStack {
                        IconManager.shared.loadImage(for: item.iconFileName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                        
                        Text(item.name)
                            .font(.body)
                        
                        Spacer()
                        
                        // 添加物品信息按钮
                        Button {
                            selectedItemID = item.typeId
                            showingItemInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            
            Section {
                Button {
                    // 选择整个套装
                    let typeIds = implants.map { $0.typeId }
                    onSelectPreset(typeIds)
                } label: {
                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Apply_Preset", comment: "应用预设"))
                            .bold()
                        Spacer()
                    }
                }
                .foregroundColor(.blue)
            }
        }
        .navigationTitle("\(localizedImplantString(grade)) \(localizedImplantString(setName))")
        .sheet(isPresented: $showingItemInfo) {
            if let itemID = selectedItemID {
                NavigationStack {
                    ShowItemInfo(databaseManager: DatabaseManager.shared, itemID: itemID)
                }
                .presentationDragIndicator(.visible)
            }
        }
    }
} 
