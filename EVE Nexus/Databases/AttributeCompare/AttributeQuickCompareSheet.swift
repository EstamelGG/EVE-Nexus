import SwiftUI

/// 市场详情内：与同市场叶子组内全部物品做属性对比，不写盘
struct AttributeQuickCompareSheet: View {
    @ObservedObject var databaseManager: DatabaseManager
    let marketGroupID: Int
    @Environment(\.dismiss) private var dismiss

    @State private var items: [DatabaseListItem] = []
    @State private var compareResult: AttributeCompareUtil.CompareResult?
    @State private var isCalculating = false
    @AppStorage("showOnlyDifferences") private var showOnlyDifferences: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text(NSLocalizedString("Main_Attribute_Compare_Empty", comment: ""))
                        .foregroundColor(.secondary)
                } else if items.count < 2 {
                    ContentUnavailableView {
                        Label(
                            NSLocalizedString("Main_Attribute_Quick_Compare_Need_Two", comment: ""),
                            systemImage: "square.split.2x1"
                        )
                    } description: {
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString(
                                    "Main_Attribute_Quick_Compare_Single_Item_Format",
                                    comment: ""
                                ),
                                items.count
                            )
                        )
                    }
                } else {
                    Section {
                        Toggle(
                            NSLocalizedString(
                                "Main_Attribute_Compare_Show_Only_Differences",
                                comment: ""
                            ),
                            isOn: $showOnlyDifferences
                        )
                        .padding(.top, 4)
                    } header: {
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString("Main_Attribute_Quick_Compare_Count_Format", comment: ""),
                                items.count
                            )
                        )
                        .fontWeight(.semibold)
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                        .textCase(.none)
                    }

                    if isCalculating {
                        Section {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                        } header: {
                            Text(NSLocalizedString("Misc_Calculating", comment: ""))
                        }
                    }

                    if let result = compareResult {
                        let allAttributes = result.publishedAttributeInfo
                        let sortedAttributeIDs = allAttributes.keys.sorted {
                            (Int($0) ?? 0) < (Int($1) ?? 0)
                        }
                        let attributesToShow =
                            showOnlyDifferences
                                ? attributeIDsWithDifferences(result) : sortedAttributeIDs
                        let filteredAttributes = sortedAttributeIDs.filter {
                            attributesToShow.contains($0)
                        }

                        ForEach(filteredAttributes, id: \.self) { attributeID in
                            if let attributeValues = result.compareResult[attributeID],
                               let attributeName = allAttributes[attributeID]
                            {
                                AttributeCompareSection(
                                    attributeName: attributeName,
                                    attributeID: attributeID,
                                    values: attributeValues,
                                    typeInfo: result.typeInfo,
                                    items: items,
                                    attributeIcons: result.attributeIcons,
                                    highIsGood: result.attributeHighIsGood[attributeID] ?? true
                                )
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Main_Attribute_Quick_Compare", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: loadAndCompare)
        }
    }

    private func loadAndCompare() {
        items = databaseManager.loadMarketItems(
            whereClause: "t.marketGroupID = ?",
            parameters: [marketGroupID]
        )
        .sorted { $0.id < $1.id }

        guard items.count >= 2 else {
            compareResult = nil
            return
        }

        isCalculating = true
        let typeIDs = items.map(\.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AttributeCompareUtil.compareAttributesWithResult(
                typeIDs: typeIDs,
                databaseManager: databaseManager
            )
            DispatchQueue.main.async {
                self.compareResult = result
                self.isCalculating = false
            }
        }
    }

    private func attributeIDsWithDifferences(_ result: AttributeCompareUtil.CompareResult) -> [String] {
        let totalItemCount = items.count
        var attributesWithDifferences: [String] = []

        for (attributeID, values) in result.compareResult {
            if values.count != totalItemCount {
                attributesWithDifferences.append(attributeID)
                continue
            }

            var allSame = true
            let firstValue = values.values.first?.value

            for (_, info) in values {
                if info.value != firstValue {
                    allSame = false
                    break
                }
            }

            if !allSame {
                attributesWithDifferences.append(attributeID)
            }
        }

        return attributesWithDifferences.sorted { Int($0) ?? 0 < Int($1) ?? 0 }
    }
}
