import SwiftUI

/// 单个技能要求行
struct SkillRequirementRow: View {
    let skillID: Int
    let level: Int
    let timeMultiplier: Double?
    @ObservedObject var databaseManager: DatabaseManager
    let currentLevel: Int?

    private func skillPoints(at level: Int) -> Int {
        guard let multiplier = timeMultiplier,
              level > 0,
              level <= SkillTreeManager.levelBasePoints.count
        else { return 0 }
        return Int(Double(SkillTreeManager.levelBasePoints[level - 1]) * multiplier)
    }

    private var skillPointsText: String {
        let points = skillPoints(at: level)
        return points > 0 ? "\(FormatUtil.format(Double(points))) SP" : ""
    }

    var body: some View {
        if let skillName = SkillTreeManager.shared.getSkillName(for: skillID) {
            NavigationLink {
                ItemInfoMap.getItemInfoView(
                    itemID: skillID,
                    databaseManager: databaseManager
                )
            } label: {
                HStack {
                    statusIcon

                    VStack(alignment: .leading) {
                        Text(skillName)
                            .font(.body)
                        statusCaption
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(
                        String.localizedStringWithFormat(
                            NSLocalizedString("Misc_Level", comment: "lv%d"),
                            level
                        )
                    )
                    .font(.body)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if currentLevel == nil {
            ProgressView()
                .frame(width: 32, height: 32)
                .scaleEffect(0.8)
        } else if let currentLevel, currentLevel == -2 {
            Image("skill")
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(Circle())
        } else if let currentLevel, currentLevel == -1 {
            Image(systemName: "xmark.circle.fill")
                .frame(width: 32, height: 32)
                .foregroundColor(.red)
        } else if let currentLevel, currentLevel >= level {
            Image(systemName: "checkmark.circle.fill")
                .frame(width: 32, height: 32)
                .foregroundColor(.green)
        } else {
            Image(systemName: "circle")
                .frame(width: 32, height: 32)
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private var statusCaption: some View {
        if currentLevel == nil {
            Text(NSLocalizedString("Misc_Loading", comment: ""))
        } else if let currentLevel, currentLevel == -2 {
            if !skillPointsText.isEmpty {
                Text(skillPointsText)
            }
        } else if let currentLevel, currentLevel >= -1, currentLevel < level {
            let currentSP = skillPoints(at: currentLevel)
            let requiredSP = skillPoints(at: level)
            Text(
                "\(FormatUtil.format(Double(currentSP)))/\(FormatUtil.format(Double(requiredSP))) SP"
            )
        } else if !skillPointsText.isEmpty {
            Text(skillPointsText)
        }
    }
}

/// 技能要求组显示组件
struct SkillRequirementsView: View {
    let typeID: Int
    let groupName: String
    @ObservedObject var databaseManager: DatabaseManager
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    @StateObject private var skillsManager = SharedSkillsManager.shared
    @State private var characterAttributes: CharacterAttributes?

    private var requirements: [(skillID: Int, level: Int, timeMultiplier: Double?)] {
        SkillTreeManager.shared.getDeduplicatedSkillRequirements(
            for: typeID,
            databaseManager: databaseManager
        )
    }

    private func points(level: Int, multiplier: Double?) -> Int? {
        guard let multiplier,
              level > 0,
              level <= SkillTreeManager.levelBasePoints.count
        else { return nil }
        return Int(Double(SkillTreeManager.levelBasePoints[level - 1]) * multiplier)
    }

    private var totalPoints: Int {
        requirements.reduce(0) { total, skill in
            total + (points(level: skill.level, multiplier: skill.timeMultiplier) ?? 0)
        }
    }

    private var missingPoints: Int {
        requirements.reduce(0) { total, skill in
            guard let requiredPoints = points(level: skill.level, multiplier: skill.timeMultiplier),
                  let currentLevel = skillsManager.getSkillLevel(for: skill.skillID),
                  currentLevel != -2,
                  currentLevel < skill.level
            else { return total }

            let currentPoints =
                currentLevel > 0
                    ? (points(level: currentLevel, multiplier: skill.timeMultiplier) ?? 0) : 0
            return total + (requiredPoints - currentPoints)
        }
    }

    private var unmetSkillAttributes: [Int: (primary: Int, secondary: Int)] {
        let unmetSkillIDs = requirements.compactMap { requirement -> Int? in
            guard let currentLevel = skillsManager.getSkillLevel(for: requirement.skillID),
                  currentLevel != -2,
                  currentLevel < requirement.level
            else { return nil }
            return requirement.skillID
        }
        guard !unmetSkillIDs.isEmpty else { return [:] }
        return SkillTreeManager.shared.trainingAttributes(forSkillIDs: unmetSkillIDs)
    }

    private var estimatedTrainingTime: TimeInterval {
        guard let attributes = characterAttributes, missingPoints > 0 else { return 0 }

        let skillAttributesMap = unmetSkillAttributes
        var totalTime: TimeInterval = 0

        for requirement in requirements {
            guard let currentLevel = skillsManager.getSkillLevel(for: requirement.skillID),
                  currentLevel != -2,
                  currentLevel < requirement.level,
                  let skillAttrs = skillAttributesMap[requirement.skillID],
                  let pointsPerHour = SkillTrainingCalculator.calculateTrainingRate(
                      primaryAttrId: skillAttrs.primary,
                      secondaryAttrId: skillAttrs.secondary,
                      attributes: attributes
                  ),
                  let requiredPoints = points(
                      level: requirement.level,
                      multiplier: requirement.timeMultiplier
                  )
            else { continue }

            let currentPoints =
                currentLevel > 0
                    ? (points(level: currentLevel, multiplier: requirement.timeMultiplier) ?? 0)
                    : 0
            let missingSkillPoints = requiredPoints - currentPoints
            guard missingSkillPoints > 0, pointsPerHour > 0 else { continue }

            totalTime += Double(missingSkillPoints) / Double(pointsPerHour) * 3600
        }

        return totalTime
    }

    private var footerText: String {
        let total = "\(NSLocalizedString("Misc_InAll", comment: "")): \(FormatUtil.format(Double(totalPoints))) SP"
        if currentCharacterId == 0 || missingPoints == 0 {
            return total
        }
        return "\(total), \(NSLocalizedString("Misc_Need", comment: "")): \(FormatUtil.format(Double(missingPoints))) SP"
    }

    var body: some View {
        if !requirements.isEmpty {
            Section(
                header: HStack {
                    Text(groupName)
                        .font(.headline)
                    if currentCharacterId != 0 && missingPoints > 0 && estimatedTrainingTime > 0 {
                        Spacer()
                        Text("(\(FormatUtil.formatCompactDuration(estimatedTrainingTime)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                },
                footer: Text(footerText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            ) {
                ForEach(requirements, id: \.skillID) { requirement in
                    SkillRequirementRow(
                        skillID: requirement.skillID,
                        level: requirement.level,
                        timeMultiplier: requirement.timeMultiplier,
                        databaseManager: databaseManager,
                        currentLevel: skillsManager.getSkillLevel(for: requirement.skillID)
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
            .onAppear {
                loadCharacterAttributes()
            }
        }
    }

    private func loadCharacterAttributes() {
        guard currentCharacterId != 0 else {
            characterAttributes = nil
            return
        }

        Task {
            do {
                let attributes = try await CharacterSkillsAPI.shared.fetchAttributes(
                    characterId: currentCharacterId,
                    forceRefresh: false
                )
                await MainActor.run {
                    characterAttributes = attributes
                }
            } catch {
                Logger.error("获取角色属性失败: \(error)")
                await MainActor.run {
                    characterAttributes = nil
                }
            }
        }
    }
}
