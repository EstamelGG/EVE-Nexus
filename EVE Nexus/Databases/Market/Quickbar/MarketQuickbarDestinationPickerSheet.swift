import SwiftUI

/// 关注列表物品种类（不同 `type_id`）上限与剪贴板导入一致
enum MarketQuickbarDestinationPicker {
    static var maxDistinctTypeCount: Int {
        MarketClipboardParser.maxImportDistinctTypeCount
    }

    /// 从 `items` **末尾**删除条目，直到不同 `typeID` 的个数 ≤ `maxDistinctTypeCount`。
    /// - Returns: 是否删除了至少一行
    @discardableResult
    static func trimToMaxDistinctTypesRemovingFromEnd(_ items: inout [QuickbarItem]) -> Bool {
        let countBefore = items.count
        while !items.isEmpty, Set(items.map(\.typeID)).count > maxDistinctTypeCount {
            items.removeLast()
        }
        return items.count != countBefore
    }

    /// 若尚无该 `typeID` 则追加（数量 1），再执行种类上限裁剪。
    /// - Returns: `(追加后 typeID 仍在列表中, 是否发生了尾部裁剪)`，用于提示「列表过长…」
    static func appendTypeIfAbsentWithLimitBehavior(typeID: Int, in quickbar: inout MarketQuickbar) -> (
        newTypePresent: Bool, didTrim: Bool
    ) {
        if quickbar.items.contains(where: { $0.typeID == typeID }) {
            return (true, false)
        }
        quickbar.items.append(QuickbarItem(typeID: typeID, quantity: 1))
        quickbar.lastUpdated = Date()
        let didTrim = trimToMaxDistinctTypesRemovingFromEnd(&quickbar.items)
        let newTypePresent = quickbar.items.contains(where: { $0.typeID == typeID })
        return (newTypePresent, didTrim)
    }

    /// 剪贴板「附加」模式：合并已有与导入条目，同 type 数量相加并封顶
    static func mergeQuickbarItems(existing: [QuickbarItem], imported: [QuickbarItem]) -> [QuickbarItem] {
        var quantities: [Int: Int64] = [:]
        for item in existing {
            quantities[item.typeID] = item.quantity
        }
        for item in imported {
            let sum = (quantities[item.typeID] ?? 0) + item.quantity
            quantities[item.typeID] = min(999_999_999, sum)
        }
        return quantities.keys.sorted().map { QuickbarItem(typeID: $0, quantity: quantities[$0]!) }
    }
}

/// 从物品详情 / 市场详情中选择要加入的关注列表：导航推进、单选、点导航栏「确认」再写入并返回（不自动 dismiss）
struct MarketQuickbarDestinationPickerView: View {
    @ObservedObject var databaseManager: DatabaseManager
    let typeID: Int
    @Environment(\.dismiss) private var dismiss

    @State private var quickbars: [MarketQuickbar] = []
    @State private var selectedQuickbarID: UUID?
    @State private var showAddSuccessAlert = false
    @State private var successWatchlistName = ""
    @State private var showTypeLimitAlert = false
    @State private var showAlreadyInListAlert = false

    var body: some View {
        Group {
            if quickbars.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Main_Market_Watch_List_Empty", comment: ""),
                        systemImage: "list.bullet.rectangle"
                    )
                }
            } else {
                List {
                    ForEach(quickbars) { quickbar in
                        Button {
                            selectedQuickbarID = quickbar.id
                        } label: {
                            MarketQuickbarPickerRowView(
                                quickbar: quickbar,
                                databaseManager: databaseManager,
                                isSelected: selectedQuickbarID == quickbar.id
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Market_Add_To_Watchlist_Picker_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(NSLocalizedString("Common_Confirm", comment: "")) {
                    confirmSelection()
                }
                .disabled(selectedQuickbarID == nil || quickbars.isEmpty)
            }
        }
        .onAppear {
            quickbars = MarketQuickbarManager.shared.loadQuickbars()
        }
        .alert(
            NSLocalizedString("Main_Market_Add_To_Watchlist_Success_Title", comment: ""),
            isPresented: $showAddSuccessAlert
        ) {
            Button(NSLocalizedString("Misc_Done", comment: "")) {
                dismiss()
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Main_Market_Add_To_Watchlist_Success_Message",
                        comment: ""
                    ),
                    successWatchlistName
                )
            )
        }
        .alert(
            NSLocalizedString("Main_Market_Watch_List_Type_Limit_Title", comment: ""),
            isPresented: $showTypeLimitAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: "")) {}
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Main_Market_Watch_List_Type_Limit_Message",
                        comment: ""
                    ),
                    MarketQuickbarDestinationPicker.maxDistinctTypeCount
                )
            )
        }
        .alert(
            NSLocalizedString("Main_Market_Add_To_Watchlist_Already_Title", comment: ""),
            isPresented: $showAlreadyInListAlert
        ) {
            Button(NSLocalizedString("Common_OK", comment: "")) {}
        } message: {
            Text(NSLocalizedString("Main_Market_Add_To_Watchlist_Already_Message", comment: ""))
        }
    }

    private func confirmSelection() {
        guard let id = selectedQuickbarID,
              var quickbar = quickbars.first(where: { $0.id == id })
        else { return }

        if quickbar.items.contains(where: { $0.typeID == typeID }) {
            showAlreadyInListAlert = true
            return
        }

        let nameForMessage = quickbar.name
        let (kept, trimmed) = MarketQuickbarDestinationPicker.appendTypeIfAbsentWithLimitBehavior(
            typeID: typeID,
            in: &quickbar
        )
        MarketQuickbarManager.shared.saveQuickbar(quickbar)

        if kept, !trimmed {
            successWatchlistName = nameForMessage
            showAddSuccessAlert = true
        } else {
            showTypeLimitAlert = true
        }
    }
}

// MARK: - 行样式（与市场关注列表首页 `quickbarRowView` 一致）

struct MarketQuickbarPickerRowView: View {
    let quickbar: MarketQuickbar
    @ObservedObject var databaseManager: DatabaseManager
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28, alignment: .center)

            if let iconTypeID = preferredIconTypeID(for: quickbar) {
                Image(uiImage: itemIcon(typeID: iconTypeID))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            } else {
                Image("Folder")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(quickbar.name)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(marketDisplayName(for: quickbar))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(
                String(
                    format: NSLocalizedString("Main_Market_Watch_List_Items", comment: ""),
                    quickbar.items.count
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private func preferredIconTypeID(for quickbar: MarketQuickbar) -> Int? {
        guard !quickbar.items.isEmpty else { return nil }
        let typeIDs = quickbar.items.map { String($0.typeID) }.joined(separator: ",")
        let loaded = databaseManager.loadMarketItems(
            whereClause: "t.type_id IN (\(typeIDs))",
            parameters: []
        )
        let typeIDToCategory: [Int: Int] = Dictionary(uniqueKeysWithValues: loaded.compactMap { item in
            guard let cat = item.categoryID else { return nil }
            return (item.id, cat)
        })
        for item in quickbar.items {
            if typeIDToCategory[item.typeID] == 6 {
                return item.typeID
            }
        }
        return quickbar.items.first?.typeID
    }

    private func itemIcon(typeID: Int) -> UIImage {
        let itemData = databaseManager.loadMarketItems(
            whereClause: "t.type_id = ?",
            parameters: [typeID]
        )
        if let item = itemData.first {
            return IconManager.shared.loadUIImage(for: item.iconFileName)
        }
        return UIImage(named: "not_found") ?? UIImage()
    }

    private func marketDisplayName(for quickbar: MarketQuickbar) -> String {
        let regionID = quickbar.regionID
        if StructureMarketManager.isStructureId(regionID) {
            if let structureId = StructureMarketManager.getStructureId(from: regionID),
               let structure = MarketStructureManager.shared.structures.first(where: {
                   $0.structureId == Int(structureId)
               })
            {
                return structure.structureName
            }
            return "Unknown Structure"
        }
        return SDEMemoryStore.regionName(for: regionID) ?? "Unknown Region"
    }
}
