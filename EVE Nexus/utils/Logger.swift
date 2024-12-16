import Foundation
import os.log

enum LogLevel: String {
    case error = "[✕]"   // 错误：执行失败、创建失败等
    case warning = "[!]"  // 警告：可能的问题、需要注意的情况
    case info = "[✓]"    // 信息：执行成功、加载成功等
    case debug = "[•]"    // 调试：详细的调试信息
    
    var osLogType: OSLogType {
        switch self {
        case .error: return .error
        case .warning: return .fault
        case .info: return .info
        case .debug: return .debug
        }
    }
}

class Logger {
    static let shared = Logger()
    private let osLog: OSLog
    
    private init() {
        self.osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.ev_nexus", category: "Database")
    }
    
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(fileName):\(line)] \(function): \(message)"
        os_log("%{public}@ %{public}@", log: osLog, type: level.osLogType, level.rawValue, logMessage)
        #endif
    }
    
    // 便捷方法
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.log(message, level: .error, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.log(message, level: .warning, file: file, function: function, line: line)
    }
    
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.log(message, level: .info, file: file, function: function, line: line)
    }
    
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        shared.log(message, level: .debug, file: file, function: function, line: line)
    }
} 
