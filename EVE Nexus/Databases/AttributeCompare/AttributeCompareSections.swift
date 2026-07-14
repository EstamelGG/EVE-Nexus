import SwiftUI

/// 单个属性对比的 Section：以属性为维度展示所有物品的属性值
struct AttributeCompareSection: View {
    let attributeName: String
    let attributeID: String
    let values: [String: AttributeCompareUtil.AttributeValueInfo]
    let typeInfo: [String: String]
    let items: [DatabaseListItem]
    let attributeIcons: [String: String]
    let highIsGood: Bool

    var body: some View {
        Section {
            ForEach(items) { item in
                let typeIDString = String(item.id)
                HStack {
                    Image(uiImage: IconManager.shared.loadUIImage(for: item.iconFileName))
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(4)

                    Text(item.name)
                        .font(.body)

                    Spacer()

                    if let valueInfo = values[typeIDString] {
                        Text(getFormattedValue(valueInfo))
                            .font(.body)
                            .foregroundColor(getValueColor(for: item))
                    } else {
                        Text("N/A")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                if let iconFileName = attributeIcons[attributeID] {
                    IconManager.shared.loadImage(for: iconFileName)
                        .resizable()
                        .frame(width: 24, height: 24)
                }

                Text(attributeName)
                    .font(.headline)
            }
        }
    }

    /// 格式化属性值和单位
    private func getFormattedValue(_ valueInfo: AttributeCompareUtil.AttributeValueInfo) -> String {
        // 使用 AttributeDisplayConfig.transformValue 进行格式化，与 AttributeBarView 保持一致
        guard let attributeIDInt = Int(attributeID) else {
            return FormatUtil.format(valueInfo.value)
        }

        var allAttributes: [Int: Double] = [:]
        allAttributes[attributeIDInt] = valueInfo.value

        let result = AttributeDisplayConfig.transformValue(
            attributeIDInt, allAttributes: allAttributes, unitID: valueInfo.unitID
        )

        switch result {
        case let .number(value, unit):
            return unit.map { "\(FormatUtil.format(value))\($0)" } ?? FormatUtil.format(value)
        case let .text(str):
            return str
        case let .resistance(resistances):
            return resistances.map { "\(FormatUtil.format($0))%" }.joined(separator: ", ")
        }
    }

    /// 根据 highIsGood 确定每个物品的颜色（最好绿色、最差橙色、其余灰色）
    private func getValueColor(for item: DatabaseListItem) -> Color {
        let typeIDString = String(item.id)

        guard let currentValueInfo = values[typeIDString] else {
            return .secondary
        }

        let existingValues = values.values.map { $0.value }

        if existingValues.count <= 1 {
            return .secondary
        }

        let currentValue = currentValueInfo.value

        let bestValue: Double
        let worstValue: Double

        if highIsGood {
            bestValue = existingValues.max() ?? currentValue
            worstValue = existingValues.min() ?? currentValue
        } else {
            bestValue = existingValues.min() ?? currentValue
            worstValue = existingValues.max() ?? currentValue
        }

        if bestValue == worstValue {
            return .secondary
        }

        if currentValue == bestValue {
            return .green
        } else if currentValue == worstValue {
            return .orange
        } else {
            return .secondary
        }
    }
}

/// 计算中 Section（带 `Misc_Calculating` header 的居中 ProgressView）
struct CalculatingSection: View {
    var body: some View {
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
}

/// 属性对比结果 Section 列表（按属性 ID 排序，可选只展示有差异的属性）
struct AttributeCompareResultSections: View {
    let result: AttributeCompareUtil.CompareResult
    let items: [DatabaseListItem]
    let showOnlyDifferences: Bool

    var body: some View {
        let visibleIDs = AttributeCompareUtil.visibleAttributeIDs(
            in: result,
            itemCount: items.count,
            showOnlyDifferences: showOnlyDifferences
        )

        ForEach(visibleIDs, id: \.self) { attributeID in
            if let attributeValues = result.compareResult[attributeID],
               let attributeName = result.publishedAttributeInfo[attributeID]
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
