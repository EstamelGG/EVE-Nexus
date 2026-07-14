import SwiftUI

/// 精炼设置弹窗视图
struct RefinerySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var systemSecurity: OreRefineryCalculatorView.SystemSecurity
    @Binding var structure: OreRefineryCalculatorView.Structure
    @Binding var structureRigs: OreRefineryCalculatorView.StructureRigs
    @Binding var implant: OreRefineryCalculatorView.Implant
    @Binding var taxRate: Double
    @Binding var selectedCharacterSkills: [Int: Int]
    @Binding var selectedCharacterName: String
    @Binding var selectedCharacterId: Int

    @State private var taxRateText: String = ""
    @State private var showCharacterSelector = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // 星系安等选择器
                    Picker(
                        NSLocalizedString("Ore_Refinery_System_Security", comment: ""),
                        selection: $systemSecurity
                    ) {
                        ForEach(OreRefineryCalculatorView.SystemSecurity.allCases, id: \.self) {
                            security in
                            Text(security.localizedName).tag(security)
                        }
                    }
                    .pickerStyle(.menu)

                    // 建筑选择器
                    Picker(
                        NSLocalizedString("Ore_Refinery_Structure", comment: ""),
                        selection: $structure
                    ) {
                        ForEach(OreRefineryCalculatorView.Structure.allCases, id: \.self) {
                            struct_ in
                            Text(struct_.displayName).tag(struct_)
                        }
                    }
                    .pickerStyle(.menu)

                    // 建筑插件选择器
                    Picker(
                        NSLocalizedString("Ore_Refinery_Structure_Rigs", comment: ""),
                        selection: $structureRigs
                    ) {
                        ForEach(OreRefineryCalculatorView.StructureRigs.allCases, id: \.self) {
                            rig in
                            Text(rig.localizedName).tag(rig)
                        }
                    }
                    .pickerStyle(.menu)

                    // 植入体选择器
                    Picker(
                        NSLocalizedString("Ore_Refinery_Implant", comment: ""), selection: $implant
                    ) {
                        ForEach(OreRefineryCalculatorView.Implant.allCases, id: \.self) { implant in
                            Text(implant.displayName).tag(implant)
                        }
                    }
                    .pickerStyle(.menu)

                    // 建筑税率输入
                    HStack {
                        Text(NSLocalizedString("Ore_Refinery_Tax_Rate", comment: ""))
                        Spacer()
                        TextField(
                            NSLocalizedString("Ore_Refinery_Tax_Rate_Placeholder", comment: ""),
                            text: $taxRateText
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("%")
                            .foregroundColor(.secondary)
                    }
                }

                // 技能设置section
                Section(header: Text(NSLocalizedString("Fitting_Setting_Skills", comment: "技能设置"))) {
                    Button {
                        showCharacterSelector = true
                    } label: {
                        HStack {
                            Image("skill")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            Text(NSLocalizedString("Fitting_Skills_Mode", comment: "技能模式"))
                            Spacer()
                            Text(
                                selectedCharacterSkills.isEmpty
                                    ? NSLocalizedString("Fitting_Unknown_Skills", comment: "未知技能模式")
                                    : selectedCharacterName
                            )
                            .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle(NSLocalizedString("Ore_Refinery_Settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Misc_Done", comment: "")) {
                        // 保存输入的数值
                        if let newTaxRate = Double(taxRateText) {
                            taxRate = max(0, min(100, newTaxRate))
                            // 保存税率到UserDefaults
                            UserDefaultsManager.shared.refineryTaxRate = taxRate
                        }
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // 初始化文本字段的值，从UserDefaults读取保存的税率
            let savedTaxRate = UserDefaultsManager.shared.refineryTaxRate
            taxRateText = String(savedTaxRate)
            // 同时更新当前税率状态
            taxRate = savedTaxRate

            Logger.info("RefinerySettingsView onAppear - 加载保存的税率: \(savedTaxRate)%")
        }
        .onChange(of: taxRateText) { _, newValue in
            // 实时验证税率输入
            if let value = Double(newValue) {
                if value > 100 {
                    taxRateText = "100"
                } else if value < 0 {
                    taxRateText = "0"
                } else {
                    // 实时保存有效的税率
                    taxRate = value
                    UserDefaultsManager.shared.refineryTaxRate = value
                }
            }
        }

        .sheet(isPresented: $showCharacterSelector) {
            NavigationView {
                CharacterSkillsSelectorView(
                    databaseManager: DatabaseManager.shared,
                    onSelectSkills: { skills, skillModeName, characterId in
                        selectedCharacterSkills = skills
                        selectedCharacterName = skillModeName
                        selectedCharacterId = characterId
                        showCharacterSelector = false
                    }
                )
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDragIndicator(.visible)
        }
    }
}
