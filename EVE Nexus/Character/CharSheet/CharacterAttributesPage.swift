import SwiftUI

/// 人物表单子页面：技能属性（五维属性，懒加载）
struct CharacterAttributesPage: View {
    let character: EVECharacterInfo

    @State private var attributes: CharacterAttributes?
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                if let attributes {
                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Perception", comment: ""),
                        icon: "perception", value: attributes.perception
                    )
                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Memory", comment: ""),
                        icon: "memory", value: attributes.memory
                    )
                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Willpower", comment: ""),
                        icon: "willpower", value: attributes.willpower
                    )
                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Intelligence", comment: ""),
                        icon: "intelligence", value: attributes.intelligence
                    )
                    AttributeRow(
                        name: NSLocalizedString("Character_Attribute_Charisma", comment: ""),
                        icon: "charisma", value: attributes.charisma
                    )
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .transition(.opacity)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .navigationTitle(NSLocalizedString("Character_Attributes_Basic", comment: ""))
        .task {
            await load()
        }
        .refreshable {
            await load(forceRefresh: true)
        }
    }

    private func load(forceRefresh: Bool = false) async {
        let attrs = try? await CharacterSkillsAPI.shared.fetchAttributes(
            characterId: character.CharacterID, forceRefresh: forceRefresh
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            attributes = attrs
            isLoading = false
        }
    }
}
