import SwiftUI

struct CharacterEmploymentHistoryView: View {
    let history: [CharacterEmploymentHistory]
    let corporationNamesCache: [Int: String]
    let character: EVECharacterInfo
    let isLoadingCorpNames: Bool
    /// 雇佣记录本身是否在加载（加载期间显示加载指示器，不显示"无数据"）
    let isLoading: Bool
    @ObservedObject var allianceCache: EmploymentAllianceCache
    let npcCorporationIds: Set<Int>

    var body: some View {
        if isLoading {
            HStack(spacing: 8) {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Text(NSLocalizedString("Misc_Loading", comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .transition(.opacity)
        } else if history.isEmpty {
            ContentUnavailableView {
                Label(
                    NSLocalizedString("Misc_No_Data", comment: "无数据"),
                    systemImage: "exclamationmark.triangle"
                )
            }
            .transition(.opacity)
        } else {
            ForEach(Array(history.enumerated()), id: \.element.record_id) { index, record in
                if let startDate = parseDate(record.start_date) {
                    let endDate = index > 0 ? parseDate(history[index - 1].start_date) : nil

                    VStack(spacing: 0) {
                        EmploymentHistoryRowView(
                            corporationId: record.corporation_id,
                            startDate: startDate,
                            endDate: endDate,
                            corporationNamesCache: corporationNamesCache,
                            character: character,
                            isLoadingCorpNames: isLoadingCorpNames,
                            allianceCache: allianceCache,
                            npcCorporationIds: npcCorporationIds
                        )
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        return dateFormatter.date(from: dateString)
    }
}

struct EmploymentHistoryRowView: View {
    let corporationId: Int
    let startDate: Date
    let endDate: Date?
    let corporationNamesCache: [Int: String]
    let character: EVECharacterInfo
    let isLoadingCorpNames: Bool
    @ObservedObject var allianceCache: EmploymentAllianceCache
    let npcCorporationIds: Set<Int>
    @State private var corporationIcon: UIImage?
    @State private var allianceInfo: (id: Int, name: String?, icon: UIImage?)?
    @State private var isLoadingAlliance: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if let icon = corporationIcon {
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(3)
            } else {
                Image(systemName: "building.2.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(width: 32, height: 32)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isLoadingCorpNames {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(NSLocalizedString("Misc_Loading", comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    HStack(spacing: 4) {
                        if npcCorporationIds.contains(corporationId) {
                            Text("NPC")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color(red: 0.7, green: 0.5, blue: 0.9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(red: 0.7, green: 0.5, blue: 0.9).opacity(0.15))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color(red: 0.7, green: 0.5, blue: 0.9).opacity(0.3), lineWidth: 0.5)
                                )
                        }

                        Text(corporationNamesCache[corporationId] ?? NSLocalizedString("Unknown", comment: ""))
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                }

                if isLoadingAlliance {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text(NSLocalizedString("Misc_Loading", comment: ""))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                } else if let alliance = allianceInfo {
                    HStack(spacing: 4) {
                        if let icon = alliance.icon {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .cornerRadius(2)
                        } else {
                            Image(systemName: "globe")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        if let name = alliance.name {
                            Text(name)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(NSLocalizedString("Misc_Load_Failed", comment: ""))
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: 4) {
                    Text(FormatUtil.formatHistoryDateRange(start: startDate, end: endDate))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(FormatUtil.formatHistoryDuration(start: startDate, end: endDate))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            NavigationLink {
                CorporationDetailView(corporationId: corporationId, character: character)
            } label: {
                Label(
                    NSLocalizedString("View Corporation", comment: ""),
                    systemImage: "info.circle"
                )
            }

            if let alliance = allianceInfo {
                NavigationLink {
                    AllianceDetailView(allianceId: alliance.id, character: character)
                } label: {
                    Label(
                        NSLocalizedString("View Alliance", comment: ""),
                        systemImage: "info.circle"
                    )
                }
            }
        }
        .task {
            await loadData()
        }
    }

    /// 并行加载军团图标和联盟信息，加载完成后一次性更新状态
    /// - row 重建时 @State 重置为初始值（isLoadingAlliance = true），UI 立即显示"加载中"避免空白
    /// - Task.isCancelled 检查避免 row 滚出屏幕后取消的 task 仍然赋值
    private func loadData() async {
        async let iconTask: UIImage? = loadCorporationIcon()
        async let allianceTask: (id: Int, name: String?, icon: UIImage?)? = loadAllianceInfo()

        let (icon, alliance) = await (iconTask, allianceTask)

        guard !Task.isCancelled else { return }

        corporationIcon = icon
        allianceInfo = alliance
        isLoadingAlliance = false
    }

    private func loadCorporationIcon() async -> UIImage? {
        if let cachedIcon = allianceCache.corporationIcons[corporationId] {
            return cachedIcon
        }
        return await allianceCache.getCorporationIcon(corporationId: corporationId)
    }

    private func loadAllianceInfo() async -> (id: Int, name: String?, icon: UIImage?)? {
        let queryDate = endDate ?? Date()
        return await allianceCache.getCorpAlliance(corporationId: corporationId, date: queryDate)
    }
}
