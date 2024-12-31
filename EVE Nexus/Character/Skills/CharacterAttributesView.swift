import SwiftUI

struct CharacterAttributesView: View {
    let characterId: Int
    @State private var attributes: CharacterAttributes?
    @State private var isLoading = true
    
    var body: some View {
        List {
            Section {
                if let attributes = attributes {
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Perception", comment: ""), value: attributes.perception)
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Memory", comment: ""), value: attributes.memory)
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Willpower", comment: ""), value: attributes.willpower)
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Intelligence", comment: ""), value: attributes.intelligence)
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Charisma", comment: ""), value: attributes.charisma)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(NSLocalizedString("Character_Attributes_Load_Failed", comment: ""))
                        .foregroundColor(.secondary)
                }
            } header: {
                Text(NSLocalizedString("Character_Attributes_Basic", comment: ""))
            }
            
            if let attributes = attributes {
                Section {
                    if let bonusRemaps = attributes.bonus_remaps {
                        HStack {
                            Text(NSLocalizedString("Character_Attributes_Bonus_Remaps", comment: ""))
                            Spacer()
                            Text("\(bonusRemaps)")
                        }
                    }
                    
                    if let lastRemapDate = attributes.last_remap_date {
                        HStack {
                            Text(NSLocalizedString("Character_Attributes_Last_Remap", comment: ""))
                            Spacer()
                            Text(lastRemapDate)
                        }
                    }
                    
                    if let cooldownDate = attributes.accrued_remap_cooldown_date {
                        HStack {
                            Text(NSLocalizedString("Character_Attributes_Next_Remap", comment: ""))
                            Spacer()
                            Text(cooldownDate)
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Character_Attributes_Remap", comment: ""))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Character_Attributes_Title", comment: ""))
        .onAppear {
            Task {
                await fetchAttributes()
            }
        }
    }
    
    private func fetchAttributes() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            attributes = try await CharacterSkillsAPI.shared.fetchAttributes(characterId: characterId)
        } catch {
            Logger.error("获取角色属性失败: \(error)")
        }
    }
}

struct AttributeRow: View {
    let name: String
    let value: Int
    
    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text("\(value)")
        }
    }
} 