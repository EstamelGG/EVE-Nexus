import SwiftUI

struct StructureSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var defaultStructures: [IndustryFacilityInfo] = []
    @State private var customStructures: [IndustryFacilityInfo] = []
    @State private var isLoading = true
    @State private var showFacilitySelector = false
    
    let onStructureSelected: (IndustryFacilityInfo) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        List {
            Section {
                Button {
                    showFacilitySelector = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                            .frame(width: 32, height: 32)
                        Text(NSLocalizedString("Structure_Selector_Add_Structure", comment: "添加建筑"))
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }
            
            Section(header: Text(NSLocalizedString("Structure_Selector_Preset_Structures", comment: "预设建筑"))) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else if defaultStructures.isEmpty {
                    Text(NSLocalizedString("Structure_Selector_No_Preset_Structures", comment: "暂无预设建筑"))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(defaultStructures) { structure in
                        StructureInfoRow(structure: structure) {
                            onStructureSelected(structure)
                        }
                    }
                }
            }
            
            if !customStructures.isEmpty {
                Section(header: Text(NSLocalizedString("Structure_Selector_Custom_Structures", comment: "自定义建筑"))) {
                    ForEach(customStructures) { structure in
                        StructureInfoRow(structure: structure) {
                            onStructureSelected(structure)
                        }
                    }
                    .onDelete { indexSet in
                        deleteCustomStructures(at: indexSet)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Structure_Selector_Title", comment: "选择建筑"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NSLocalizedString("Main_Setting_Cancel", comment: "取消")) {
                    onDismiss()
                }
            }
        }
        .onAppear {
            loadDefaultStructures()
            loadCustomStructures()
        }
        .sheet(isPresented: $showFacilitySelector) {
            StructureFacilitySelectorView(
                databaseManager: databaseManager,
                onStructureCreated: { newStructure in
                    saveCustomStructure(newStructure)
                },
                onStructureDeleted: nil,  // 在创建界面中不需要删除功能
                onDismiss: {
                    showFacilitySelector = false
                }
            )
        }
    }
    
    private func loadDefaultStructures() {
        isLoading = true
        
        // 读取默认建筑配置文件
        guard let url = Bundle.main.url(forResource: "default_structure", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let configs = try? JSONDecoder().decode([DefaultStructureConfig].self, from: data) else {
            Logger.error("无法加载默认建筑配置文件")
            isLoading = false
            return
        }
        
        // 收集所有需要查询的type_id
        let allTypeIds = configs.map { $0.structure_typeid } +
        configs.flatMap { $0.rigs }
        
        // 一次性查询所有type_id的信息
        let placeholders = String(repeating: "?,", count: allTypeIds.count).dropLast()
        let query = "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(placeholders))"
        
        if case let .success(rows) = databaseManager.executeQuery(query, parameters: allTypeIds) {
            // 创建type_id到信息的映射
            var typeInfoMap: [Int: (name: String, iconFileName: String)] = [:]
            for row in rows {
                if let typeId = row["type_id"] as? Int,
                   let name = row["name"] as? String,
                   let iconFileName = row["icon_filename"] as? String {
                    typeInfoMap[typeId] = (name: name, iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName)
                }
            }
            
            // 构建建筑信息
            var structures: [IndustryFacilityInfo] = []
            for config in configs {
                if let typeInfo = typeInfoMap[config.structure_typeid] {
                    // 构建插件信息
                    let rigInfos = config.rigs.compactMap { rigId in
                        typeInfoMap[rigId].map { (id: rigId, name: $0.name, iconFileName: $0.iconFileName) }
                    }
                    
                    let structure = IndustryFacilityInfo(
                        id: config.id,
                        typeId: config.structure_typeid,
                        name: typeInfo.name,
                        iconFileName: typeInfo.iconFileName,
                        customName: config.name.isEmpty ? nil : config.name,
                        isDefault: config.is_default == 1,
                        rigs: config.rigs,
                        rigInfos: rigInfos,
                        systemId: config.system_id
                    )
                    structures.append(structure)
                }
            }
            
            defaultStructures = structures
        } else {
            Logger.error("查询建筑信息失败")
        }
        
        isLoading = false
    }
    
    private func loadCustomStructures() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let industryFacilitiesPath = documentsPath.appendingPathComponent("IndustryFacilities")
        
        Logger.info("读取自定义建筑目录：\(industryFacilitiesPath.path)")
        
        // 创建目录（如果不存在）
        if !FileManager.default.fileExists(atPath: industryFacilitiesPath.path) {
            try? FileManager.default.createDirectory(at: industryFacilitiesPath, withIntermediateDirectories: true)
        }
        
        // 读取所有自定义建筑文件
        do {
            let files = try FileManager.default.contentsOfDirectory(at: industryFacilitiesPath, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "json" }
            
            Logger.info("找到 \(jsonFiles.count) 个自定义建筑文件")
            
            var structures: [IndustryFacilityInfo] = []
            for file in jsonFiles {
                Logger.info("读取自定义建筑文件：\(file.lastPathComponent)")
                
                if let data = try? Data(contentsOf: file),
                   let config = try? JSONDecoder().decode(DefaultStructureConfig.self, from: data) {
                    
                    // 查询建筑信息
                    let allTypeIds = [config.structure_typeid] + config.rigs
                    let placeholders = String(repeating: "?,", count: allTypeIds.count).dropLast()
                    let query = "SELECT type_id, name, icon_filename FROM types WHERE type_id IN (\(placeholders))"
                    
                    if case let .success(rows) = databaseManager.executeQuery(query, parameters: allTypeIds) {
                        var typeInfoMap: [Int: (name: String, iconFileName: String)] = [:]
                        for row in rows {
                            if let typeId = row["type_id"] as? Int,
                               let name = row["name"] as? String,
                               let iconFileName = row["icon_filename"] as? String {
                                typeInfoMap[typeId] = (name: name, iconFileName: iconFileName.isEmpty ? "not_found" : iconFileName)
                            }
                        }
                        
                        if let typeInfo = typeInfoMap[config.structure_typeid] {
                            let rigInfos = config.rigs.compactMap { rigId in
                                typeInfoMap[rigId].map { (id: rigId, name: $0.name, iconFileName: $0.iconFileName) }
                            }
                            
                            let structure = IndustryFacilityInfo(
                                id: config.id,
                                typeId: config.structure_typeid,
                                name: typeInfo.name,
                                iconFileName: typeInfo.iconFileName,
                                customName: config.name.isEmpty ? nil : config.name,
                                isDefault: false,
                                rigs: config.rigs,
                                rigInfos: rigInfos,
                                systemId: config.system_id
                            )
                            structures.append(structure)
                        }
                    }
                }
            }
            
            customStructures = structures
        } catch {
            Logger.error("加载自定义建筑失败: \(error)")
        }
    }
    
    private func saveCustomStructure(_ structure: IndustryFacilityInfo) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let industryFacilitiesPath = documentsPath.appendingPathComponent("IndustryFacilities")
        
        // 创建目录（如果不存在）
        if !FileManager.default.fileExists(atPath: industryFacilitiesPath.path) {
            try? FileManager.default.createDirectory(at: industryFacilitiesPath, withIntermediateDirectories: true)
        }
        
        // 创建配置对象
        let config = DefaultStructureConfig(
            id: structure.id,  // 使用结构的实际ID
            is_default: 0,
            structure_typeid: structure.typeId,
            rigs: structure.rigs,
            name: structure.customName ?? "",
            system_id: structure.systemId
        )
        
        // 生成文件名
        let fileName = "facility_\(structure.typeId)_\(UUID().uuidString).json"
        let fileURL = industryFacilitiesPath.appendingPathComponent(fileName)
        
        // 保存到文件
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: fileURL)
            
            // 添加到自定义建筑列表
            customStructures.append(structure)
            
            Logger.info("自定义建筑保存成功: \(fileName)")
        } catch {
            Logger.error("保存自定义建筑失败: \(error)")
        }
    }
    
    private func deleteCustomStructures(at offsets: IndexSet) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let industryFacilitiesPath = documentsPath.appendingPathComponent("IndustryFacilities")
        
        for index in offsets {
            let structure = customStructures[index]
            
            // 读取所有自定义建筑文件，找到匹配的文件
            do {
                let files = try FileManager.default.contentsOfDirectory(at: industryFacilitiesPath, includingPropertiesForKeys: nil)
                let jsonFiles = files.filter { $0.pathExtension == "json" }
                
                for fileURL in jsonFiles {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let config = try JSONDecoder().decode(DefaultStructureConfig.self, from: data)
                        
                        // 检查是否是我们要删除的建筑（通过ID匹配）
                        if config.id == structure.id {
                            // 删除文件
                            try FileManager.default.removeItem(at: fileURL)
                            Logger.info("删除自定义建筑文件成功: \(fileURL.lastPathComponent)")
                            break
                        }
                    } catch {
                        Logger.error("读取或解析建筑文件失败: \(fileURL.lastPathComponent), 错误: \(error)")
                        continue
                    }
                }
                
                // 从列表中移除
                customStructures.remove(at: index)
                
            } catch {
                Logger.error("删除自定义建筑失败: \(error)")
            }
        }
    }
}

// 建筑信息行视图
struct StructureInfoRow: View {
    let structure: IndustryFacilityInfo
    let onSelect: () -> Void
    @State private var showInfoSheet = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 建筑图标
            IconManager.shared.loadImage(for: structure.iconFileName)
                .resizable()
                .frame(width: 40, height: 40)
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 4) {
                // 第一行：建筑名称
                Text(structure.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // 星系信息 - 如果是自定义建筑且有星系设置
                if !structure.isDefault, let systemId = structure.systemId {
                    let systemInfo = getSystemInfo(systemId: systemId, databaseManager: DatabaseManager.shared)
                    HStack(spacing: 4) {
                        if let security = systemInfo.security {
                            Text(formatSystemSecurity(security))
                                .foregroundColor(getSecurityColor(security))
                                .font(.system(.caption2, design: .monospaced))
                                .fontWeight(.medium)
                        }
                        
                        if let systemName = systemInfo.name {
                            Text(systemName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(NSLocalizedString("Structure_Facility_Selector_Unknown_System", comment: "未知星系"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                // 插件信息 - 只显示前3个
                if !structure.rigInfos.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        // 显示前3个插件
                        ForEach(Array(structure.rigInfos.prefix(3)), id: \.id) { rigInfo in
                            HStack(spacing: 2) {
                                IconManager.shared.loadImage(for: rigInfo.iconFileName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                                    .cornerRadius(2)
                                Text(rigInfo.name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        // 如果有更多插件，显示"等其他 X个"
                        if structure.rigInfos.count > 3 {
                            let remainingCount = structure.rigInfos.count - 3
                            Text(String(format: NSLocalizedString("Structure_Selector_Other_Rigs", comment: "等其他 %d 个"), remainingCount))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                // 如果没有插件和服务，显示无
                if structure.rigInfos.isEmpty {
                    Text(NSLocalizedString("Structure_Selector_No_Rigs", comment: "无"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Info按钮
            Button(action: {
                showInfoSheet = true
            }) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.system(size: 20))
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .sheet(isPresented: $showInfoSheet) {
            StructureInfoDetailView(structure: structure)
        }
    }
}

// 建筑详细信息视图
struct StructureInfoDetailView: View {
    let structure: IndustryFacilityInfo
    @Environment(\.dismiss) private var dismiss
    @StateObject private var databaseManager = DatabaseManager.shared
    
    
    
    var body: some View {
        NavigationStack {
            List {
                // 建筑基本信息
                Section {
                    NavigationLink {
                        ItemInfoMap.getItemInfoView(
                            itemID: structure.typeId,
                            databaseManager: databaseManager
                        )
                    } label: {
                        HStack(spacing: 12) {
                            IconManager.shared.loadImage(for: structure.iconFileName)
                                .resizable()
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(structure.displayName)
                                    .font(.title2)
                                    .foregroundColor(.primary)
                                
                                Text("ID: \(structure.typeId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                }
                
                // 星系信息
                if let systemId = structure.systemId {
                    Section(header: Text(NSLocalizedString("Structure_Info_System", comment: "星系"))) {
                        HStack(spacing: 12) {
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
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .fontWeight(.semibold)
                                } else {
                                    Text(NSLocalizedString("Structure_Info_Unknown_System", comment: "未知星系"))
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .fontWeight(.semibold)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // 所有插件列表
                if !structure.rigInfos.isEmpty {
                    Section(header: Text(NSLocalizedString("Structure_Info_All_Rigs", comment: "所有插件"))) {
                        ForEach(structure.rigInfos, id: \.id) { rigInfo in
                            NavigationLink {
                                ItemInfoMap.getItemInfoView(
                                    itemID: rigInfo.id,
                                    databaseManager: databaseManager
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    IconManager.shared.loadImage(for: rigInfo.iconFileName)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                        .cornerRadius(6)
                                    
                                    Text(rigInfo.name)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                }
                            }
                        }
                    }
                } else {
                    Section(header: Text(NSLocalizedString("Structure_Info_Rigs", comment: "插件"))) {
                        Text(NSLocalizedString("Structure_Selector_No_Rigs", comment: "无"))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Structure_Info_Detail_Title", comment: "建筑详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Structure_Info_Done", comment: "完成")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
