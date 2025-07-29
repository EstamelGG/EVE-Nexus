import SwiftUI

struct WormholeView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var wormholes: [String: [WormholeInfo]] = [:]
    @State private var targetOrder: [String] = []
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var showingInfoSheet = false

    var filteredWormholes: [String: [WormholeInfo]] {
        if searchText.isEmpty {
            return wormholes
        }

        var filtered: [String: [WormholeInfo]] = [:]
        for (target, items) in wormholes {
            let matchingItems = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
                    || $0.target.localizedCaseInsensitiveContains(searchText)
                    || $0.sizeType.localizedCaseInsensitiveContains(searchText)
            }
            if !matchingItems.isEmpty {
                filtered[target] = matchingItems
            }
        }
        return filtered
    }

    var body: some View {
        List {
            ForEach(
                searchText.isEmpty ? targetOrder : Array(filteredWormholes.keys.sorted()),
                id: \.self
            ) { target in
                Section(
                    header: Text(target)
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                ) {
                    ForEach(filteredWormholes[target] ?? wormholes[target] ?? []) { wormhole in
                        NavigationLink(
                            destination: WormholeDetailView(
                                wormhole: wormhole, databaseManager: databaseManager
                            )
                        ) {
                            HStack(spacing: 12) {
                                // 左侧图标
                                IconManager.shared.loadImage(for: wormhole.icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .cornerRadius(6)

                                // 右侧文本
                                VStack(alignment: .leading) {
                                    Text(wormhole.name)
                                        .font(.body)
                                    Text(wormhole.sizeType)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 0)
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            isPresented: $isSearchActive,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
        .navigationTitle(NSLocalizedString("Main_Market_WH_info", comment: ""))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingInfoSheet = true
                }) {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingInfoSheet) {
            WormholeInfoSheetView()
        }
        .onAppear {
            loadWormholes()
        }
    }

    private func loadWormholes() {
        let items = databaseManager.loadWormholes()
        var tempWormholes: [String: [WormholeInfo]] = [:]
        var tempTargetOrder: [String] = []

        for item in items {
            if tempWormholes[item.target] == nil {
                tempWormholes[item.target] = []
                tempTargetOrder.append(item.target)
            }
            tempWormholes[item.target]?.append(item)
        }

        wormholes = tempWormholes
        targetOrder = tempTargetOrder
    }
}

struct WormholeInfoSheetView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text(NSLocalizedString("WH_time_life", comment: "Time")).font(.headline).textCase(.none)) {
                    WormholeInfoRow(
                        description: NSLocalizedString("WH_life_Notyet", comment: ""),
                        timeInfo: "> 24h",
                        statusType: .good
                    )
                    WormholeInfoRow(
                        description: NSLocalizedString("WH_life_beginning", comment: ""),
                        timeInfo: "> 4h, < 24h",
                        statusType: .warning
                    )
                    WormholeInfoRow(
                        description: NSLocalizedString("WH_life_reaching", comment: ""),
                        timeInfo: "< 4h",
                        statusType: .critical
                    )
                }
                
                Section(header: Text(NSLocalizedString("WH_Mass_life", comment: "Mass")).font(.headline).textCase(.none)) {
                    WormholeInfoRow(
                        description: NSLocalizedString("WH_Mass_Notyet", comment: ""),
                        timeInfo: "> 50%",
                        statusType: .good
                    )
                    WormholeInfoRow(
                        description: NSLocalizedString("WH_Mass_Notcritical", comment: ""),
                        timeInfo: "> 10%, < 50%",
                        statusType: .warning
                    )
                    WormholeInfoRow(
                        description: NSLocalizedString("WH_Mass_critically", comment: ""),
                        timeInfo: "< 10%",
                        statusType: .critical
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Text(NSLocalizedString("Misc_Done", comment: "Done"))
                    }
                }
            }
        }
    }
}

// 状态类型枚举
enum WormholeStatusType {
    case good
    case warning
    case critical
}

struct WormholeInfoRow: View {
    let description: String
    let timeInfo: String
    let statusType: WormholeStatusType
    
    // 根据状态类型确定颜色
    private var statusColor: Color {
        switch statusType {
        case .good:
            return .green
        case .warning:
            return .yellow
        case .critical:
            return .red
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 状态圆点
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .padding(.top, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(description)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(timeInfo)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WormholeDetailView: View {
    let wormhole: WormholeInfo
    @ObservedObject var databaseManager: DatabaseManager

    var body: some View {
        List {
            // 基本信息部分
            ItemBasicInfoView(
                itemDetails: ItemDetails(
                    name: wormhole.name,
                    en_name: wormhole.name,
                    description: wormhole.description,
                    iconFileName: wormhole.icon,
                    groupName: wormhole.sizeType,
                    categoryID: nil,
                    categoryName: wormhole.target,
                    typeId: wormhole.id,
                    groupID: nil,
                    volume: nil,
                    capacity: nil,
                    mass: nil,
                    marketGroupID: nil
                ),
                databaseManager: databaseManager,
                modifiedAttributes: nil
            )

            // 详细信息部分
            Section {
                WHDetailInfoRow(
                    title: NSLocalizedString("Main_Market_WH_Leadsto", comment: ""),
                    value: wormhole.target,
                    iconName: "items_7_64_4.png"
                )
                WHDetailInfoRow(
                    title: NSLocalizedString("Main_Market_WH_MaxStableTime", comment: ""),
                    value: wormhole.stableTime,
                    iconName: "items_22_32_16.png"
                )
                WHDetailInfoRow(
                    title: NSLocalizedString("Main_Market_WH_MaxStableMass", comment: ""),
                    value: wormhole.maxStableMass,
                    iconName: "icon_1333_64.png"
                )
                WHDetailInfoRow(
                    title: NSLocalizedString("Main_Market_WH_MaxJumpMass", comment: ""),
                    value: wormhole.maxJumpMass,
                    iconName: "items_9_64_5.png"
                )
                WHDetailInfoRow(
                    title: NSLocalizedString("Main_Market_WH_Size", comment: ""),
                    value: wormhole.sizeType,
                    iconName: "items_22_32_15.png"
                )
            } header: {
                Text(NSLocalizedString("Main_Market_WH_Details", comment: ""))
                    .font(.headline)
                    .textCase(.none)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WHDetailInfoRow: View {
    let title: String
    let value: String
    let iconName: String?

    init(title: String, value: String, iconName: String? = nil) {
        self.title = title
        self.value = value
        self.iconName = iconName
    }

    var body: some View {
        HStack {
            if let iconName = iconName {
                IconManager.shared.loadImage(for: iconName)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .aspectRatio(contentMode: .fit)
            }
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}
