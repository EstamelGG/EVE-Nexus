import SwiftUI

// 简化的星系选择器Sheet
struct StructureSystemSelectorSheet: View {
    let title: String
    let onSelect: (Int) -> Void  // 只接收星系ID
    let onCancel: () -> Void
    let currentSelection: Int?
    
    // 使用懒加载的星系数据
    @State private var allSystems: [JumpSystemData] = []
    @State private var isLoadingData = true
    
    private let databaseManager = DatabaseManager.shared
    
    init(
        title: String, currentSelection: Int? = nil, onSelect: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.currentSelection = currentSelection
    }
    
    var body: some View {
        if isLoadingData {
            VStack {
                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                Text(NSLocalizedString("Structure_Facility_Selector_Loading_Systems", comment: "加载星系数据中..."))
                    .foregroundColor(.gray)
            }
            .onAppear {
                loadAllSystemsData()
            }
        } else {
            // 复用SystemSelectorSheet，但包装选择回调
            SystemSelectorSheet(
                title: title,
                currentSelection: currentSelection,
                onlyLowSec: false,  // 建筑可以在所有星系进行
                jumpSystems: allSystems,
                onSelect: { systemId in
                    onSelect(systemId)
                },
                onCancel: onCancel
            )
        }
    }
    
    // 加载所有星系数据
    private func loadAllSystemsData() {
        DispatchQueue.global(qos: .userInitiated).async {
            // 查询所有星系，包含中英文名称，不限制跳跃门条件
            let query = """
                SELECT u.solarsystem_id, s.solarSystemName, s.solarSystemName_en, s.solarSystemName_zh,
                       u.system_security, r.regionName, u.x, u.y, u.z
                FROM universe u
                JOIN solarsystems s ON s.solarSystemID = u.solarsystem_id
                JOIN regions r ON r.regionID = u.region_id
                ORDER BY s.solarSystemName
            """
            
            var systems: [JumpSystemData] = []
            
            if case let .success(rows) = databaseManager.executeQuery(query) {
                for row in rows {
                    if let id = row["solarsystem_id"] as? Int,
                       let name = row["solarSystemName"] as? String,
                       let nameEN = row["solarSystemName_en"] as? String,
                       let security = row["system_security"] as? Double,
                       let region = row["regionName"] as? String,
                       let x = row["x"] as? Double,
                       let y = row["y"] as? Double,
                       let z = row["z"] as? Double
                    {
                        // 获取中文名，如果为nil则使用英文名
                        let nameZH = (row["solarSystemName_zh"] as? String) ?? nameEN
                        
                        // 计算显示安全等级
                        let displaySec = calculateDisplaySecurity(security)
                        
                        systems.append(
                            JumpSystemData(
                                id: id,
                                name: name,
                                nameEN: nameEN,
                                nameZH: nameZH,
                                security: displaySec,
                                region: region,
                                x: x,
                                y: y,
                                z: z
                            )
                        )
                    }
                }
            }
            
            // 在主线程更新UI
            DispatchQueue.main.async {
                allSystems = systems
                isLoadingData = false
            }
        }
    }
}

struct StructureFacilitySelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var selectedStructure: DatabaseListItem?
    @State private var customName: String = ""
    @State private var selectedRigs: [DatabaseListItem] = []
    @State private var showStructureSelector = false
    @State private var showRigSelector = false
    @State private var selectedSystemId: Int? = nil
    @State private var showSystemSelector = false
    
    let onStructureCreated: (IndustryFacilityInfo) -> Void
    let onStructureDeleted: ((Int) -> Void)?  // 新增：删除建筑的回调函数
    let onDismiss: () -> Void
    
    // 建筑相关的市场组ID
    private let allowedMarketGroups: Set<Int> = [2199, 2324, 2327]
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text(NSLocalizedString("Structure_Facility_Selector_Structure", comment: "建筑"))) {
                    // 自定义名称
                    TextField(NSLocalizedString("Structure_Facility_Selector_Name_Placeholder", comment: "输入建筑名称"), text: $customName)
                        .textFieldStyle(.plain)
                    
                    // 选择建筑
                    Button {
                        showStructureSelector = true
                    } label: {
                        HStack {
                            if let structure = selectedStructure {
                                IconManager.shared.loadImage(for: structure.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                
                                Text(structure.name)
                                    .foregroundColor(.primary)
                            } else {
                                IconManager.shared.loadImage(for: "industry")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("Structure_Facility_Selector_Select_Structure", comment: "选择建筑"))
                                        .foregroundColor(.primary)
                                    Text(NSLocalizedString("Structure_Facility_Selector_No_Structure_Selected", comment: "未选择建筑"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                Section(header: Text(NSLocalizedString("Structure_Facility_Selector_Rigs", comment: "插件"))) {
                    Button {
                        showRigSelector = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .frame(width: 32, height: 32)
                            Text(NSLocalizedString("Structure_Facility_Selector_Add_Rigs", comment: "添加插件"))
                            Spacer()
                        }
                    }
                    .foregroundColor(.primary)
                    .disabled(selectedStructure == nil) // 只有在选择了建筑后才允许选择插件
                    
                    // 显示已选择的插件
                    ForEach(selectedRigs) { rig in
                        HStack {
                            IconManager.shared.loadImage(for: rig.iconFileName)
                                .resizable()
                                .frame(width: 24, height: 24)
                                .cornerRadius(4)
                            Text(rig.name)
                                .font(.caption)
                            Spacer()
                            Button {
                                selectedRigs.removeAll { $0.id == rig.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                Section(header: Text(NSLocalizedString("Structure_Facility_Selector_System", comment: "星系"))) {
                    Button {
                        showSystemSelector = true
                    } label: {
                        HStack {
                            if let systemId = selectedSystemId {
                                // 已选择星系时的显示
                                Image(systemName: "location.circle.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 32, height: 32)
                                
                                HStack(spacing: 8) {
                                    let systemInfo = getSystemInfo(systemId: systemId, databaseManager: databaseManager)
                                    
                                    // 显示安全等级
                                    if let security = systemInfo.security {
                                        Text(formatSystemSecurity(security))
                                            .foregroundColor(getSecurityColor(security))
                                            .font(.system(.body, design: .monospaced))
                                            .fontWeight(.medium)
                                    }
                                    
                                    if let systemName = systemInfo.name {
                                        Text(systemName)
                                            .foregroundColor(.primary)
                                            .fontWeight(.semibold)
                                    } else {
                                        Text(NSLocalizedString("Structure_Facility_Selector_Unknown_System", comment: "未知星系"))
                                            .foregroundColor(.primary)
                                            .fontWeight(.semibold)
                                    }
                                }
                                
                                Spacer()
                                
                                Button {
                                    selectedSystemId = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.title2)
                                }
                            } else {
                                // 未选择星系时的显示
                                Image(systemName: "location.circle")
                                    .foregroundColor(.blue)
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("Structure_Facility_Selector_Select_System", comment: "选择星系"))
                                        .foregroundColor(.primary)
                                    Text(NSLocalizedString("Structure_Facility_Selector_No_System_Selected", comment: "未选择星系"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle(NSLocalizedString("Structure_Facility_Selector_Title", comment: "添加建筑"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Main_Setting_Cancel", comment: "取消")) {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Structure_Facility_Selector_Save", comment: "保存")) {
                        saveStructure()
                    }
                    .disabled(selectedStructure == nil)
                }
            }
        }
        .sheet(isPresented: $showStructureSelector) {
            NavigationView {
                MarketItemSelectorIntegratedView(
                    databaseManager: databaseManager,
                    title: NSLocalizedString("Structure_Facility_Selector_Select_Structure", comment: "选择建筑"),
                    allowedMarketGroups: allowedMarketGroups,
                    allowTypeIDs: nil,
                    existingItems: selectedStructure.map { Set([$0.id]) } ?? Set(),
                    onItemSelected: { structure in
                        selectedStructure = structure
                        showStructureSelector = false // 选择建筑后直接关闭
                    },
                    onItemDeselected: { _ in
                        selectedStructure = nil
                    },
                    onDismiss: {
                        showStructureSelector = false
                    },
                    showSelected: false // 不显示选择图标
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showRigSelector) {
            if let structure = selectedStructure {
                FacilityRigSelectorView(
                    databaseManager: databaseManager,
                    facilityTypeID: structure.id,
                    onRigSelected: { rigId in
                        // 检查是否已经添加了相同的插件
                        if selectedRigs.contains(where: { $0.id == rigId }) {
                            Logger.warning("已存在相同插件")
                            return // 如果已存在相同插件则不添加
                        }
                        
                        // 检查是否已经存在同类型插件（包括衍生型号）
                        if hasSameTypeRig(rigId: rigId) {
                            Logger.warning("已存在同类型插件")
                            return // 如果已存在同类型插件则不添加
                        }
                        
                        // 查询插件详细信息并添加到列表
                        if let rigInfo = getRigInfo(rigId: rigId) {
                            selectedRigs.append(rigInfo)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showSystemSelector) {
            StructureSystemSelectorSheet(
                title: NSLocalizedString("Structure_Facility_Selector_Select_System", comment: "选择星系"),
                currentSelection: selectedSystemId,
                onSelect: { systemId in
                    selectedSystemId = systemId
                    showSystemSelector = false
                },
                onCancel: {
                    showSystemSelector = false
                }
            )
        }
    }
    
    private func getRigInfo(rigId: Int) -> DatabaseListItem? {
        // 查询插件详细信息
        let query = "SELECT type_id, name, icon_filename FROM types WHERE type_id = ?"
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [rigId]),
           let row = rows.first,
           let typeId = row["type_id"] as? Int,
           let name = row["name"] as? String,
           let iconFileName = row["icon_filename"] as? String {
            return DatabaseListItem(
                id: typeId,
                name: name,
                enName: nil,
                iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName,
                published: true,
                categoryID: 0,
                groupID: nil,
                groupName: nil,
                pgNeed: nil,
                cpuNeed: nil,
                rigCost: nil,
                emDamage: nil,
                themDamage: nil,
                kinDamage: nil,
                expDamage: nil,
                highSlot: nil,
                midSlot: nil,
                lowSlot: nil,
                rigSlot: nil,
                gunSlot: nil,
                missSlot: nil,
                metaGroupID: nil,
                marketGroupID: nil,
                navigationDestination: AnyView(EmptyView())
            )
        }
        return nil
    }
    
    // 检查是否已存在同类型插件（包括衍生型号）
    private func hasSameTypeRig(rigId: Int) -> Bool {
        // 获取要添加插件的父类型ID
        let newRigParentId = getParentTypeId(typeId: rigId)
        
        // 检查已选择的插件中是否有同类型的
        for existingRig in selectedRigs {
            let existingRigParentId = getParentTypeId(typeId: existingRig.id)
            
            // 如果父类型ID相同，说明是同类型插件
            if newRigParentId == existingRigParentId {
                return true
            }
        }
        
        return false
    }
    
    // 获取物品的父类型ID（用于识别同类型不同衍生版本）
    private func getParentTypeId(typeId: Int) -> Int {
        // 使用递归查询获取最顶层的父类型ID
        let parentQuery = """
            WITH RECURSIVE parent AS (
                -- 基础查询：获取当前物品
                SELECT type_id, variationParentTypeID
                FROM types
                WHERE type_id = ?

                UNION ALL

                -- 递归查询：获取父物品
                SELECT t.type_id, t.variationParentTypeID
                FROM types t
                JOIN parent p ON t.type_id = p.variationParentTypeID
            )
            -- 获取最顶层的父物品ID或当前物品ID
            SELECT COALESCE(
                (SELECT type_id FROM parent WHERE variationParentTypeID IS NULL LIMIT 1),
                ?
            ) as parent_id
        """
        
        let parentResult = databaseManager.executeQuery(parentQuery, parameters: [typeId, typeId])
        
        if case let .success(rows) = parentResult,
           let row = rows.first,
           let parentId = row["parent_id"] as? Int {
            return parentId
        }
        
        // 如果查询失败，返回原始ID
        return typeId
    }
    
    
    
    private func saveStructure() {
        guard let structure = selectedStructure else { return }
        
        // 构建插件信息
        let rigInfos = selectedRigs.map { (id: $0.id, name: $0.name, iconFileName: $0.iconFileName) }
        
        // 创建建筑信息
        let facilityInfo = IndustryFacilityInfo(
            id: UUID().hashValue, // 使用UUID生成唯一ID
            typeId: structure.id,
            name: structure.name,
            iconFileName: structure.iconFileName,
            customName: customName.isEmpty ? nil : customName,
            isDefault: false,
            rigs: selectedRigs.map { $0.id },
            rigInfos: rigInfos,
            systemId: selectedSystemId
        )
        
        onStructureCreated(facilityInfo)
        onDismiss()
    }
}
