import SwiftUI

private let environmentCategoryRowInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
private let environmentSelectionRowInsets = EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18)

struct EnvironmentSettingsView: View {
    let databaseManager: DatabaseManager
    @ObservedObject var viewModel: FittingEditorViewModel
    @Binding var selectedTypeId: Int?
    @Binding var pendingSelectionItem: DatabaseListItem?
    let onCommit: () -> Void

    @State private var effectListCategory: EnvironmentOptions.Category?

    var body: some View {
        List {
            Section {
                Button {
                    selectedTypeId = nil
                    pendingSelectionItem = nil
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                            .frame(width: 32, height: 32)
                        Text(NSLocalizedString("Environment_Clear_Selection", comment: "清空选项"))
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
                .disabled(selectedTypeId == nil)
            }
            .listRowInsets(environmentCategoryRowInsets)

            Section(header: Text(NSLocalizedString("Environment_Select_Category", comment: "选择类别"))) {
                ForEach(EnvironmentOptions.Category.allCases) { category in
                    Button {
                        effectListCategory = category
                    } label: {
                        HStack {
                            EnvironmentCategoryRow(category: category)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .listRowInsets(environmentCategoryRowInsets)

            if let item = pendingSelectionItem {
                Section(header: Text(NSLocalizedString("Environment_Current_Selection", comment: "当前选择"))) {
                    DatabaseListItemView(item: item, showDetails: false)
                }
                .listRowInsets(environmentCategoryRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("Environment_Settings_Title", comment: "环境设置"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            onCommit()
        }
        .sheet(item: $effectListCategory) { category in
            NavigationStack {
                EnvironmentEffectListView(
                    databaseManager: databaseManager,
                    category: category,
                    selectedTypeId: $selectedTypeId,
                    onItemSelected: { item in
                        pendingSelectionItem = item
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            effectListCategory = nil
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .presentationDragIndicator(.visible)
        }
    }
}

private struct EnvironmentCategoryRow: View {
    let category: EnvironmentOptions.Category

    var body: some View {
        HStack(spacing: 12) {
            Image(category.iconAssetName)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            Text(category.title)
                .foregroundColor(.primary)
        }
    }
}

struct EnvironmentEffectListView: View {
    let databaseManager: DatabaseManager
    let category: EnvironmentOptions.Category
    @Binding var selectedTypeId: Int?
    let onItemSelected: (DatabaseListItem) -> Void

    @State private var sections: [EnvironmentEffectSection] = []
    @State private var flatItems: [EnvironmentEffectItem] = []
    @State private var isLoading = true

    private var isGroupedList: Bool {
        category == .wormhole || category == .abyssal
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if isGroupedList ? sections.isEmpty : flatItems.isEmpty {
                ContentUnavailableView {
                    Label(
                        NSLocalizedString("Misc_No_Data", comment: "无数据"),
                        systemImage: "exclamationmark.triangle"
                    )
                }
            } else {
                List {
                    if isGroupedList {
                        ForEach(sections) { section in
                            Section(header: Text(section.title)) {
                                ForEach(section.items) { item in
                                    environmentSelectionRow(for: item)
                                }
                            }
                        }
                    } else {
                        ForEach(flatItems) { item in
                            environmentSelectionRow(for: item)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadItems()
        }
    }

    private func environmentSelectionRow(for item: EnvironmentEffectItem) -> some View {
        EnvironmentEffectSelectionRow(
            item: item.asDatabaseListItem(),
            rowIconAssetName: item.rowIconAssetName,
            isSelected: selectedTypeId == item.typeId
        ) {
            selectedTypeId = item.typeId
            onItemSelected(item.asDatabaseListItem())
        }
    }

    private func loadItems() {
        isLoading = true

        let typeIds = category.typeIds(from: EnvironmentOptions.shared)
        guard !typeIds.isEmpty else {
            sections = []
            flatItems = []
            isLoading = false
            return
        }

        // 内存索引构建环境效果物品
        let loadedItems: [EnvironmentEffectItem] = typeIds.compactMap { typeId in
            guard let info = SDEMemoryStore.type(for: typeId) else { return nil }
            return EnvironmentEffectNaming.makeItem(
                typeId: typeId,
                enName: info.enName,
                localName: info.name,
                iconFileName: info.iconFilename,
                category: category
            )
        }

        switch category {
        case .wormhole:
            sections = EnvironmentEffectNaming.wormholeSections(from: loadedItems)
            flatItems = []
        case .abyssal:
            sections = EnvironmentEffectNaming.abyssalSections(from: loadedItems)
            flatItems = []
        case .other:
            sections = []
            flatItems = loadedItems.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }

        isLoading = false
    }
}

private struct EnvironmentEffectSelectionRow: View {
    let item: DatabaseListItem
    let rowIconAssetName: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                if let rowIconAssetName {
                    Image(rowIconAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)

                    Text(item.name)
                        .foregroundColor(.primary)
                } else {
                    DatabaseListItemView(item: item, showDetails: false)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .listRowInsets(environmentSelectionRowInsets)
    }
}
