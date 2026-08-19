import SwiftUI

struct ShipAllCargoView: View {
    @ObservedObject var viewModel: FittingEditorViewModel

    /// 货仓属性数据模型
    private struct CargoAttribute: Identifiable {
        let id: Int // attribute_id
        let name: String // 属性名称（如 "capacity"）
        let displayName: String
        let value: Double
        let unitName: String?
    }

    /// 获取货仓属性列表
    private var cargoAttributes: [CargoAttribute] {
        guard let ship = viewModel.simulationOutput?.ship else {
            return []
        }

        var attributes: [CargoAttribute] = []
        let calculatedAttributesByName = ship.attributesByName

        // 1. 手动添加 capacity 属性（attribute_id 38）到第一位
        // capacity 不在 categoryID 40 中，直接手动构造
        let capacityValue = calculatedAttributesByName["capacity"] ?? 0

        if capacityValue > 0 {
            attributes.append(
                CargoAttribute(
                    id: 38,
                    name: "capacity",
                    displayName: NSLocalizedString("Fitting_cargo", comment: "货舱"),
                    value: capacityValue,
                    unitName: "m³"
                )
            )
        }

        // 2. 内存索引获取 categoryID 为 40 的其他货仓属性（原 SQL 查询，现缓存于 SDEMemoryStore）
        let cargoAttrs = SDEMemoryStore.dogmaAttributes.values
            .filter { $0.categoryID == 40 }
            .sorted { $0.id < $1.id }

        for attr in cargoAttrs {
            guard let displayName = attr.displayName else { continue }

            // 通过 name 从 attributesByName 获取数值
            let attributeValue = calculatedAttributesByName[attr.name] ?? 0

            // 只显示有值的属性
            guard attributeValue > 0 else { continue }

            let unitName = attr.unitNames.resolvedNonEmpty()
            attributes.append(
                CargoAttribute(
                    id: attr.id,
                    name: attr.name,
                    displayName: displayName,
                    value: attributeValue,
                    unitName: unitName
                )
            )
        }

        return attributes
    }

    var body: some View {
        if let _ = viewModel.simulationOutput?.ship, !cargoAttributes.isEmpty {
            Section {
                // Single column layout
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cargoAttributes) { attribute in
                        HStack {
                            // 左侧：属性名称
                            Text(attribute.displayName)
                                .foregroundColor(.secondary)
                                .font(.caption)
                                .lineLimit(1)

                            Spacer()

                            // 右侧：属性数值
                            Text(formatAttributeValue(attribute.value, unitName: attribute.unitName))
                                .foregroundColor(.primary)
                                .font(.caption)
                        }
                        .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text(NSLocalizedString("Fitting_stat_cargo", comment: "货仓属性"))
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .font(.system(size: 18))
                    Spacer()
                }
            }
        }
    }

    /// 格式化属性值
    private func formatAttributeValue(_ value: Double, unitName: String?) -> String {
        // 创建 NumberFormatter 用于添加千位分隔符
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."

        // 如果数值是整数，不显示小数部分
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
        } else {
            // 显示小数部分，最多保留合理的小数位数
            formatter.maximumFractionDigits = 10
            formatter.minimumFractionDigits = 0
        }

        let numberString = formatter.string(from: NSNumber(value: value)) ?? String(value)

        if let unit = unitName, !unit.isEmpty {
            // 百分号不添加空格，其他单位添加空格
            if unit == "%" {
                return numberString + unit
            } else {
                return numberString + " " + unit
            }
        }

        return numberString
    }
}
