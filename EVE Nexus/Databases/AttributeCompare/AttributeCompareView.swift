import SwiftUI

/// 属性对比物品选择器视图（使用过滤的顶级市场分组）
struct AttributeItemSelectorView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var showSelected = true
    let allowedTopMarketGroupIDs: Set<Int>
    let existingItems: Set<Int>
    let onItemSelected: (DatabaseListItem) -> Void
    let onItemDeselected: (DatabaseListItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MarketItemSelectorIntegratedView(
                databaseManager: databaseManager,
                title: NSLocalizedString("Main_Attribute_Compare_Add_Item", comment: ""),
                allowedMarketGroups: allowedTopMarketGroupIDs,
                allowTypeIDs: [],
                existingItems: existingItems,
                onItemSelected: onItemSelected,
                onItemDeselected: onItemDeselected,
                onDismiss: { dismiss() },
                showSelected: showSelected
            )
            .interactiveDismissDisabled()
        }
    }
}

/// 属性对比列表主视图
struct AttributeCompareView: View {
    @ObservedObject var databaseManager: DatabaseManager
    @State private var compares: [AttributeCompare] = []
    @State private var isShowingAddAlert = false
    @State private var tempCompareName = "" // 临时变量，用于接收用户输入
    @State private var searchText = ""
    @State private var isShowingRenameAlert = false
    @State private var renameCompare: AttributeCompare?
    @State private var renameCompareName = ""

    private var filteredCompares: [AttributeCompare] {
        if searchText.isEmpty {
            return compares
        } else {
            return compares.filter { compare in
                compare.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        List {
            if filteredCompares.isEmpty {
                if searchText.isEmpty {
                    Text(NSLocalizedString("Main_Attribute_Compare_Empty", comment: ""))
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                } else {
                    Text(String.localizedStringWithFormat(NSLocalizedString("Main_EVE_Mail_No_Results", comment: "")))
                        .foregroundColor(.secondary)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                }
            } else {
                ForEach(filteredCompares) { compare in
                    NavigationLink {
                        AttributeCompareDetailView(
                            databaseManager: databaseManager,
                            compare: compare
                        )
                    } label: {
                        compareRowView(compare)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if let index = compares.firstIndex(where: { $0.id == compare.id }) {
                                deleteCompare(at: IndexSet(integer: index))
                            }
                        } label: {
                            Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                        }

                        Button {
                            renameCompare = compare
                            renameCompareName = compare.name
                            isShowingRenameAlert = true
                        } label: {
                            Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            renameCompare = compare
                            renameCompareName = compare.name
                            isShowingRenameAlert = true
                        } label: {
                            Label(NSLocalizedString("Misc_Rename", comment: ""), systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            if let index = compares.firstIndex(where: { $0.id == compare.id }) {
                                deleteCompare(at: IndexSet(integer: index))
                            }
                        } label: {
                            Label(NSLocalizedString("Misc_Delete", comment: ""), systemImage: "trash")
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
            }
        }
        .navigationTitle(NSLocalizedString("Main_Attribute_Compare", comment: ""))
        .searchable(
            text: $searchText,
            // placement: .navigationBarDrawer(displayMode: .always),
            prompt: NSLocalizedString("Main_Database_Search", comment: "")
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    tempCompareName = ""
                    isShowingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert(
            NSLocalizedString("Main_Attribute_Compare_Add", comment: ""),
            isPresented: $isShowingAddAlert
        ) {
            TextField(
                NSLocalizedString("Main_Attribute_Compare_Name", comment: ""),
                text: $tempCompareName
            )

            Button(NSLocalizedString("Misc_Done", comment: "")) {
                Logger.info("用户新增对比列表: \(tempCompareName)")
                if !tempCompareName.isEmpty {
                    let newCompare = AttributeCompare(
                        name: tempCompareName,
                        items: []
                    )
                    compares.append(newCompare)
                    AttributeCompareManager.shared.saveCompare(newCompare)
                    tempCompareName = ""
                }
            }
            .disabled(tempCompareName.isEmpty)

            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                tempCompareName = ""
            }
        }
        .alert(NSLocalizedString("Misc_Rename", comment: ""), isPresented: $isShowingRenameAlert) {
            TextField(NSLocalizedString("Misc_Name", comment: ""), text: $renameCompareName)

            Button(NSLocalizedString("Misc_Done", comment: "")) {
                if let compare = renameCompare, !renameCompareName.isEmpty {
                    if let index = compares.firstIndex(where: { $0.id == compare.id }) {
                        compares[index].name = renameCompareName
                        AttributeCompareManager.shared.saveCompare(compares[index])
                    }
                }
                renameCompare = nil
                renameCompareName = ""
            }
            .disabled(renameCompareName.isEmpty)

            Button(NSLocalizedString("Main_EVE_Mail_Cancel", comment: ""), role: .cancel) {
                renameCompare = nil
                renameCompareName = ""
            }
        }
        .task {
            compares = AttributeCompareManager.shared.loadCompares()
        }
    }

    private func compareRowView(_ compare: AttributeCompare) -> some View {
        HStack {
            if !compare.items.isEmpty, let firstItem = compare.items.first {
                let icon = getItemIcon(typeID: firstItem.typeID)
                Image(uiImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .padding(.trailing, 8)
            } else {
                Image("Folder")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .padding(.trailing, 8)
            }

            Text(compare.name)
                .lineLimit(1)
            Spacer()
            Text(
                String(
                    format: NSLocalizedString("Main_Attribute_Compare_Items", comment: ""),
                    compare.items.count
                )
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// 获取物品图标
    private func getItemIcon(typeID: Int) -> UIImage {
        let itemData = databaseManager.loadMarketItems(
            whereClause: "t.type_id = ?",
            parameters: [typeID]
        )

        if let item = itemData.first {
            return IconManager.shared.loadUIImage(for: item.iconFileName)
        } else {
            return UIImage(named: "not_found") ?? UIImage()
        }
    }

    private func deleteCompare(at offsets: IndexSet) {
        let comparesToDelete = offsets.map { filteredCompares[$0] }
        for compare in comparesToDelete {
            AttributeCompareManager.shared.deleteCompare(compare)
            if let index = compares.firstIndex(where: { $0.id == compare.id }) {
                compares.remove(at: index)
            }
        }
    }
}
