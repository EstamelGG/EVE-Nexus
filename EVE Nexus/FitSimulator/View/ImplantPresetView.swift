import SwiftUI

// 系统预设数据缓存（静态数据，只需要加载一次）
private class SystemPresetCache {
    static let shared = SystemPresetCache()
    private var cachedPresetData: [String: [String: [ImplantPresetItem]]] = [:]
    private var cachedAttributeDisplayNames: [Int: String] = [:]
    private var isLoaded = false

    private init() {}

    func loadIfNeeded(databaseManager: DatabaseManager, gradeList: [String], implantSetList: [String], typeList: [String], implantSetAttributeMap: [String: Int]) {
        guard !isLoaded else { return }

        // 加载属性显示名称
        let attributeIds = Array(implantSetAttributeMap.values)
        let placeholders = attributeIds.map { _ in "?" }.joined(separator: ",")
        let attrQuery = """
            SELECT attribute_id, display_name 
            FROM dogmaAttributes 
            WHERE attribute_id IN (\(placeholders))
        """

        if case let .success(rows) = databaseManager.executeQuery(attrQuery, parameters: attributeIds) {
            for row in rows {
                if let attributeId = row["attribute_id"] as? Int,
                   let displayName = row["display_name"] as? String
                {
                    cachedAttributeDisplayNames[attributeId] = displayName
                }
            }
        }

        // 加载系统预设
        var implantNames: [String] = []
        for grade in gradeList {
            for setName in implantSetList {
                for typeName in typeList {
                    let fullName = "\(grade) \(setName) \(typeName)"
                    implantNames.append(fullName)
                }
            }
        }

        let namePlaceholders = implantNames.map { _ in "?" }.joined(separator: ",")
        let query = """
            SELECT type_id, name, en_name, icon_filename 
            FROM types 
            WHERE en_name IN (\(namePlaceholders))
            AND published = 1
        """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: implantNames) {
            var tempPresetData: [String: [String: [ImplantPresetItem]]] = [:]

            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let enName = row["en_name"] as? String,
                   let iconFile = row["icon_filename"] as? String
                {
                    let components = enName.components(separatedBy: " ")
                    if components.count >= 3 {
                        let grade = components[0]
                        let setName = components[1]
                        let type = components.last ?? ""

                        if gradeList.contains(grade), implantSetList.contains(setName),
                           typeList.contains(type)
                        {
                            if tempPresetData[grade] == nil {
                                tempPresetData[grade] = [:]
                            }
                            if tempPresetData[grade]?[setName] == nil {
                                tempPresetData[grade]?[setName] = []
                            }

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
            for grade in gradeList {
                for setName in implantSetList {
                    tempPresetData[grade]?[setName]?.sort { item1, item2 in
                        let index1 = typeList.firstIndex(of: item1.type) ?? Int.max
                        let index2 = typeList.firstIndex(of: item2.type) ?? Int.max
                        return index1 < index2
                    }
                }
            }

            cachedPresetData = tempPresetData
        }

        isLoaded = true
    }

    func getPresetData() -> [String: [String: [ImplantPresetItem]]] {
        return cachedPresetData
    }

    func getAttributeDisplayNames() -> [Int: String] {
        return cachedAttributeDisplayNames
    }
}

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
    "Virtue": "Implant_Virtue",
]

// 套装对应的属性ID映射
private let implantSetAttributeMap: [String: Int] = [
    "Snake": 315, // 速度加成
    "Crystal": 548, // 护盾加成
    "Amulet": 335, // 装甲加成
    "Ascendancy": 624, // 扫描强度加成
    "Asklepian": 2457, // 护盾回复加成
    "Nirvana": 3015, // 装甲回复加成
    "Rapture": 314, // 电容回复加成
    "Virtue": 846, // 扫描强度加成
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
    private let implantSet_list = [
        "Snake", "Crystal", "Amulet", "Ascendancy", "Asklepian", "Nirvana", "Rapture", "Virtue",
    ]
    private let type_list = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Omega"]

    @State private var isLoading = true
    @State private var presetData: [String: [String: [ImplantPresetItem]]] = [:]
    @State private var attributeDisplayNames: [Int: String] = [:]
    @State private var customPresets: [CustomImplantPreset] = []
    @State private var customPresetIcons: [UUID: String] = [:] // 存储每个预设的第一个物品图标

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                } else {
                    // 自定义预设部分
                    if !customPresets.isEmpty {
                        Section(header: Text(NSLocalizedString("Implant_Custom_Presets", comment: "自定义预设"))) {
                            ForEach(customPresets) { preset in
                                NavigationLink(
                                    destination: CustomPresetDetailView(
                                        preset: preset,
                                        databaseManager: databaseManager,
                                        onSelectPreset: onSelectPreset
                                    )
                                ) {
                                    HStack {
                                        if let iconFileName = customPresetIcons[preset.id] {
                                            IconManager.shared.loadImage(for: iconFileName)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 32, height: 32)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        } else {
                                            Image(systemName: "bookmark.circle.fill")
                                                .foregroundColor(.green)
                                                .frame(width: 32, height: 32)
                                        }
                                        VStack(alignment: .leading) {
                                            Text(preset.name)
                                                .font(.body)
                                            Text(String(format: NSLocalizedString("Implant_Preset_Item_Count", comment: "%d 个物品"), preset.implantTypeIds.count))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .onDelete { indexSet in
                                deleteCustomPresets(at: indexSet)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }

                    // 系统预设部分
                    Section(header: Text(NSLocalizedString("Implant_System_Presets", comment: "系统预设"))) {
                        // 第一层：等级列表
                        ForEach(grade_list, id: \.self) { grade in
                            NavigationLink(
                                destination: GradeDetailView(
                                    grade: grade,
                                    implantSets: presetData[grade] ?? [:],
                                    attributeDisplayNames: attributeDisplayNames,
                                    onSelectPreset: onSelectPreset
                                )
                            ) {
                                HStack {
                                    Text(localizedImplantString(grade))
                                    Spacer()
                                }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
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
            .task {
                // 系统预设使用缓存，只在第一次加载
                SystemPresetCache.shared.loadIfNeeded(
                    databaseManager: databaseManager,
                    gradeList: grade_list,
                    implantSetList: implantSet_list,
                    typeList: type_list,
                    implantSetAttributeMap: implantSetAttributeMap
                )
                presetData = SystemPresetCache.shared.getPresetData()
                attributeDisplayNames = SystemPresetCache.shared.getAttributeDisplayNames()

                // 自定义预设每次都需要加载（可能在其他地方被修改）
                loadCustomPresets()

                isLoading = false
            }
        }
    }

    // 加载自定义预设
    private func loadCustomPresets() {
        customPresets = CustomImplantPresetManager.shared.loadPresets()
        loadCustomPresetIcons()
    }

    // 加载自定义预设的第一个物品图标
    private func loadCustomPresetIcons() {
        var icons: [UUID: String] = [:]

        // 收集所有需要查询的 typeId
        var allTypeIds: [Int] = []
        var presetIdMap: [Int: UUID] = [:] // typeId -> presetId 映射

        for preset in customPresets {
            if let firstTypeId = preset.implantTypeIds.first {
                allTypeIds.append(firstTypeId)
                presetIdMap[firstTypeId] = preset.id
            }
        }

        guard !allTypeIds.isEmpty else {
            customPresetIcons = icons
            return
        }

        // 查询第一个物品的图标
        let placeholders = String(repeating: "?,", count: allTypeIds.count).dropLast()
        let query = """
            SELECT type_id, icon_filename 
            FROM types 
            WHERE type_id IN (\(placeholders))
            AND published = 1
        """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: allTypeIds) {
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let iconFile = row["icon_filename"] as? String,
                   let presetId = presetIdMap[typeId]
                {
                    icons[presetId] = iconFile
                }
            }
        }

        customPresetIcons = icons
    }

    // 删除自定义预设
    private func deleteCustomPresets(at offsets: IndexSet) {
        for index in offsets {
            let preset = customPresets[index]
            CustomImplantPresetManager.shared.deletePreset(preset.id)
        }
        loadCustomPresets() // 重新加载
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
                    NavigationLink(
                        destination: ImplantSetDetailView(
                            setName: setName,
                            grade: grade,
                            implants: setItems,
                            onSelectPreset: onSelectPreset
                        )
                    ) {
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
                                   let displayName = attributeDisplayNames[attributeId]
                                {
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

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Implant_Set_Items", comment: "套装物品"))) {
                ForEach(implants) { item in
                    ImplantPresetItemRow(item: item)
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
    }
}

// 植入体预设项行组件
struct ImplantPresetItemRow: View {
    let item: ImplantPresetItem
    @State private var showingItemInfo = false

    var body: some View {
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
                showingItemInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(BorderlessButtonStyle())
            .sheet(isPresented: $showingItemInfo) {
                NavigationStack {
                    ShowItemInfo(databaseManager: DatabaseManager.shared, itemID: item.typeId)
                }
                .presentationDragIndicator(.visible)
            }
        }
    }
}

// 自定义预设详情视图
struct CustomPresetDetailView: View {
    let preset: CustomImplantPreset
    let databaseManager: DatabaseManager
    let onSelectPreset: ([Int]) -> Void

    @State private var presetItems: [PresetItemInfo] = []
    @State private var isLoading = true
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if presetItems.isEmpty {
                Text(NSLocalizedString("Implant_Preset_No_Items", comment: "预设中没有物品"))
                    .foregroundColor(.secondary)
            } else {
                Section(header: Text(NSLocalizedString("Implant_Preset_Items", comment: "预设物品"))) {
                    ForEach(presetItems) { item in
                        HStack {
                            IconManager.shared.loadImage(for: item.iconFileName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)

                            Text(item.name)
                                .font(.body)

                            Spacer()
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))

                Section {
                    Button {
                        onSelectPreset(preset.implantTypeIds)
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

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text(NSLocalizedString("Misc_Delete", comment: "删除"))
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(preset.name)
        .onAppear {
            loadPresetItems()
        }
        .alert(NSLocalizedString("Misc_Delete", comment: "删除"), isPresented: $showingDeleteConfirmation) {
            Button(NSLocalizedString("Misc_Cancel", comment: "取消"), role: .cancel) {}
            Button(NSLocalizedString("Misc_Delete", comment: "删除"), role: .destructive) {
                CustomImplantPresetManager.shared.deletePreset(preset.id)
            }
        } message: {
            Text(NSLocalizedString("Implant_Confirm_Delete_Preset", comment: "确定要删除此预设吗？"))
        }
    }

    private func loadPresetItems() {
        isLoading = true

        guard !preset.implantTypeIds.isEmpty else {
            isLoading = false
            return
        }

        let placeholders = String(repeating: "?,", count: preset.implantTypeIds.count).dropLast()
        let query = """
            SELECT type_id, name, icon_filename 
            FROM types 
            WHERE type_id IN (\(placeholders))
            AND published = 1
        """

        if case let .success(rows) = databaseManager.executeQuery(query, parameters: preset.implantTypeIds) {
            var items: [PresetItemInfo] = []

            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFile = row["icon_filename"] as? String
                {
                    items.append(PresetItemInfo(
                        typeId: typeId,
                        name: name,
                        iconFileName: iconFile
                    ))
                }
            }

            // 按照原始顺序排序
            var sortedItems: [PresetItemInfo] = []
            for typeId in preset.implantTypeIds {
                if let item = items.first(where: { $0.typeId == typeId }) {
                    sortedItems.append(item)
                }
            }

            presetItems = sortedItems
        }

        isLoading = false
    }
}

// 预设物品信息
struct PresetItemInfo: Identifiable {
    let id: UUID = .init()
    let typeId: Int
    let name: String
    let iconFileName: String
}
