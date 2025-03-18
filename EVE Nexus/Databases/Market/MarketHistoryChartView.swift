import Charts
import SwiftUI

// 市场历史图表视图
struct MarketHistoryChartView: View {
    let history: [MarketHistory]
    let orders: [MarketOrder]

    // 使用@State存储月份第一天的集合，但初始化时就计算好
    @State private var firstDaysOfMonth: Set<String>

    // 缓存图表相关的计算结果
    private let chartData: ChartData

    // 图表数据结构
    private struct ChartData {
        let dates: [String]
        let priceValues: [Double]
        let volumeValues: [Double]
        let maxVolume: Double
        let minPrice: Double
        let maxPrice: Double
        let yMin: Double
        let yMax: Double
        let effectiveRange: Double
    }

    // 初始化时计算月份第一天和图表数据
    init(history: [MarketHistory], orders: [MarketOrder]) {
        self.history = history
        self.orders = orders

        // 计算图表数据
        let dates = history.map { $0.date }
        let priceValues = history.map { $0.average }
        let volumeValues = history.map { Double($0.volume) }
        let maxVolume = volumeValues.max() ?? 1

        // 计算价格范围
        let minPrice = priceValues.min() ?? 0
        let maxPrice = priceValues.max() ?? 1
        let priceRange = maxPrice - minPrice
        let yMin = max(0, minPrice - priceRange * 0.15)
        let yMax = maxPrice + priceRange * 0.15
        let effectiveRange = yMax - yMin

        // 初始化图表数据
        self.chartData = ChartData(
            dates: dates,
            priceValues: priceValues,
            volumeValues: volumeValues,
            maxVolume: maxVolume,
            minPrice: minPrice,
            maxPrice: maxPrice,
            yMin: yMin,
            yMax: yMax,
            effectiveRange: effectiveRange
        )

        // 在初始化时就计算好月份第一天，避免视图重新出现时重复计算
        _firstDaysOfMonth = State(initialValue: Self.calculateFirstDaysOfMonth(in: dates))
    }

    // 格式化日期显示（只显示月份）
    private func formatMonth(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US")
        guard let date = dateFormatter.date(from: dateString) else { return "" }

        dateFormatter.dateFormat = "MMM"
        return dateFormatter.string(from: date).uppercased()
    }

    // 获取当前总交易量
    private var totalVolume: Int {
        orders.filter { !$0.isBuyOrder }.reduce(0) { $0 + $1.volumeTotal }
    }

    // 静态方法计算所有月份的第一个数据点
    private static func calculateFirstDaysOfMonth(in dates: [String]) -> Set<String> {
        let dateFormatter = DateFormatter()
        Logger.info("提取横坐标月份点")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        var result = Set<String>()
        var lastMonth: Int? = nil

        // 按日期排序
        let sortedDates = dates.sorted()

        for (index, dateString) in sortedDates.enumerated() {
            guard let date = dateFormatter.date(from: dateString) else { continue }
            let currentMonth = Calendar.current.component(.month, from: date)

            // 如果是第一个数据点或者月份变化了，则添加到结果集
            if index == 0 || currentMonth != lastMonth {
                result.insert(dateString)
            }

            lastMonth = currentMonth
        }

        return result
    }

    var body: some View {
        // 使用缓存的图表数据
        Chart {
            ForEach(history, id: \.date) { item in
                // 成交量柱状图 - 从yMin开始，高度为归一化后的值
                BarMark(
                    x: .value("Date", item.date),
                    yStart: .value("VolumeStart", chartData.yMin),
                    yEnd: .value(
                        "VolumeEnd",
                        chartData.yMin + (Double(item.volume) / chartData.maxVolume)
                            * chartData.effectiveRange * 0.7
                    )
                )
                .foregroundStyle(.gray.opacity(0.8))
            }

            ForEach(history, id: \.date) { item in
                // 价格线
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Price", item.average)
                )
                .foregroundStyle(.blue)
                .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: chartData.yMin...chartData.yMax)
        .chartYAxis {
            // 价格轴（左侧）
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                if let price = value.as(Double.self) {
                    AxisValueLabel {
                        Text(FormatUtil.formatISK(price))
                            .font(.system(size: 10))
                    }
                    AxisGridLine()
                }
            }
        }
        .chartYAxis {
            // 成交量轴（右侧）
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                if let price = value.as(Double.self) {
                    // 反向计算成交量
                    let volume = Int(
                        ((price - chartData.yMin) / (chartData.effectiveRange * 0.7))
                            * chartData.maxVolume)
                    AxisValueLabel {
                        Text("\(volume)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(.gray.opacity(0.1))
        }
        .chartXAxis {
            AxisMarks(values: chartData.dates) { value in
                if let dateStr = value.as(String.self),
                    firstDaysOfMonth.contains(dateStr)
                {
                    AxisValueLabel(anchor: .top) {
                        Text(formatMonth(dateStr))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    AxisGridLine()
                }
            }
        }
        .frame(height: 200)
        .padding(.top, 8)
        .id("chart_\(history.count)_\(history.first?.date ?? "")")  // 添加一个稳定的ID，只有当数据真正变化时才会改变
    }
}
