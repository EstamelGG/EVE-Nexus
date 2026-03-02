import SwiftUI

/// 装配模拟默认角色设置 - 选择新建装配时默认使用的技能数据来源
/// 「当前人物」随主界面切换而变，不固定
struct FittingDefaultSkillSettingView: View {
    @AppStorage("skillsModePreference") private var skillsModePreference: String = "current_char"
    @AppStorage("selectedSkillCharacterId") private var selectedSkillCharacterId: Int = 0
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0

    var body: some View {
        List {
            // 当前人物（不固定，随主界面切换）
            Section(header: Text(NSLocalizedString("Fitting_Default_Skill_Source_Section", comment: "角色技能来源"))) {
                Button {
                    skillsModePreference = "current_char"
                    selectedSkillCharacterId = 0
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("Fitting_Current_Character", comment: "当前人物"))
                                .foregroundColor(.primary)
                            Text(NSLocalizedString("Fitting_Default_Current_Char_Subtitle", comment: "跟随主界面当前选择"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if skillsModePreference == "current_char" {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }

            // 虚拟技能等级
            Section(header: Text(NSLocalizedString("Fitting_Virtual_Characters", comment: "虚拟角色"))) {
                ForEach((0 ... 5).reversed(), id: \.self) { level in
                    Button {
                        skillsModePreference = "all\(level)"
                        selectedSkillCharacterId = 0
                    } label: {
                        HStack {
                            Image("skill_lv_\(level)")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .cornerRadius(6)
                            Text(
                                String(
                                    format: NSLocalizedString("Fitting_All_Skills", comment: "全n级"),
                                    level
                                )
                            )
                            .foregroundColor(.primary)
                            Spacer()
                            if skillsModePreference == "all\(level)" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Fitting_Setting_Default_Character", comment: "默认角色"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 若之前为「指定角色」模式，重置为当前人物（已移除指定角色选项）
            if skillsModePreference == "character" {
                skillsModePreference = "current_char"
                selectedSkillCharacterId = 0
            }
        }
    }
}
