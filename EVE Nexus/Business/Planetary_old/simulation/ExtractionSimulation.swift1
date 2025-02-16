import Foundation

class ExtractionSimulation {
    private static let SEC: Int64 = 10000000
    private static let decayFactor: Double = 0.012
    private static let noiseFactor: Double = 0.8
    private static let f1: Double = 1.0 / 12.0
    private static let f2: Double = 1.0 / 5.0
    private static let f3: Double = 1.0 / 2.0
    
    /// 计算特定时间点的产出
    /// - Parameters:
    ///   - baseValue: 基础产量
    ///   - startTime: 开始时间
    ///   - currentTime: 当前时间
    ///   - cycleTime: 周期时长（秒）
    /// - Returns: 该时间点的产量
    static func getProgramOutput(
        baseValue: Int,
        startTime: Date,
        currentTime: Date,
        cycleTime: TimeInterval
    ) -> Int64 {
        let startTimeSeconds = Int64(startTime.timeIntervalSince1970 * Double(SEC))
        let currentTimeSeconds = Int64(currentTime.timeIntervalSince1970 * Double(SEC))
        let cycleTimeSeconds = Int64(cycleTime * Double(SEC))
        
        return getProgramOutput(
            baseValue: baseValue,
            startTime: startTimeSeconds,
            currentTime: currentTimeSeconds,
            cycleTime: cycleTimeSeconds
        )
    }
    
    /// 预测未来多个周期的产出
    /// - Parameters:
    ///   - baseValue: 基础产量
    ///   - cycleDuration: 周期时长（秒）
    ///   - length: 预测周期数
    /// - Returns: 预测的产量列表
    static func getProgramOutputPrediction(
        baseValue: Int,
        cycleDuration: TimeInterval,
        length: Int
    ) -> [Int64] {
        var results = [Int64]()
        let startTime: Int64 = 0
        let cycleTime = Int64(cycleDuration * Double(SEC))
        
        for i in 0..<length {
            let currentTime = Int64(i + 1) * cycleTime
            results.append(getProgramOutput(
                baseValue: baseValue,
                startTime: startTime,
                currentTime: currentTime,
                cycleTime: cycleTime
            ))
        }
        
        return results
    }
    
    // MARK: - Private Methods
    
    private static func getProgramOutput(
        baseValue: Int,
        startTime: Int64,
        currentTime: Int64,
        cycleTime: Int64
    ) -> Int64 {
        let timeDiff = currentTime - startTime
        let cycleNum = max((timeDiff + SEC) / cycleTime - 1, 0)
        let barWidth = Double(cycleTime) / Double(SEC) / 900.0
        let t = (Double(cycleNum) + 0.5) * barWidth
        
        // 计算衰减值
        let decayValue = Double(baseValue) / (1.0 + t * decayFactor)
        
        // 计算相移
        let phaseShift = pow(Double(baseValue), 0.7)
        
        // 计算波动
        let sinA = cos(phaseShift + t * f1)
        let sinB = cos(phaseShift / 2.0 + t * f2)
        let sinC = cos(t * f3)
        let sinStuff = max((sinA + sinB + sinC) / 3.0, 0.0)
        
        // 计算最终产量
        let barHeight = decayValue * (1.0 + noiseFactor * sinStuff)
        let output = barWidth * barHeight
        
        // 向下取整
        return Int64(floor(output))
    }
} 