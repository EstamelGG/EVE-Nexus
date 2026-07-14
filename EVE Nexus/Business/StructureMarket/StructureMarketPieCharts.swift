import SwiftUI

// MARK: - 目录饼图视图

struct CategoryPieChartView: View {
    let data: [CategoryOrderData]
    @State private var selectedSlice: CategoryPieSlice?

    private var slices: [CategoryPieSlice] {
        let total = data.reduce(0) { $0 + Double($1.orderCount) }
        guard total > 0 else { return [] }

        // 按订单数降序排序
        let sortedData = data.sorted { $0.orderCount > $1.orderCount }

        // 只取前10个目录
        let top10Categories = Array(sortedData.prefix(10))
        let remainingCategories = Array(sortedData.dropFirst(10))

        // 计算前10个目录的占比
        var finalItems: [(item: CategoryOrderData, percentage: Double)] = top10Categories.map { item in
            (item: item, percentage: Double(item.orderCount) / total * 100)
        }

        // 如果有剩余目录，合并为"其他"
        if !remainingCategories.isEmpty {
            let otherTotalCount = remainingCategories.reduce(0) { $0 + $1.orderCount }
            let otherPercentage = Double(otherTotalCount) / total * 100
            finalItems.append((
                item: CategoryOrderData(
                    id: -1, // 使用-1作为"其他"的ID
                    name: NSLocalizedString("Structure_Market_Other", comment: "其他"),
                    orderCount: otherTotalCount
                ),
                percentage: otherPercentage
            ))
        }

        // 生成颜色（扩展颜色数组，避免重复）
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .red, .yellow,
            .pink, .cyan, .mint, .indigo, .teal, .brown,
            Color(red: 0.2, green: 0.6, blue: 0.8), // 天蓝色
            Color(red: 0.8, green: 0.4, blue: 0.2), // 橙红色
            Color(red: 0.6, green: 0.8, blue: 0.2), // 黄绿色
            Color(red: 0.8, green: 0.2, blue: 0.6), // 粉紫色
            Color(red: 0.4, green: 0.2, blue: 0.8), // 深紫色
            Color(red: 0.2, green: 0.8, blue: 0.6), // 青绿色
            Color(red: 0.9, green: 0.5, blue: 0.1), // 金橙色
            Color(red: 0.3, green: 0.7, blue: 0.9), // 亮蓝色
            Color(red: 0.7, green: 0.3, blue: 0.9), // 亮紫色
            Color(red: 0.5, green: 0.9, blue: 0.3), // 亮绿色
            Color(red: 0.9, green: 0.7, blue: 0.2), // 金黄色
            Color(red: 0.6, green: 0.3, blue: 0.9), // 深蓝紫色
        ]

        // 生成切片
        var startAngle = 0.0
        return finalItems.enumerated().map { index, itemWithPercentage in
            let angle = 360 * (itemWithPercentage.percentage / 100)
            // "其他"使用灰色，其他目录使用颜色数组
            let color = itemWithPercentage.item.id == -1 ? Color.gray : colors[index % colors.count]
            let slice = CategoryPieSlice(
                id: itemWithPercentage.item.id,
                name: itemWithPercentage.item.name,
                orderCount: itemWithPercentage.item.orderCount,
                percentage: itemWithPercentage.percentage,
                startAngle: startAngle,
                endAngle: startAngle + angle,
                color: color
            )
            startAngle += angle
            return slice
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            // 图例
            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        // 颜色方块
                        Rectangle()
                            .fill(slice.color)
                            .frame(width: 12, height: 12)
                            .cornerRadius(2)
                            .overlay(
                                // 高亮边框
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(selectedSlice?.id == slice.id ? Color.primary : Color.clear, lineWidth: 2)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            // 目录名称
                            Text(slice.name)
                                .font(.caption)
                                .fontWeight(selectedSlice?.id == slice.id ? .semibold : .regular)
                                .foregroundColor(selectedSlice?.id == slice.id ? .primary : .primary)

                            // 占比和订单数
                            Text(
                                String(format: "%.1f%% (%d)",
                                       slice.percentage,
                                       slice.orderCount)
                            )
                            .font(.caption2)
                            .foregroundColor(selectedSlice?.id == slice.id ? .primary : .secondary)
                        }
                    }
                    .padding(.horizontal, selectedSlice?.id == slice.id ? 4 : 0)
                    .padding(.vertical, selectedSlice?.id == slice.id ? 2 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedSlice?.id == slice.id ? Color.secondary.opacity(0.1) : Color.clear)
                    )
                    .onTapGesture {
                        withAnimation(.spring()) {
                            selectedSlice = selectedSlice?.id == slice.id ? nil : slice
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            // 饼图
            ZStack {
                ForEach(slices) { slice in
                    CategoryPieSliceView(slice: slice, size: 200)
                        .scaleEffect(selectedSlice?.id == slice.id ? 1.05 : 1.0)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                selectedSlice = selectedSlice?.id == slice.id ? nil : slice
                            }
                        }
                }
            }
            .frame(width: 200, height: 200)
        }
    }
}

// MARK: - 目录饼图切片视图

struct CategoryPieSliceView: View {
    let slice: CategoryPieSlice
    let size: CGFloat

    /// 内圆半径比例，设置为外圆半径的40%，形成圆环
    private var innerRadiusRatio: CGFloat {
        0.4
    }

    private var outerRadius: CGFloat {
        size / 2
    }

    private var innerRadius: CGFloat {
        outerRadius * innerRadiusRatio
    }

    var path: Path {
        var path = Path()
        let center = CGPoint(x: size / 2, y: size / 2)

        let startAngleRad = Double(slice.startAngle - 90) * .pi / 180
        let endAngleRad = Double(slice.endAngle - 90) * .pi / 180

        // 计算外圆起始点和内圆结束点
        let outerStart = CGPoint(
            x: center.x + outerRadius * CGFloat(cos(startAngleRad)),
            y: center.y + outerRadius * CGFloat(sin(startAngleRad))
        )
        let innerEnd = CGPoint(
            x: center.x + innerRadius * CGFloat(cos(endAngleRad)),
            y: center.y + innerRadius * CGFloat(sin(endAngleRad))
        )

        // 绘制圆环段路径
        // 1. 从外圆起始点开始
        path.move(to: outerStart)
        // 2. 沿着外圆绘制到结束点
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(slice.startAngle - 90),
            endAngle: .degrees(slice.endAngle - 90),
            clockwise: false
        )
        // 3. 连接到内圆结束点
        path.addLine(to: innerEnd)
        // 4. 沿着内圆反向绘制回到起始点
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(slice.endAngle - 90),
            endAngle: .degrees(slice.startAngle - 90),
            clockwise: true
        )
        // 5. 闭合路径
        path.closeSubpath()

        return path
    }

    var body: some View {
        path
            .fill(slice.color)
            .overlay(
                path.stroke(Color(UIColor.systemBackground), lineWidth: 1.5)
            )
    }
}

// MARK: - 分组饼图视图

struct GroupPieChartView: View {
    let data: [GroupOrderData]
    @State private var selectedSlice: GroupPieSlice?

    private var slices: [GroupPieSlice] {
        let total = data.reduce(0) { $0 + Double($1.orderCount) }
        guard total > 0 else { return [] }

        // 按订单数降序排序
        let sortedData = data.sorted { $0.orderCount > $1.orderCount }

        // 只取前10个分组
        let top10Groups = Array(sortedData.prefix(10))
        let remainingGroups = Array(sortedData.dropFirst(10))

        // 计算前10个分组的占比
        var finalItems: [(item: GroupOrderData, percentage: Double)] = top10Groups.map { item in
            (item: item, percentage: Double(item.orderCount) / total * 100)
        }

        // 如果有剩余分组，合并为"其他"
        if !remainingGroups.isEmpty {
            let otherTotalCount = remainingGroups.reduce(0) { $0 + $1.orderCount }
            let otherPercentage = Double(otherTotalCount) / total * 100
            finalItems.append((
                item: GroupOrderData(
                    id: -1, // 使用-1作为"其他"的ID
                    name: NSLocalizedString("Structure_Market_Other", comment: "其他"),
                    orderCount: otherTotalCount,
                    iconFileName: IconManager.defaultIcon
                ),
                percentage: otherPercentage
            ))
        }

        // 生成颜色（扩展颜色数组，避免重复）
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .red, .yellow,
            .pink, .cyan, .mint, .indigo, .teal, .brown,
            Color(red: 0.2, green: 0.6, blue: 0.8), // 天蓝色
            Color(red: 0.8, green: 0.4, blue: 0.2), // 橙红色
            Color(red: 0.6, green: 0.8, blue: 0.2), // 黄绿色
            Color(red: 0.8, green: 0.2, blue: 0.6), // 粉紫色
            Color(red: 0.4, green: 0.2, blue: 0.8), // 深紫色
            Color(red: 0.2, green: 0.8, blue: 0.6), // 青绿色
            Color(red: 0.9, green: 0.5, blue: 0.1), // 金橙色
            Color(red: 0.3, green: 0.7, blue: 0.9), // 亮蓝色
            Color(red: 0.7, green: 0.3, blue: 0.9), // 亮紫色
            Color(red: 0.5, green: 0.9, blue: 0.3), // 亮绿色
            Color(red: 0.9, green: 0.7, blue: 0.2), // 金黄色
            Color(red: 0.6, green: 0.3, blue: 0.9), // 深蓝紫色
        ]

        // 生成切片
        var startAngle = 0.0
        return finalItems.enumerated().map { index, itemWithPercentage in
            let angle = 360 * (itemWithPercentage.percentage / 100)
            // "其他"使用灰色，其他分组使用颜色数组
            let color = itemWithPercentage.item.id == -1 ? Color.gray : colors[index % colors.count]
            let slice = GroupPieSlice(
                id: itemWithPercentage.item.id,
                name: itemWithPercentage.item.name,
                orderCount: itemWithPercentage.item.orderCount,
                percentage: itemWithPercentage.percentage,
                startAngle: startAngle,
                endAngle: startAngle + angle,
                color: color
            )
            startAngle += angle
            return slice
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            // 图例
            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        // 颜色方块
                        Rectangle()
                            .fill(slice.color)
                            .frame(width: 12, height: 12)
                            .cornerRadius(2)
                            .overlay(
                                // 高亮边框
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(selectedSlice?.id == slice.id ? Color.primary : Color.clear, lineWidth: 2)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            // 分组名称
                            Text(slice.name)
                                .font(.caption)
                                .fontWeight(selectedSlice?.id == slice.id ? .semibold : .regular)
                                .foregroundColor(selectedSlice?.id == slice.id ? .primary : .primary)

                            // 占比和订单数
                            Text(
                                String(format: "%.1f%% (%d)",
                                       slice.percentage,
                                       slice.orderCount)
                            )
                            .font(.caption2)
                            .foregroundColor(selectedSlice?.id == slice.id ? .primary : .secondary)
                        }
                    }
                    .padding(.horizontal, selectedSlice?.id == slice.id ? 4 : 0)
                    .padding(.vertical, selectedSlice?.id == slice.id ? 2 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(selectedSlice?.id == slice.id ? Color.secondary.opacity(0.1) : Color.clear)
                    )
                    .onTapGesture {
                        withAnimation(.spring()) {
                            selectedSlice = selectedSlice?.id == slice.id ? nil : slice
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            // 饼图
            ZStack {
                ForEach(slices) { slice in
                    GroupPieSliceView(slice: slice, size: 200)
                        .scaleEffect(selectedSlice?.id == slice.id ? 1.05 : 1.0)
                        .onTapGesture {
                            withAnimation(.spring()) {
                                selectedSlice = selectedSlice?.id == slice.id ? nil : slice
                            }
                        }
                }
            }
            .frame(width: 200, height: 200)
        }
    }
}

// MARK: - 分组饼图切片视图

struct GroupPieSliceView: View {
    let slice: GroupPieSlice
    let size: CGFloat

    /// 内圆半径比例，设置为外圆半径的40%，形成圆环
    private var innerRadiusRatio: CGFloat {
        0.4
    }

    private var outerRadius: CGFloat {
        size / 2
    }

    private var innerRadius: CGFloat {
        outerRadius * innerRadiusRatio
    }

    var path: Path {
        var path = Path()
        let center = CGPoint(x: size / 2, y: size / 2)

        let startAngleRad = Double(slice.startAngle - 90) * .pi / 180
        let endAngleRad = Double(slice.endAngle - 90) * .pi / 180

        // 计算外圆起始点和内圆结束点
        let outerStart = CGPoint(
            x: center.x + outerRadius * CGFloat(cos(startAngleRad)),
            y: center.y + outerRadius * CGFloat(sin(startAngleRad))
        )
        let innerEnd = CGPoint(
            x: center.x + innerRadius * CGFloat(cos(endAngleRad)),
            y: center.y + innerRadius * CGFloat(sin(endAngleRad))
        )

        // 绘制圆环段路径
        // 1. 从外圆起始点开始
        path.move(to: outerStart)
        // 2. 沿着外圆绘制到结束点
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: .degrees(slice.startAngle - 90),
            endAngle: .degrees(slice.endAngle - 90),
            clockwise: false
        )
        // 3. 连接到内圆结束点
        path.addLine(to: innerEnd)
        // 4. 沿着内圆反向绘制回到起始点
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .degrees(slice.endAngle - 90),
            endAngle: .degrees(slice.startAngle - 90),
            clockwise: true
        )
        // 5. 闭合路径
        path.closeSubpath()

        return path
    }

    var body: some View {
        path
            .fill(slice.color)
            .overlay(
                path.stroke(Color(UIColor.systemBackground), lineWidth: 1.5)
            )
    }
}
