import Foundation

class ExtractionSimulator {
    private static let SEC: Int64 = 10000000
    
    /// 预测提取器在给定时间段内的产出
    /// - Parameters:
    ///   - baseValue: 基础产出值
    ///   - cycleDuration: 循环时长
    ///   - length: 需要预测的循环数量
    /// - Returns: 每个循环的产出值列表
    static func getProgramOutputPrediction(
        baseValue: Int,
        cycleDuration: TimeInterval,
        length: Int
    ) -> [Int64] {
        var outputs: [Int64] = []
        let cycleTime = Int64(cycleDuration) * SEC
        
        for i in 0..<length {
            let currentTime = Int64(i + 1) * cycleTime
            outputs.append(getProgramOutput(
                baseValue: baseValue,
                startTime: 0,
                currentTime: currentTime,
                cycleTime: cycleTime
            ))
        }
        return outputs
    }
    
    /// 计算提取器在特定时间点的产出
    /// - Parameters:
    ///   - baseValue: 基础产出值
    ///   - startTime: 开始时间
    ///   - currentTime: 当前时间
    ///   - cycleTime: 循环时长
    static func getProgramOutput(
        baseValue: Int,
        startTime: Date,
        currentTime: Date,
        cycleTime: TimeInterval
    ) -> Int64 {
        return getProgramOutput(
            baseValue: baseValue,
            startTime: Int64(startTime.timeIntervalSince1970) * SEC,
            currentTime: Int64(currentTime.timeIntervalSince1970) * SEC,
            cycleTime: Int64(cycleTime) * SEC
        )
    }
    
    /// 计算提取器在特定时间点的产出（内部实现）
    private static func getProgramOutput(
        baseValue: Int,
        startTime: Int64,
        currentTime: Int64,
        cycleTime: Int64
    ) -> Int64 {
        let decayFactor = 0.012
        let noiseFactor = 0.8
        let timeDiff = currentTime - startTime
        let cycleNum = max((timeDiff + SEC) / cycleTime - 1, 0)
        let barWidth = Double(cycleTime) / Double(SEC) / 900.0
        let t = (Double(cycleNum) + 0.5) * barWidth
        
        // 计算衰减值
        let decayValue = Double(baseValue) / (1 + t * decayFactor)
        
        // 计算波动
        let f1 = 1.0 / 12.0
        let f2 = 1.0 / 5.0
        let f3 = 1.0 / 2.0
        let phaseShift = pow(Double(baseValue), 0.7)
        let sinA = cos(phaseShift + t * f1)
        let sinB = cos(phaseShift / 2.0 + t * f2)
        let sinC = cos(t * f3)
        var sinStuff = (sinA + sinB + sinC) / 3.0
        sinStuff = max(0.0, sinStuff)
        
        // 计算最终产出
        let barHeight = decayValue * (1 + noiseFactor * sinStuff)
        let output = barWidth * barHeight
        
        // 向下取整，整数也向下取整
        return output.truncatingRemainder(dividingBy: 1) == 0 ? Int64(output) - 1 : Int64(output)
    }
} 