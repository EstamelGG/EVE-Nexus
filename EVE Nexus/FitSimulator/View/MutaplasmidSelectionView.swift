import SwiftUI

/// 突变质体选择视图 - 显示物品可用的突变质体列表
struct MutaplasmidSelectionView: View {
    let databaseManager: DatabaseManager
    let itemTypeID: Int
    var onSelectMutaplasmid: ((Int) -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @State private var mutaplasmids: [(typeID: Int, name: String, iconFileName: String)] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text(NSLocalizedString("Misc_Loading", comment: ""))
                }
            } else if mutaplasmids.isEmpty {
                Text(NSLocalizedString("Misc_No_Data", comment: ""))
                    .foregroundColor(.secondary)
            } else {
                ForEach(mutaplasmids, id: \.typeID) { mutaplasmid in
                    MutaplasmidRowView(
                        mutaplasmid: mutaplasmid,
                        attributes: SDEMemoryStore.dynamicItemAttributes(
                            forTypeID: mutaplasmid.typeID
                        )
                    ) {
                        // 选择突变质体
                        onSelectMutaplasmid?(mutaplasmid.typeID)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Fitting_Available_Mutations", comment: ""))
        .onAppear {
            loadMutaplasmids()
        }
    }

    private func loadMutaplasmids() {
        isLoading = true
        // 获取可用突变质体列表（属性范围从 SDEMemoryStore 内存缓存取）
        mutaplasmids = databaseManager.getRequiredMutaplasmids(for: itemTypeID)
        isLoading = false
    }
}

/// 突变质体行视图
struct MutaplasmidRowView: View {
    let mutaplasmid: (typeID: Int, name: String, iconFileName: String)
    let attributes: [SDEMemoryStore.DynamicItemAttributeInfo]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 突变质体图标和名称
                HStack(spacing: 8) {
                    IconManager.shared.loadImage(for: mutaplasmid.iconFileName)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)

                    Text(mutaplasmid.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    Spacer()
                }

                // 突变属性列表
                if !attributes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(attributes, id: \.attributeID) { attribute in
                            HStack(spacing: 4) {
                                if let iconFileName = attribute.iconFileName, !iconFileName.isEmpty {
                                    IconManager.shared.loadImage(for: iconFileName)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }

                                Text(attribute.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                // 显示属性范围
                                HStack(spacing: 2) {
                                    Text(formatValue(
                                        attribute.highIsGood ? attribute.minValue : attribute.maxValue
                                    ))
                                    .foregroundColor(.red)
                                    .font(.system(.caption, design: .monospaced))

                                    Text("-")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    Text(formatValue(
                                        attribute.highIsGood ? attribute.maxValue : attribute.minValue
                                    ))
                                    .foregroundColor(.green)
                                    .font(.system(.caption, design: .monospaced))
                                }
                            }
                        }
                    }
                    .padding(.leading, 40) // 与图标对齐
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatValue(_ value: Double) -> String {
        let percentage = (value - 1) * 100
        return String(format: "%+.2f%%", percentage)
    }
}
