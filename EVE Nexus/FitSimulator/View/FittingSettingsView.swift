import SwiftUI

struct FittingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fittingName: String = ""
    let databaseManager: DatabaseManager
    let shipTypeID: Int
    @State private var shipItem: DatabaseListItem?
    @State private var fittingData: [String: Any]
    let onNameChanged: ([String: Any]) -> Void
    @ObservedObject var viewModel: FittingEditorViewModel
    
    @AppStorage("skillsModePreference") private var skillsMode = "current_char"
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @State private var selectedCharacterId: Int? = nil
    var onSkillModeChanged: (() -> Void)?

    init(
        databaseManager: DatabaseManager, shipTypeID: Int, fittingName: String,
        fittingData: [String: Any], onNameChanged: @escaping ([String: Any]) -> Void,
        onSkillModeChanged: (() -> Void)? = nil, viewModel: FittingEditorViewModel
    ) {
        self.databaseManager = databaseManager
        self.shipTypeID = shipTypeID
        self._fittingName = State(initialValue: fittingName)
        self._fittingData = State(initialValue: fittingData)
        self.onNameChanged = onNameChanged
        self.onSkillModeChanged = onSkillModeChanged
        self.viewModel = viewModel
    }
    
    private var skillModeText: String {
        if skillsMode == "current_char" {
            // 获取当前角色名称
            if currentCharacterId != 0 {
                if let character = EVELogin.shared.getCharacterByID(currentCharacterId)?.character {
                    return character.CharacterName
                }
            }
            skillsMode = "all5"
        } else if skillsMode == "all5" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: "全5级"), 5)
        } else if skillsMode == "all4" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 4)
        } else if skillsMode == "all3" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 3)
        } else if skillsMode == "all2" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 2)
        } else if skillsMode == "all1" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 1)
        } else if skillsMode == "all0" {
            return String(format: NSLocalizedString("Fitting_All_Skills", comment: ""), 0)
        } else if skillsMode == "character" {
            let charId = UserDefaults.standard.integer(forKey: "selectedSkillCharacterId")
            let chars = CharacterSkillsUtils.getAllCharacters(excludeCurrentCharacter: false)
            if let character = chars.first(where: { $0.id == charId }) {
                return character.name
            }
        }
        return NSLocalizedString("Fitting_Unknown_Skills", comment: "未知技能模式")
    }

    var body: some View {
        List {
            Section(header: Text(NSLocalizedString("Fitting_Setting_Ship", comment: ""))) {
                TextField(NSLocalizedString("Fitting_Name", comment: ""), text: $fittingName)
                    .textFieldStyle(.plain)
                    .onChange(of: fittingName) { _, newValue in
                        var updatedData = fittingData
                        updatedData["name"] = newValue
                        fittingData = updatedData
                        onNameChanged(updatedData)
                    }

                if let shipItem = shipItem {
                    NavigationLink {
                        ShowItemInfo(
                            databaseManager: databaseManager,
                            itemID: shipTypeID
                        )
                    } label: {
                        DatabaseListItemView(
                            item: shipItem,
                            showDetails: true
                        )
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            
            Section(header: Text(NSLocalizedString("Fitting_Setting_Skills", comment: "技能设置"))) {
                NavigationLink {
                    CharacterSkillsSelectorView(
                        databaseManager: databaseManager,
                        onSelectSkills: { skills, skillModeName, characterId in
                            // 更新技能模式
                            if characterId == 0 {
                                // 虚拟角色情况 (All 5/4/3/2/1/0)
                                if skillModeName.contains("5") {
                                    skillsMode = "all5"
                                } else if skillModeName.contains("4") {
                                    skillsMode = "all4"
                                } else if skillModeName.contains("3") {
                                    skillsMode = "all3"
                                } else if skillModeName.contains("2") {
                                    skillsMode = "all2"
                                } else if skillModeName.contains("1") {
                                    skillsMode = "all1"
                                } else if skillModeName.contains("0") {
                                    skillsMode = "all0"
                                }
                                selectedCharacterId = nil
                            } else if characterId == currentCharacterId {
                                // 当前角色情况
                                skillsMode = "current_char"
                                selectedCharacterId = nil
                            } else {
                                // 其他角色情况
                                skillsMode = "character"
                                selectedCharacterId = characterId
                                UserDefaults.standard.set(characterId, forKey: "selectedSkillCharacterId")
                            }
                            
                            // 执行技能模式更改回调
                            onSkillModeChanged?()
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
                        Text(skillModeText)
                            .foregroundColor(.secondary)
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            
            Section(header: Text(NSLocalizedString("Fitting_Setting_Implants", comment: "植入体设置"))) {
                NavigationLink {
                    ImplantSettingsView(
                        databaseManager: databaseManager,
                        viewModel: viewModel
                    )
                } label: {
                    HStack {
                        Image("implants")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        Text(NSLocalizedString("Fitting_Implants_Mode", comment: "查看/编辑植入体"))
                    }
                }
            }.listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .navigationTitle(NSLocalizedString("Main_Setting_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                }
            }
        }
        .onAppear {
            let items = databaseManager.loadMarketItems(
                whereClause: "t.type_id = ?",
                parameters: [shipTypeID]
            )
            if let item = items.first {
                shipItem = item
            }
            
            if skillsMode == "character" {
                selectedCharacterId = UserDefaults.standard.integer(forKey: "selectedSkillCharacterId")
            }
        }
    }
} 
