import SwiftUI

/// 角色名称文本：扫描 refreshTokenExpired 标签，过期则追加本地化的"（已过期）"后缀并显示为红色
struct CharacterNameText: View {
    let characterId: Int
    let name: String

    private var isExpired: Bool {
        EVELogin.shared.getCharacterByID(characterId)?.character.refreshTokenExpired ?? false
    }

    private var displayText: String {
        guard isExpired else { return name }
        return String(
            format: NSLocalizedString("Character_Name_Expired_Format", comment: "角色名（已过期）格式，%@ 为角色名"),
            name
        )
    }

    var body: some View {
        Text(displayText)
            .foregroundColor(isExpired ? .red : .primary)
    }
}

/// 多人物聚合功能中通用的角色选择列表 Section。
///
/// 包含：角色列表（头像 + 名称 + 选中勾号）+ 全选/全不选按钮。
struct MultiCharacterSelectionSection: View {
    let availableCharacters: [(id: Int, name: String)]
    @Binding var selectedCharacterIds: Set<Int>

    var body: some View {
        Section(
            header: Text(
                NSLocalizedString("MultiCharacter_Select_Characters", comment: "选择角色")
            )
        ) {
            ForEach(availableCharacters, id: \.id) { character in
                Button {
                    if selectedCharacterIds.contains(character.id) {
                        selectedCharacterIds.remove(character.id)
                    } else {
                        selectedCharacterIds.insert(character.id)
                    }
                } label: {
                    HStack {
                        CharacterPortraitView(characterId: character.id)
                            .padding(.trailing, 8)
                        CharacterNameText(characterId: character.id, name: character.name)
                        Spacer()
                        if selectedCharacterIds.contains(character.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                if selectedCharacterIds.count == availableCharacters.count {
                    selectedCharacterIds = []
                } else {
                    selectedCharacterIds = Set(availableCharacters.map(\.id))
                }
            } label: {
                HStack {
                    Text(NSLocalizedString("MultiCharacter_Select_All", comment: "全选"))
                    Spacer()
                    if selectedCharacterIds.count == availableCharacters.count {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
