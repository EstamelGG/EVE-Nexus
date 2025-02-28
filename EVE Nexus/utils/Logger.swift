import Foundation
import OSLog
import UIKit

class Logger {
    static let shared = Logger()
    private let fileManager = FileManager.default
    private let dateFormatter = DateFormatter()
    private let logQueue = DispatchQueue(label: "com.eve.nexus.logger")
    private var currentLogFile: URL?
    private let maxLogFiles = 7 // 保留最近7天的日志
    
    private init() {
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        // 确保在访问 StaticResourceManager 之前完成基本初始化
        DispatchQueue.main.async { [weak self] in
            self?.setupLogDirectory()
            self?.rotateLogFiles()
            self?.createNewLogFile()
        }
    }
    
    private func setupLogDirectory() {
        let logPath = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent("Logs")
        try? fileManager.createDirectory(at: logPath, withIntermediateDirectories: true)
    }
    
    private func createNewLogFile() {
        let logPath = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent("Logs")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "EVE_Nexus_\(formatter.string(from: Date())).log"
        currentLogFile = logPath.appendingPathComponent(fileName)
        
        // 写入日志文件头部信息
        let header = """
        =====================================
        EVE Panel Log File
        Created at: \(dateFormatter.string(from: Date()))
        Device: \(UIDevice.current.model)
        System: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        =====================================\n\n
        """
        try? header.write(to: currentLogFile!, atomically: true, encoding: .utf8)
        
        Logger.info("Log session started")
    }
    
    private func rotateLogFiles() {
        let logPath = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent("Logs")
        
        do {
            let files = try fileManager.contentsOfDirectory(at: logPath, includingPropertiesForKeys: [.creationDateKey])
            let sortedFiles = files.filter { $0.pathExtension == "log" }
                .sorted { (file1, file2) -> Bool in
                    let date1 = try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return date1! > date2!
                }
            
            // 删除超过最大数量的旧日志文件
            if sortedFiles.count > maxLogFiles {
                for file in sortedFiles[maxLogFiles...] {
                    try? fileManager.removeItem(at: file)
                }
            }
        } catch {
            os_log("Failed to rotate log files: %{public}@", type: .error, error.localizedDescription)
        }
    }
    
    private func writeToFile(_ message: String, type: OSLogType) {
        guard let logFile = currentLogFile else { return }
        
        logQueue.async {
            let timestamp = self.dateFormatter.string(from: Date())
            let logLevel = self.logLevelString(for: type)
            let logMessage = "[\(timestamp)] [\(logLevel)] \(message)\n"
            
            if let data = logMessage.data(using: .utf8) {
                if self.fileManager.fileExists(atPath: logFile.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        try? fileHandle.close()
                    }
                } else {
                    try? data.write(to: logFile, options: .atomic)
                }
            }
        }
    }
    
    private func logLevelString(for type: OSLogType) -> String {
        switch type {
        case .debug:
            return NSLocalizedString("Main_Setting_Logs_Level_Debug", comment: "")
        case .info:
            return NSLocalizedString("Main_Setting_Logs_Level_Info", comment: "")
        case .error:
            return NSLocalizedString("Main_Setting_Logs_Level_Error", comment: "")
        case .fault:
            return NSLocalizedString("Main_Setting_Logs_Level_Warning", comment: "")
        default:
            return NSLocalizedString("Main_Setting_Logs_Level_Info", comment: "")
        }
    }
    
    // 公共日志方法
    static func debug(_ message: String) {
        os_log("%{public}@", type: .debug, message)
        shared.writeToFile(message, type: .debug)
    }
    
    static func info(_ message: String) {
        os_log("%{public}@", type: .info, message)
        shared.writeToFile(message, type: .info)
    }
    
    static func warning(_ message: String) {
        os_log("%{public}@", type: .fault, message)
        shared.writeToFile(message, type: .fault)
    }
    
    static func error(_ message: String, error: Error? = nil, showAlert: Bool = true) {
        os_log("%{public}@", type: .error, message)
        let errorMessage = "\(message) \(error?.localizedDescription ?? "")"
        // 记录到文件
        shared.writeToFile(errorMessage, type: .error)
    }
    
    static func fault(_ message: String) {
        os_log("%{public}@", type: .fault, message)
        shared.writeToFile(message, type: .fault)
    }
    
    // 获取所有日志文件
    static func getAllLogFiles() -> [URL] {
        let logPath = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent("Logs")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logPath,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        return files.filter { $0.pathExtension == "log" }
            .sorted { (file1, file2) -> Bool in
                let date1 = try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1! > date2!
            }
    }
    
    // 读取日志文件内容
    static func readLogFile(_ file: URL) -> String {
        do {
            return try String(contentsOf: file, encoding: .utf8)
        } catch {
            os_log("Failed to read log file: %{public}@", type: .error, error.localizedDescription)
            return "Failed to read log file: \(error.localizedDescription)"
        }
    }
    
    // 清除所有日志文件
    static func clearAllLogs() {
        let logPath = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent("Logs")
        do {
            let files = try FileManager.default.contentsOfDirectory(at: logPath, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "log" {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            os_log("Failed to clear log files: %{public}@", type: .error, error.localizedDescription)
        }
    }
} 
