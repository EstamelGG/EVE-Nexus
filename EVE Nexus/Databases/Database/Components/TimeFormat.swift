//
//  TimeFormat.swift
//  EVE Panel
//
//  Created by GG Estamel on 2024/12/10.
//

import SwiftUI

func formatTime(_ totalSeconds: Int) -> String {
    var seconds = totalSeconds
    
    // 计算各个时间单位
    let year = seconds / (365 * 24 * 3600)
    seconds %= (365 * 24 * 3600)
    
    let month = seconds / (30 * 24 * 3600)
    seconds %= (30 * 24 * 3600)
    
    let day = seconds / (24 * 3600)
    seconds %= (24 * 3600)
    
    let hour = seconds / 3600
    seconds %= 3600
    
    let minute = seconds / 60
    let remainingSeconds = seconds % 60
    
    var components: [String] = []
    
    // 按顺序添加各个时间单位
    if year > 0 {
        components.append("\(year)\(NSLocalizedString("Time_Year", comment: ""))")
    }
    
    if month > 0 {
        components.append("\(month)\(NSLocalizedString("Time_Month", comment: ""))")
    }
    
    if day > 0 {
        components.append("\(day)\(NSLocalizedString("Time_Day", comment: ""))")
    }
    
    if hour > 0 {
        components.append("\(hour)\(NSLocalizedString("Time_Hour", comment: ""))")
    }
    
    // 如果有更大的时间单位，且分钟为0，则不显示分钟
    if minute > 0 || (components.isEmpty && remainingSeconds == 0) {
        components.append("\(minute)\(NSLocalizedString("Time_Minute", comment: ""))")
    }
    
    // 如果只有秒数，或者有分钟且有秒数，则显示秒数
    if remainingSeconds > 0 || components.isEmpty {
        components.append("\(remainingSeconds)\(NSLocalizedString("Time_Second", comment: ""))")
    }
    
    return components.joined(separator: " ")
}
