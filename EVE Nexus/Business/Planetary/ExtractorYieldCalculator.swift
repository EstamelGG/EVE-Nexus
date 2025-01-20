import Foundation
import SwiftUI

class ExtractorYieldCalculator {
    private let quantityPerCycle: Int
    private let cycleTime: Int
    private let wCount: Double
    private let phaseShift: Double
    private let decayFactor: Double = 0.012  // ecuDecayFactor 默认值
    private let noiseFactor: Double = 0.8    // ecuNoiseFactor 默认值
    private let f1: Double = 1.0 / 12.0
    private let f2: Double = 1.0 / 5.0
    private let f3: Double = 1.0 / 2.0
    
    init(quantityPerCycle: Int, cycleTime: Int) {
        self.quantityPerCycle = quantityPerCycle
        self.cycleTime = cycleTime
        // 转换周期时间为15分钟单位数
        self.wCount = Double(cycleTime) / 900.0  // 900秒 = 15分钟
        self.phaseShift = pow(Double(quantityPerCycle), 0.7)
    }
    
    func calculateYield(cycleIndex: Int) -> Int {
        // 使用15分钟为基本单位计算时间
        let t = (Double(cycleIndex) + 0.5) * wCount
        
        // 计算衰减
        let decay = Double(quantityPerCycle) / (1.0 + t * decayFactor)
        
        // 计算余弦波动
        let sina = cos(phaseShift + t * f1)
        let sinb = cos(phaseShift / 2 + t * f2)
        let sinc = cos(t * f3)
        
        // 计算波动值
        let sins = max((sina + sinb + sinc) / 3.0, 0.0)
        
        // 计算产量
        let hourlyYield = decay * (1.0 + noiseFactor * sins)
        
        // 返回总产量
        return Int(wCount * hourlyYield)
    }
    
    func calculateRange(startCycle: Int, endCycle: Int) -> [(cycle: Int, yield: Int)] {
        return (startCycle...endCycle).map { cycle in
            (cycle: cycle + 1, yield: calculateYield(cycleIndex: cycle))
        }
    }
    
    static func calculateTotalCycles(installTime: String, expiryTime: String, cycleTime: Int) -> Int {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        guard let installDate = dateFormatter.date(from: installTime),
              let expiryDate = dateFormatter.date(from: expiryTime) else {
            return 0
        }
        
        let totalSeconds = expiryDate.timeIntervalSince(installDate)
        return Int(totalSeconds / Double(cycleTime)) - 1  // 减1是因为周期从0开始
    }
    
    static func getCurrentCycle(installTime: String, cycleTime: Int) -> Int {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        
        guard let installDate = dateFormatter.date(from: installTime) else {
            return 0
        }
        
        let elapsedSeconds = Date().timeIntervalSince(installDate)
        return Int(elapsedSeconds / Double(cycleTime))
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
    @State private var currentTime = Date()
    
    // 图表常量
    private let chartHeight: CGFloat = 160  // 从100增加到160
    private let yAxisWidth: CGFloat = 40
    private let gridLines: Int = 5
    
    init(extractor: PlanetaryExtractor, installTime: String, expiryTime: String?) {
        guard let qtyPerCycle = extractor.qtyPerCycle,
              let cycleTime = extractor.cycleTime,
              let expiryTime = expiryTime else {
            yields = []
            currentCycle = 0
            maxYield = 0
            totalCycles = 0
            self.cycleTime = 0
            self.installTime = ""
            self.expiryTime = ""
            return
        }
        
        let calculator = ExtractorYieldCalculator(quantityPerCycle: qtyPerCycle, cycleTime: cycleTime)
        self.currentCycle = ExtractorYieldCalculator.getCurrentCycle(installTime: installTime, cycleTime: cycleTime)
        self.totalCycles = ExtractorYieldCalculator.calculateTotalCycles(installTime: installTime, expiryTime: expiryTime, cycleTime: cycleTime)
        self.cycleTime = cycleTime
        self.installTime = installTime
        self.expiryTime = expiryTime
        
        // 计算所有周期的数据
        yields = calculator.calculateRange(startCycle: 0, endCycle: totalCycles)
        let actualMaxYield = yields.map { $0.yield }.max() ?? 0
        // 增加10%的缓冲区
        maxYield = Int(Double(actualMaxYield) * 1.1)
    }
    
    private func formatYAxisLabel(_ value: Int) -> String {
        if value >= 1000000 {
            return String(format: "%.1fM", Double(value) / 1000000.0)
        } else if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        return "\(value)"
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
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
        let elapsedTime = currentTime.timeIntervalSince(installDate)
        let cycleElapsed = elapsedTime.truncatingRemainder(dividingBy: Double(cycleTime))
        return formatTimeInterval(cycleElapsed)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {  // 增加spacing从4到8，让整体布局更加舒适
            // 图表区域
            HStack(alignment: .center, spacing: 0) {
                // Y轴
                ZStack(alignment: .trailing) {
                    // Y轴标签
                    VStack(spacing: 0) {
                        ForEach(0...gridLines, id: \.self) { i in
                            Text(formatYAxisLabel(maxYield * (gridLines - i) / gridLines))
                                .font(.system(size: 9))  // 稍微增加字体大小，从8到9
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
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(yields, id: \.cycle) { yield in
                                Rectangle()
                                    .fill(yield.cycle == currentCycle + 1 ? Color.blue : Color.gray.opacity(0.6))
                                    .frame(width: max(1, (geometry.size.width - CGFloat(yields.count)) / CGFloat(yields.count)),
                                           height: CGFloat(yield.yield) / CGFloat(maxYield) * chartHeight)
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
                    Text(formatYAxisLabel(yields.map { $0.yield }.reduce(0, +)))
                        .foregroundColor(.secondary)
                    if let currentYield = yields.first(where: { $0.cycle == currentCycle + 1 }) {
                        Text(formatYAxisLabel(currentYield.yield))
                            .foregroundColor(.secondary)
                    } else {
                        Text("0")
                            .foregroundColor(.secondary)
                    }
                    Text(formatElapsedTime(installTime: installTime))
                        .foregroundColor(.secondary)
                    Text(formatTimeInterval(TimeInterval(cycleTime)))
                        .foregroundColor(.secondary)
                    if let expiryDate = ISO8601DateFormatter().date(from: expiryTime) {
                        Text(formatTimeInterval(expiryDate.timeIntervalSince(currentTime)))
                            .foregroundColor(expiryDate.timeIntervalSince(currentTime) > 24 * 3600 ? .secondary : .yellow)
                    } else {
                        Text("00:00:00")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.system(.footnote, design: .monospaced))
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)  // 增加垂直内边距从4到8
        .padding(.horizontal, -16)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            currentTime = Date()
        }
    }
} 
