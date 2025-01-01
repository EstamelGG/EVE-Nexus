import SwiftUI

struct CharacterAttributesView: View {
    let characterId: Int
    @State private var attributes: CharacterAttributes?
    @State private var isLoading = true
    
    var body: some View {
        List {
            Section {
                if let attributes = attributes {
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Perception", comment: ""), icon: "perception", value: attributes.perception)
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Memory", comment: ""), icon: "memory", value: attributes.memory)
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Willpower", comment: ""), icon: "willpower", value: attributes.willpower)
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Intelligence", comment: ""), icon: "intelligence", value: attributes.intelligence)
                    AttributeRow(name: NSLocalizedString("Character_Attribute_Charisma", comment: ""), icon: "charisma", value: attributes.charisma)
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
                    
                    if let cooldownDate = attributes.accrued_remap_cooldown_date {
                        HStack {
                            Text(NSLocalizedString("Character_Attributes_Next_Remap", comment: ""))
                            Spacer()
                            Text(formatNextRemapTime(cooldownDate))
                        }
                    }
                } header: {
                    Text(NSLocalizedString("Character_Attributes_Remap", comment: ""))
                }
            }
        }
        .refreshable {
            await fetchAttributes(forceRefresh: true)
        }
        .navigationTitle(NSLocalizedString("Character_Attributes_Title", comment: ""))
        .onAppear {
            Task {
                await fetchAttributes()
            }
        }
    }
    
    private func formatNextRemapTime(_ dateString: String) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        guard let date = dateFormatter.date(from: dateString) else {
            return NSLocalizedString("Character_Never", comment: "")
        }
        
        let now = Date()
        if now > date {
            return NSLocalizedString("Character_Attributes_Ready_Now", comment: "")
        }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day, .hour], from: now, to: date)
        
        if let months = components.month, months > 0 {
            if let days = components.day, days > 0 {
                return String(format: NSLocalizedString("Time_Months_Days", comment: ""), months, days)
            }
            return String(format: NSLocalizedString("Time_Months", comment: ""), months)
        }
        
        if let days = components.day, days > 0 {
            if let hours = components.hour, hours > 0 {
                return String(format: NSLocalizedString("Time_Days_Hours", comment: ""), days, hours)
            }
            return String(format: NSLocalizedString("Time_Days", comment: ""), days)
        }
        
        if let hours = components.hour, hours > 0 {
            return String(format: NSLocalizedString("Time_Hours", comment: ""), hours)
        }
        
        return NSLocalizedString("Character_Attributes_Ready_Now", comment: "")
    }
    
    private func fetchAttributes(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            attributes = try await CharacterSkillsAPI.shared.fetchAttributes(characterId: characterId, forceRefresh: forceRefresh)
        } catch {
            Logger.error("获取角色属性失败: \(error)")
        }
    }
}

struct AttributeRow: View {
    let name: String
    let icon: String
    let value: Int
    
    var body: some View {
        HStack {
            Image(icon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)
                .drawingGroup()
            Text(name)
            Spacer()
            Text("\(value)")
        }
    }
}
