import SwiftUI

/// 蓝图计算器初始化参数
struct BlueprintCalculatorInitParams {
    let blueprintId: Int?
    let runs: Int?
    let materialEfficiency: Int?
    let timeEfficiency: Int?
    let selectedStructure: IndustryFacilityInfo?
    let selectedSystemId: Int?
    let facilityTax: Double?
    let selectedCharacterSkills: [Int: Int]?
    let selectedCharacterName: String?
    let selectedCharacterId: Int?
    
    init(
        blueprintId: Int? = nil,
        runs: Int? = nil,
        materialEfficiency: Int? = nil,
        timeEfficiency: Int? = nil,
        selectedStructure: IndustryFacilityInfo? = nil,
        selectedSystemId: Int? = nil,
        facilityTax: Double? = nil,
        selectedCharacterSkills: [Int: Int]? = nil,
        selectedCharacterName: String? = nil,
        selectedCharacterId: Int? = nil
    ) {
        self.blueprintId = blueprintId
        self.runs = runs
        self.materialEfficiency = materialEfficiency
        self.timeEfficiency = timeEfficiency
        self.selectedStructure = selectedStructure
        self.selectedSystemId = selectedSystemId
        self.facilityTax = facilityTax
        self.selectedCharacterSkills = selectedCharacterSkills
        self.selectedCharacterName = selectedCharacterName
        self.selectedCharacterId = selectedCharacterId
    }
}

struct BlueprintCalculatorView: View {
    let initParams: BlueprintCalculatorInitParams?
    
    @State private var materialEfficiency: Int = 10
    @State private var timeEfficiency: Int = 20
    @State private var runs: Int = 1
    @State private var facilityTax: Double = 1.0  // 默认1%税率
    @State private var selectedBlueprint: DatabaseListItem?
    @State private var showBlueprintSelector = false
    @State private var selectedStructure: IndustryFacilityInfo?
    @State private var showStructureSelector = false
    @State private var selectedSystemId: Int? = nil
    @State private var showSystemSelector = false
    @State private var selectedCharacterSkills: [Int: Int] = [:]
    @State private var selectedCharacterName: String = ""
    @State private var selectedCharacterId: Int = 0
    @State private var calculationResult: BlueprintCalcUtil.BlueprintCalcResult? = nil
    @State private var showResult = false
    @State private var isCalculating = false
    @StateObject private var databaseManager = DatabaseManager.shared
    
    init(initParams: BlueprintCalculatorInitParams? = nil) {
        self.initParams = initParams
    }
    
    // 计算是否可以开始计算
    private var canStartCalculation: Bool {
        guard selectedBlueprint != nil && selectedStructure != nil && selectedSystemId != nil && !selectedCharacterSkills.isEmpty else {
            return false
        }
        
        // 检查蓝图和建筑的兼容性
        return isStructureCompatibleWithBlueprint()
    }
    
    // 检查是否所有必要条件都已满足（不考虑兼容性）
    private var hasAllRequiredSelections: Bool {
        return selectedBlueprint != nil && selectedStructure != nil && selectedSystemId != nil && !selectedCharacterSkills.isEmpty
    }
    
    // 检查建筑与蓝图的兼容性
    private func isStructureCompatibleWithBlueprint() -> Bool {
        guard let blueprint = selectedBlueprint,
              let structure = selectedStructure else {
            return false
        }
        
        let isReactionBlueprint = isReactionTypeBlueprint(blueprint)
        let isReactionStructure = isReactionStructure(structure)
        
        // 反应蓝图必须用反应建筑
        if isReactionBlueprint && !isReactionStructure {
            return false
        }
        
        // 普通蓝图不能用反应建筑
        if !isReactionBlueprint && isReactionStructure {
            return false
        }
        
        return true
    }
    
    // 判断是否为反应类型蓝图
    private func isReactionTypeBlueprint(_ blueprint: DatabaseListItem) -> Bool {
        guard let marketGroupID = blueprint.marketGroupID else {
            return false
        }
        
        // 获取市场组1849的所有子组ID
        let reactionMarketGroups = getReactionMarketGroups()
        return reactionMarketGroups.contains(marketGroupID)
    }
    
    // 判断是否为反应建筑
    private func isReactionStructure(_ structure: IndustryFacilityInfo) -> Bool {
        // 反应建筑类型ID: 35836 (反应堡垒) 或 35835 (反应服务阵列)
        return structure.typeId == 35836 || structure.typeId == 35835
    }
    
    // 获取市场组1849及其所有子组的ID集合
    private func getReactionMarketGroups() -> Set<Int> {
        let reactionRootGroupId = 1849
        var reactionGroups = Set<Int>()
        
        // 使用递归查询获取所有子组
        let query = """
            WITH RECURSIVE market_group_tree AS (
                -- 基础查询：获取根组1849(反应公式)
                SELECT group_id, parentgroup_id
                FROM marketGroups
                WHERE group_id = ?
                
                UNION ALL
                
                -- 递归查询：获取所有子组
                SELECT mg.group_id, mg.parentgroup_id
                FROM marketGroups mg
                INNER JOIN market_group_tree mgt ON mg.parentgroup_id = mgt.group_id
            )
            SELECT group_id FROM market_group_tree
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [reactionRootGroupId]) {
            for row in rows {
                if let groupId = row["group_id"] as? Int {
                    reactionGroups.insert(groupId)
                }
            }
        } else {
            return []
        }
        
        return reactionGroups
    }
    
    // 获取不兼容的原因
    private func getIncompatibilityReason() -> String {
        guard let blueprint = selectedBlueprint,
              let structure = selectedStructure else {
            return ""
        }
        
        let isReactionBlueprint = isReactionTypeBlueprint(blueprint)
        let isReactionStructure = isReactionStructure(structure)
        
        if isReactionBlueprint && !isReactionStructure {
            return NSLocalizedString("Blueprint_Calculator_Reaction_Need_Reaction_Structure", comment: "反应蓝图需要反应建筑")
        } else if !isReactionBlueprint && isReactionStructure {
            return NSLocalizedString("Blueprint_Calculator_Normal_Cannot_Use_Reaction_Structure", comment: "普通蓝图不能使用反应建筑")
        }
        
        return ""
    }
    
    // 获取按钮背景颜色
    private func getButtonBackgroundColor() -> Color {
        if isCalculating {
            // 状态4: 计算中 - 浅蓝色
            return Color.blue.opacity(0.6)
        } else if !hasAllRequiredSelections {
            // 状态1: 未完成所有必要选择 - 灰色
            return Color.gray
        } else if hasAllRequiredSelections && !isStructureCompatibleWithBlueprint() {
            // 状态2: 已完成选择但不兼容 - 红色
            return Color.red
        } else {
            // 状态3: 已完成选择且兼容 - 蓝色
            return Color.blue
        }
    }
    
    var body: some View {
        VStack {
            List {
                Section(header: Text(NSLocalizedString("Blueprint_Calculator_Settings", comment: "蓝图设置"))) {
                    // 选择蓝图跳转链接
                    Button {
                        showBlueprintSelector = true
                    } label: {
                        HStack {
                            if let blueprint = selectedBlueprint {
                                // 显示选中的蓝图图标和名称
                                IconManager.shared.loadImage(for: blueprint.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                
                                Text(blueprint.name)
                                    .foregroundColor(.primary)
                            } else {
                                // 显示默认的蓝图图标和选择提示
                                IconManager.shared.loadImage(for: "blueprints")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("Blueprint_Calculator_Select_Blueprint", comment: "选择蓝图"))
                                        .foregroundColor(.primary)
                                    Text(NSLocalizedString("Blueprint_Calculator_No_Blueprint_Selected", comment: "未选择蓝图"))
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
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    
                    // 流程数设置
                    HStack {
                        Text(NSLocalizedString("Blueprint_Calculator_Runs", comment: "流程数"))
                        
                        Spacer()
                        
                        TextField("1", value: $runs, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                            .multilineTextAlignment(.leading)
                            .onChange(of: runs) { _, newValue in
                                // 确保流程数至少为1
                                if newValue < 1 {
                                    runs = 1
                                }
                            }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    
                    // 材料效率选择
                    HStack {
                        Text(NSLocalizedString("Blueprint_Calculator_Material_Efficiency", comment: "材料效率"))
                        
                        Spacer()
                        
                        Picker("", selection: $materialEfficiency) {
                            ForEach(0...10, id: \.self) { level in
                                Text("\(level) %").tag(level)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    
                    // 时间效率选择
                    HStack {
                        Text(NSLocalizedString("Blueprint_Calculator_Time_Efficiency", comment: "时间效率"))
                        
                        Spacer()
                        
                        Picker("", selection: $timeEfficiency) {
                            ForEach(0...20, id: \.self) { level in
                                if level % 2 == 0 {
                                    Text("\(level) %").tag(level)
                                }
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                
                Section(header: Text(NSLocalizedString("Blueprint_Calculator_Structure_Settings", comment: "建筑设置"))) {
                    // 选择建筑跳转链接
                    Button {
                        showStructureSelector = true
                    } label: {
                        HStack {
                            if let structure = selectedStructure {
                                // 显示选中的建筑图标和名称
                                IconManager.shared.loadImage(for: structure.iconFileName)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                
                                Text(structure.displayName)
                                    .foregroundColor(.primary)
                            } else {
                                // 显示默认的建筑图标和选择提示
                                IconManager.shared.loadImage(for: "industry")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(4)
                                
                                VStack(alignment: .leading) {
                                    Text(NSLocalizedString("Blueprint_Calculator_Select_Structure", comment: "选择建筑"))
                                        .foregroundColor(.primary)
                                    Text(NSLocalizedString("Blueprint_Calculator_No_Structure_Selected", comment: "未选择建筑"))
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
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    
                    // 选择星系
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
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    
                    // 设施税设置
                    HStack {
                        Text(NSLocalizedString("Blueprint_Calculator_Facility_Tax", comment: "设施税"))
                        
                        Spacer()
                        
                        TextField("1.0", value: $facilityTax, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.leading)
                            .onChange(of: facilityTax) { _, newValue in
                                // 确保设施税至少为0
                                if newValue < 0 {
                                    facilityTax = 0
                                }
                            }
                        Text("%")
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
                
                Section(header: Text(NSLocalizedString("Fitting_Setting_Skills", comment: "技能设置"))) {
                    NavigationLink {
                        CharacterSkillsSelectorView(
                            databaseManager: databaseManager,
                            onSelectSkills: { skills, skillModeName, characterId in
                                selectedCharacterSkills = skills
                                selectedCharacterName = skillModeName
                                selectedCharacterId = characterId
                            }
                        )
                    } label: {
                        HStack {
                            Image("skill")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            Text(NSLocalizedString("Fitting_Skills_Mode", comment: "技能模式"))
                            Spacer()
                            Text(selectedCharacterSkills.isEmpty ? NSLocalizedString("Fitting_Unknown_Skills", comment: "未知技能模式") : selectedCharacterName)
                                .foregroundColor(.secondary)
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
            
            Button(action: {
                // 开始计算逻辑
                startCalculation()
            }) {
                HStack(spacing: 8) {
                    if isCalculating {
                        // 显示加载指示器
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    VStack(spacing: 4) {
                        if isCalculating {
                            // 状态4: 计算中 - 显示计算中文本
                            Text(NSLocalizedString("Blueprint_Calculator_Calculating", comment: "计算中"))
                                .fontWeight(.semibold)
                        } else if !hasAllRequiredSelections {
                            // 状态1: 未完成所有必要选择 - 灰色按钮
                            Text(NSLocalizedString("Blueprint_Calculator_Start_Calculation", comment: "开始计算"))
                                .fontWeight(.semibold)
                        } else if hasAllRequiredSelections && !isStructureCompatibleWithBlueprint() {
                            // 状态2: 已完成选择但不兼容 - 红色按钮，显示不兼容原因
                            Text(getIncompatibilityReason())
                                .fontWeight(.semibold)
                                .multilineTextAlignment(.center)
                        } else {
                            // 状态3: 已完成选择且兼容 - 蓝色按钮
                            Text(NSLocalizedString("Blueprint_Calculator_Start_Calculation", comment: "开始计算"))
                                .fontWeight(.semibold)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(getButtonBackgroundColor())
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!canStartCalculation || isCalculating)
            .padding()
        }
        .navigationTitle(NSLocalizedString("Blueprint_Calculator", comment: "蓝图计算器"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            applyInitParams()
        }
        .sheet(isPresented: $showBlueprintSelector) {
            NavigationView {
                BlueprintSelectorView(
                    databaseManager: databaseManager,
                    onBlueprintSelected: { blueprint in
                        selectedBlueprint = blueprint
                        showBlueprintSelector = false
                    },
                    onDismiss: {
                        showBlueprintSelector = false
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showStructureSelector) {
            NavigationView {
                StructureSelectorView(
                    databaseManager: databaseManager,
                    onStructureSelected: { structure in
                        selectedStructure = structure
                        // 如果选择了自定义建筑且有星系配置，则自动设置星系
                        if let systemId = structure.systemId {
                            selectedSystemId = systemId
                        }
                        showStructureSelector = false
                    },
                    onDismiss: {
                        showStructureSelector = false
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
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
        .navigationDestination(isPresented: $showResult) {
            if let result = calculationResult,
               let blueprint = selectedBlueprint {
                BlueprintCalculatorResultView(
                    databaseManager: databaseManager,
                    calculationResult: result,
                    blueprintInfo: blueprint,
                    runs: runs,
                    originalStructure: selectedStructure,
                    originalSystemId: selectedSystemId,
                    originalFacilityTax: facilityTax,
                    originalCharacterSkills: selectedCharacterSkills,
                    originalCharacterName: selectedCharacterName,
                    originalCharacterId: selectedCharacterId
                )
            }
        }

    }
    
    // 应用初始化参数
    private func applyInitParams() {
        // 首先设置默认值
        if selectedCharacterSkills.isEmpty {
            selectedCharacterSkills = CharacterSkillsUtils.getCharacterSkills(type: .all5)
            selectedCharacterName = String(format: NSLocalizedString("Fitting_All_Skills", comment: "全n级"), 5)
            selectedCharacterId = 0
        }
        
        // 应用传入的初始化参数
        if let params = initParams {
            if let runs = params.runs {
                self.runs = runs
            }
            
            if let materialEfficiency = params.materialEfficiency {
                self.materialEfficiency = materialEfficiency
            }
            
            if let timeEfficiency = params.timeEfficiency {
                self.timeEfficiency = timeEfficiency
            }
            
            if let structure = params.selectedStructure {
                self.selectedStructure = structure
            }
            
            if let systemId = params.selectedSystemId {
                self.selectedSystemId = systemId
            }
            
            if let facilityTax = params.facilityTax {
                self.facilityTax = facilityTax
            }
            
            if let skills = params.selectedCharacterSkills {
                self.selectedCharacterSkills = skills
            }
            
            if let characterName = params.selectedCharacterName {
                self.selectedCharacterName = characterName
            }
            
            if let characterId = params.selectedCharacterId {
                self.selectedCharacterId = characterId
            }
            
            // 如果有蓝图ID，需要查询蓝图信息
            if let blueprintId = params.blueprintId {
                loadBlueprintById(blueprintId)
            }
        }
    }
    
    // 根据蓝图ID加载蓝图信息
    private func loadBlueprintById(_ blueprintId: Int) {
        let query = """
            SELECT t.type_id, t.name, t.en_name, t.icon_filename, t.published, t.marketGroupID,
                   t.categoryID, t.groupID, t.group_name
            FROM types t
            WHERE t.type_id = ? AND t.published = 1
        """
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: [blueprintId]),
           let row = rows.first,
           let typeId = row["type_id"] as? Int,
           let name = row["name"] as? String,
           let iconFileName = row["icon_filename"] as? String,
           let published = row["published"] as? Int {
            
            let enName = row["en_name"] as? String
            let marketGroupID = row["marketGroupID"] as? Int
            let categoryID = row["categoryID"] as? Int
            let groupID = row["groupID"] as? Int
            let groupName = row["group_name"] as? String
            
            let blueprint = DatabaseListItem(
                id: typeId,
                name: name,
                enName: enName,
                iconFileName: iconFileName.isEmpty ? DatabaseConfig.defaultItemIcon : iconFileName,
                published: published == 1,
                categoryID: categoryID,
                groupID: groupID,
                groupName: groupName,
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
                marketGroupID: marketGroupID,
                navigationDestination: AnyView(EmptyView())
            )
            
            self.selectedBlueprint = blueprint
            Logger.info("已加载蓝图: \(name) (ID: \(typeId))")
        } else {
            Logger.error("无法加载蓝图ID: \(blueprintId)")
        }
    }
    
    // 开始计算
    private func startCalculation() {
        guard let blueprint = selectedBlueprint,
              let structure = selectedStructure,
              let systemId = selectedSystemId else {
            return
        }
        
        // 设置计算状态
        isCalculating = true
        
        // 检查是否为反应蓝图，如果是则将效率设为0
        let isReaction = isReactionTypeBlueprint(blueprint)
        let actualTimeEfficiency = isReaction ? 0 : timeEfficiency
        let actualMaterialEfficiency = isReaction ? 0 : materialEfficiency

        // TODO: 实现蓝图计算逻辑
        print("开始计算蓝图: \(blueprint.name)")
        print("蓝图市场组ID: \(blueprint.marketGroupID ?? -1)")
        print("是否为反应蓝图: \(isReactionTypeBlueprint(blueprint))")
        print("建筑: \(structure.displayName)")
        print("建筑类型ID: \(structure.typeId)")
        print("是否为反应建筑: \(isReactionStructure(structure))")
        print("星系ID: \(systemId)")
        print("流程数: \(runs)")
        print("材料效率: \(actualMaterialEfficiency)%")
        print("时间效率: \(actualTimeEfficiency)%")
        print("角色: \(selectedCharacterName)")
        print("技能数量: \(selectedCharacterSkills.count)")
        print("建筑插件数量: \(structure.rigs.count)")
        print("建筑插件详情: \(structure.rigInfos.map { "\($0.name) (ID: \($0.id))" }.joined(separator: ", "))")
        print("设施税: \(facilityTax)")
        
        // 构建计算参数
        let calcParams = BlueprintCalcUtil.BlueprintCalcParams(
            blueprintId: blueprint.id,
            runs: runs,
            timeEfficiency: actualTimeEfficiency,
            materialEfficiency: actualMaterialEfficiency,
            facilityTypeId: structure.typeId,
            facilityRigs: structure.rigs,
            facilityTax: facilityTax / 100.0, // 将百分比转换为小数形式
            solarSystemId: systemId,
            characterSkills: selectedCharacterSkills,
            isReaction: isReaction
        )
        
        // 使用异步任务执行计算，避免阻塞UI
        Task {
            // 在后台线程执行计算
            let result = await Task.detached {
                return BlueprintCalcUtil.calculateBlueprint(params: calcParams)
            }.value
            
            // 回到主线程更新UI
            await MainActor.run {
                if result.success {
                    // 保存计算结果并显示结果页面
                    calculationResult = result
                    showResult = true
                } else {
                    Logger.warning("计算失败: \(result.errorMessage ?? "未知错误")")
                }
                
                // 重置计算状态
                isCalculating = false
            }
        }
    }
} 
