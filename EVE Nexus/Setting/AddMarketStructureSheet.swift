import SwiftUI

// MARK: - 添加市场建筑 Sheet

struct AddMarketStructureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCharacter: EVECharacterInfo?
    @State private var selectedStructure: SearcherView.SearchResult?
    @State private var showingCharacterSelector = false
    @State private var showingStructureSelector = false
    
    // 获取所有已登录的角色
    private var availableCharacters: [EVECharacterInfo] {
        let characterAuths = EVELogin.shared.loadCharacters()
        return characterAuths.map { $0.character }
    }
    
    // 获取当前登录的角色
    private var currentCharacter: EVECharacterInfo? {
        let currentCharacterId = UserDefaults.standard.integer(forKey: "currentCharacterId")
        return availableCharacters.first { $0.CharacterID == currentCharacterId }
    }
    
    // 检查是否可以完成添加
    private var canComplete: Bool {
        selectedCharacter != nil && selectedStructure != nil
    }
    
    var body: some View {
        NavigationView {
            List {
                // 选择人物 Section
                Section(header: Text(NSLocalizedString("Market_Structure_Select_Character_Section", comment: ""))) {
                    Button(action: {
                        showingCharacterSelector = true
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Market_Structure_Select_Character_Button", comment: ""))
                                    .foregroundColor(.primary)
                                
                                if let character = selectedCharacter {
                                    Text(String(format: NSLocalizedString("Market_Structure_Select_Character_Selected", comment: ""), character.CharacterName))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if let character = selectedCharacter {
                                HStack(spacing: 8) {
                                    UniversePortrait(
                                        id: character.CharacterID,
                                        type: .character,
                                        size: 64,
                                        displaySize: 32
                                    )
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(16)
                                    
                                    Text(character.CharacterName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                // 选择建筑 Section
                Section(header: Text(NSLocalizedString("Market_Structure_Select_Structure_Section", comment: ""))) {
                    Button(action: {
                        if selectedCharacter != nil {
                            showingStructureSelector = true
                        }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(NSLocalizedString("Market_Structure_Select_Structure_Button", comment: ""))
                                    .foregroundColor(selectedCharacter != nil ? .primary : .secondary)
                                
                                if let structure = selectedStructure {
                                    Text(String(format: NSLocalizedString("Market_Structure_Select_Structure_Selected", comment: ""), structure.name))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else if selectedCharacter == nil {
                                    Text(NSLocalizedString("Market_Structure_Select_Character_First", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedStructure != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundColor(selectedCharacter != nil ? .secondary : .gray)
                                    .font(.caption)
                            }
                        }
                    }
                    .disabled(selectedCharacter == nil)
                }
            }
            .navigationTitle(NSLocalizedString("Main_Setting_Market_Structure_Add_Title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Market_Structure_Sheet_Cancel", comment: "")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Market_Structure_Sheet_Complete", comment: "")) {
                        addStructure()
                    }
                    .disabled(!canComplete)
                }
            }
        }
        .sheet(isPresented: $showingCharacterSelector) {
            CharacterSelectorSheet(selectedCharacter: $selectedCharacter)
        }
        .sheet(isPresented: $showingStructureSelector) {
            if let character = selectedCharacter {
                StructureSelectorSheet(
                    character: character,
                    selectedStructure: $selectedStructure
                )
            }
        }
        .onAppear {
            // 默认选择当前登录的角色
            if selectedCharacter == nil {
                selectedCharacter = currentCharacter
            }
        }
    }
    
    private func addStructure() {
        guard let character = selectedCharacter,
              let structure = selectedStructure,
              let locationInfo = structure.locationInfo else {
            return
        }
        
        // 通过名称查询获取systemId和regionId
        let systemId = getSystemId(from: locationInfo.systemName)
        let regionId = getRegionId(from: locationInfo.regionName)
        
        let marketStructure = MarketStructure(
            structureId: structure.id,
            structureName: structure.name,
            characterId: character.CharacterID,
            characterName: character.CharacterName,
            systemId: systemId,
            regionId: regionId,
            security: locationInfo.security,
            iconFilename: structure.typeInfo  // 传递图标文件名
        )
        
        MarketStructureManager.shared.addStructure(marketStructure)
        dismiss()
    }
    
    // 通过系统名称获取系统ID
    private func getSystemId(from systemName: String) -> Int {
        let query = """
            SELECT solarSystemID
            FROM solarsystems
            WHERE solarSystemName = ?
        """
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [systemName]),
           let row = rows.first,
           let systemId = row["solarSystemID"] as? Int {
            return systemId
        }
        
        Logger.error("无法找到系统ID，系统名称: \(systemName)")
        return 0
    }
    
    // 通过星域名称获取星域ID
    private func getRegionId(from regionName: String) -> Int {
        let query = """
            SELECT regionID
            FROM regions
            WHERE regionName = ?
        """
        
        if case let .success(rows) = DatabaseManager.shared.executeQuery(query, parameters: [regionName]),
           let row = rows.first,
           let regionId = row["regionID"] as? Int {
            return regionId
        }
        
        Logger.error("无法找到星域ID，星域名称: \(regionName)")
        return 0
    }
}

// MARK: - 角色选择 Sheet

struct CharacterSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedCharacter: EVECharacterInfo?
    
    private var availableCharacters: [EVECharacterInfo] {
        let characterAuths = EVELogin.shared.loadCharacters()
        return characterAuths.map { $0.character }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(availableCharacters, id: \.CharacterID) { character in
                    CharacterSelectorRowView(
                        character: character,
                        isSelected: selectedCharacter?.CharacterID == character.CharacterID
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedCharacter = character
                        dismiss()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("Market_Structure_Character_Selector_Title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Market_Structure_Sheet_Cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 角色选择行视图

struct CharacterSelectorRowView: View {
    let character: EVECharacterInfo
    let isSelected: Bool
    
    @State private var corporationInfo: CorporationInfo?
    @State private var corporationLogo: UIImage?
    @State private var isLoadingCorporation = false
    
    var body: some View {
        HStack(spacing: 12) {
            UniversePortrait(
                id: character.CharacterID,
                type: .character,
                size: 64,
                displaySize: 40
            )
            .frame(width: 40, height: 40)
            .cornerRadius(20)
            
            VStack(alignment: .leading, spacing: 4) {
                // 角色名称
                Text(character.CharacterName)
                    .font(.body)
                    .foregroundColor(.primary)
                
                // 军团信息
                if isLoadingCorporation {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                                                 Text(NSLocalizedString("Market_Structure_Loading_Corporation", comment: ""))
                             .font(.caption)
                             .foregroundColor(.secondary)
                    }
                } else if let corporationInfo = corporationInfo {
                    HStack(spacing: 4) {
                        if let logo = corporationLogo {
                            Image(uiImage: logo)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        } else {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 16, height: 16)
                        }
                        Text("[\(corporationInfo.ticker)] \(corporationInfo.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "building.2")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .frame(width: 16, height: 16)
                                                 Text(NSLocalizedString("Market_Structure_Unknown_Corporation", comment: ""))
                             .font(.caption)
                             .foregroundColor(.gray)
                    }
                }
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadCorporationInfo()
        }
    }
    
    private func loadCorporationInfo() {
        guard let corporationId = character.corporationId, !isLoadingCorporation else {
            return
        }
        
        isLoadingCorporation = true
        
        Task {
            do {
                // 并发加载军团信息和图标
                async let corpInfoTask = CorporationAPI.shared.fetchCorporationInfo(
                    corporationId: corporationId
                )
                async let corpLogoTask = CorporationAPI.shared.fetchCorporationLogo(
                    corporationId: corporationId, size: 64
                )
                
                let (info, logo) = try await (corpInfoTask, corpLogoTask)
                
                await MainActor.run {
                    self.corporationInfo = info
                    self.corporationLogo = logo
                    self.isLoadingCorporation = false
                }
            } catch {
                Logger.error("加载军团信息失败: \(error)")
                await MainActor.run {
                    self.isLoadingCorporation = false
                }
            }
        }
    }
} 
