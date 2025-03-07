import Foundation
import SwiftUI

class ExtractorYieldCalculator {
    private let quantityPerCycle: Int
    private let cycleTime: Int

    init(quantityPerCycle: Int, cycleTime: Int) {
        self.quantityPerCycle = quantityPerCycle
        self.cycleTime = cycleTime
    }

    func calculateYield(cycleIndex: Int) -> Int {
        let results = ExtractionSimulation.getProgramOutputPrediction(
            baseValue: quantityPerCycle,
            cycleDuration: TimeInterval(cycleTime),
            length: cycleIndex + 1
        )
        return Int(results.last ?? 0)
    }

    func calculateRange(startCycle: Int, endCycle: Int) -> [(cycle: Int, yield: Int)] {
        let results = ExtractionSimulation.getProgramOutputPrediction(
            baseValue: quantityPerCycle,
            cycleDuration: TimeInterval(cycleTime),
            length: endCycle + 1
        )

        return (startCycle...endCycle).map { cycle in
            (cycle: cycle + 1, yield: Int(results[cycle]))
        }
    }

    static func calculateTotalCycles(installTime: String, expiryTime: String, cycleTime: Int) -> Int
    {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        guard let installDate = dateFormatter.date(from: installTime),
            let expiryDate = dateFormatter.date(from: expiryTime)
        else {
            return 0
        }

        let totalSeconds = expiryDate.timeIntervalSince(installDate)
        return Int(totalSeconds / Double(cycleTime)) - 1
    }

    static func getCurrentCycle(installTime: String, expiryTime: String, cycleTime: Int) -> Int {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        guard let installDate = dateFormatter.date(from: installTime),
            let expiryDate = dateFormatter.date(from: expiryTime)
        else {
            return 0
        }

        let elapsedSeconds = Date().timeIntervalSince(installDate)
        let currentCycle = Int(elapsedSeconds / Double(cycleTime))

        // 计算总周期数
        let totalSeconds = expiryDate.timeIntervalSince(installDate)
        let totalCycles = Int(totalSeconds / Double(cycleTime)) - 1

        // 如果超过了总周期数，返回-1表示已结束
        if currentCycle > totalCycles {
            return -1
        }

        return currentCycle
    }
}

// MARK: - 图表视图

struct ExtractorYieldChartView: View {
    let yields: [(cycle: Int, yield: Int)]
    let currentCycle: Int
    let maxYield: Int
    let totalCycles: Int
    let cycleTime: Int
    let installTime: String
    let expiryTime: String
    let currentTime: Date

    // 图表常量
    private let chartHeight: CGFloat = 160
    private let yAxisWidth: CGFloat = 40
    private let gridLines: Int = 5

    init(extractor: PlanetaryExtractor, installTime: String, expiryTime: String?, currentTime: Date)
    {
        guard let qtyPerCycle = extractor.qtyPerCycle,
            let cycleTime = extractor.cycleTime,
            let expiryTime = expiryTime
        else {
            yields = []
            currentCycle = 0
            maxYield = 0
            totalCycles = 0
            self.cycleTime = 0
            self.installTime = ""
            self.expiryTime = ""
            self.currentTime = currentTime
            return
        }

        let calculator = ExtractorYieldCalculator(
            quantityPerCycle: qtyPerCycle, cycleTime: cycleTime
        )
        currentCycle = ExtractorYieldCalculator.getCurrentCycle(
            installTime: installTime, expiryTime: expiryTime, cycleTime: cycleTime
        )
        totalCycles = ExtractorYieldCalculator.calculateTotalCycles(
            installTime: installTime, expiryTime: expiryTime, cycleTime: cycleTime
        )
        self.cycleTime = cycleTime
        self.installTime = installTime
        self.expiryTime = expiryTime
        self.currentTime = currentTime

        // 计算所有周期的数据
        yields = calculator.calculateRange(startCycle: 0, endCycle: totalCycles)
        let actualMaxYield = yields.map { $0.yield }.max() ?? 0
        maxYield = Int(Double(actualMaxYield) * 1.1)
    }

    private func formatYAxisLabel(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        return "\(value)"
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval <= 0 {
            return "00:00:00"
        }

        let days = Int(interval) / 86400
        let hours = Int(interval) / 3600 % 24
        let minutes = Int(interval) / 60 % 60
        let seconds = Int(interval) % 60

        if days > 0 {
            return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func formatElapsedTime(installTime: String) -> String {
        guard let installDate = ISO8601DateFormatter().date(from: installTime) else {
            return "00:00:00"
        }

        // 检查是否所有周期都已结束
        if currentCycle == -1 {
            return "00:00:00"
        }

        let elapsedTime = currentTime.timeIntervalSince(installDate)
        let cycleElapsed = elapsedTime.truncatingRemainder(dividingBy: Double(cycleTime))
        return formatTimeInterval(cycleElapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 图表区域
            HStack(alignment: .center, spacing: 0) {
                // Y轴
                ZStack(alignment: .trailing) {
                    // Y轴标签
                    VStack(spacing: 0) {
                        ForEach(0...gridLines, id: \.self) { i in
                            Text(formatYAxisLabel(maxYield * (gridLines - i) / gridLines))
                                .font(.system(size: 9))
                                .foregroundColor(.primary)
                                .frame(height: chartHeight / CGFloat(gridLines))
                        }
                    }
                }
                .frame(width: yAxisWidth)

                // 图表主体
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        // 背景和边框
                        Rectangle()
                            .fill(Color(UIColor.systemBackground))
                            .border(Color.gray.opacity(0.2), width: 1)

                        // 网格线
                        VStack(spacing: 0) {
                            ForEach(0...gridLines, id: \.self) { i in
                                if i < gridLines {
                                    Spacer()
                                }
                                Divider()
                                    .background(Color.gray.opacity(0.2))
                            }
                        }

                        // 垂直网格线
                        HStack(spacing: 0) {
                            ForEach(0...4, id: \.self) { i in
                                if i > 0 {
                                    Divider()
                                        .background(Color.gray.opacity(0.2))
                                }
                                if i < 4 {
                                    Spacer()
                                }
                            }
                        }

                        // 柱状图
                        HStack(alignment: .bottom, spacing: 1) {
                            ForEach(yields, id: \.cycle) { yield in
                                Rectangle()
                                    .fill(
                                        currentCycle != -1 && yield.cycle == currentCycle + 1
                                            ? Color.teal : Color.gray.opacity(0.6)
                                    )
                                    .frame(
                                        width: (geometry.size.width - CGFloat(yields.count - 1))
                                            / CGFloat(yields.count),
                                        height: CGFloat(yield.yield) / CGFloat(maxYield)
                                            * chartHeight
                                    )
                            }
                        }
                    }
                }
                .frame(height: chartHeight)
                .background(Color(UIColor.systemBackground))
                .border(Color.gray.opacity(0.2), width: 1)
            }
            .padding(.horizontal, 16)

            // 统计信息
            HStack {
                // 标题列
                VStack(alignment: .trailing) {
                    Text(NSLocalizedString("Total_Yield", comment: ""))
                    Text(NSLocalizedString("Current_Cycle_Yield", comment: ""))
                    Text(NSLocalizedString("Current_Cycle_Elapsed", comment: ""))
                    Text(NSLocalizedString("Cycle_Time", comment: ""))
                    Text(NSLocalizedString("Time_Remaining", comment: ""))
                }
                .foregroundColor(.primary)
                .font(.footnote)

                // 数值列
                VStack(alignment: .leading) {
                    Text("\(yields.map { $0.yield }.reduce(0, +))")
                        .foregroundColor(.secondary)
                    if let currentYield = yields.first(where: { $0.cycle == currentCycle + 1 }) {
                        Text("\(currentYield.yield)")
                            .foregroundColor(.teal)
                    } else {
                        Text("0")
                            .foregroundColor(.teal)
                    }
                    Text(formatElapsedTime(installTime: installTime))
                        .foregroundColor(.secondary)
                    Text(formatTimeInterval(TimeInterval(cycleTime)))
                        .foregroundColor(.secondary)
                    if let expiryDate = ISO8601DateFormatter().date(from: expiryTime) {
                        let timeRemaining = expiryDate.timeIntervalSince(currentTime)
                        Text(formatTimeInterval(timeRemaining))
                            .foregroundColor(timeRemaining > 24 * 3600 ? .secondary : .red)
                    } else {
                        Text("00:00:00")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(.footnote, design: .monospaced))
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, -16)
    }
}
