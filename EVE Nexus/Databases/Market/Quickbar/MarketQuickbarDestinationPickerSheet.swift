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
    @State private var isShowingCreateAlert = false
    @State private var newQuickbarName = ""

    var body: some View {
        Group {
            if quickbars.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("Main_Market_Watch_List_Empty", comment: ""))
                        .foregroundColor(.secondary)
                    Button {
                        newQuickbarName = ""
                        isShowingCreateAlert = true
                    } label: {
                        Label(
                            NSLocalizedString("Main_Market_Watch_List_Add", comment: ""),
                            systemImage: "plus"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(quickbars) { quickbar in
                        let alreadyContains = quickbar.items.contains(where: { $0.typeID == typeID })
                        Button {
                            selectedQuickbarID = quickbar.id
                        } label: {
                            MarketQuickbarPickerRowView(
                                quickbar: quickbar,
                                databaseManager: databaseManager,
                                isSelected: selectedQuickbarID == quickbar.id,
                                alreadyContainsTypeID: alreadyContains
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(alreadyContains)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            }
        }
        .navigationTitle(NSLocalizedString("Main_Market_Add_To_Watchlist_Picker_Title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newQuickbarName = ""
                    isShowingCreateAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(NSLocalizedString("Common_Confirm", comment: "")) {
                    confirmSelection()
                }
                .disabled(selectedQuickbarID == nil)
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
        .alert(
            NSLocalizedString("Main_Market_Watch_List_Add", comment: ""),
            isPresented: $isShowingCreateAlert
        ) {
            TextField(
                NSLocalizedString("Main_Market_Watch_List_Name", comment: ""),
                text: $newQuickbarName
            )
            Button(NSLocalizedString("Misc_Done", comment: "")) {
                createNewListAndAddItem()
            }
            .disabled(newQuickbarName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                newQuickbarName = ""
            }
        }
    }

    /// 创建新关注列表并添加当前物品，然后显示成功提示
    private func createNewListAndAddItem() {
        let trimmed = newQuickbarName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var newQuickbar = MarketQuickbar(name: trimmed)
        newQuickbar.items.append(QuickbarItem(typeID: typeID, quantity: 1))
        MarketQuickbarManager.shared.saveQuickbar(newQuickbar)

        successWatchlistName = trimmed
        newQuickbarName = ""
        showAddSuccessAlert = true
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
    /// 此列表是否已包含目标物品（已包含时显示绿色勾选并禁用选择）
    var alreadyContainsTypeID: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if alreadyContainsTypeID {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else if isSelected {
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
                    .saturation(alreadyContainsTypeID ? 0 : 1)
                    .opacity(alreadyContainsTypeID ? 0.5 : 1)
            } else {
                Image("Folder")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(6)
                    .opacity(alreadyContainsTypeID ? 0.5 : 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(quickbar.name)
                    .lineLimit(1)
                    .foregroundColor(alreadyContainsTypeID ? .secondary : .primary)

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
        MarketLocationType.from(id: quickbar.locationID)?.displayName ?? "Unknown"
    }
}
