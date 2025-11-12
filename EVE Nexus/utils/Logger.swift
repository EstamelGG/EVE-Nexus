import Foundation
import OSLog
import Pulse
import UIKit

class Logger {
    static let shared = Logger()

    let loggerStore: LoggerStore
    private let fileManager = FileManager.default

    // 是否输出日志到文件，通过UserDefaults控制
    private var ifWriteToFile: Bool {
        return UserDefaults.standard.bool(forKey: "enableLogging")
    }

    // 日志长度限制
    private static var maxDebugLogLength = 2000
    private static var maxInfoLogLength = 200_000

    // 静态初始化方法，应在应用启动时调用
    static func configure() {
        // Pulse 会在首次访问 LoggerStore 时自动初始化
        // 不需要额外的配置
    }

    private init() {
        // 总是使用自定义路径存储日志，不管是否启用调试模式
        // 这样日志总是被记录，只是用户界面上的查看按钮受 enableLogging 控制
        let logPath = StaticResourceManager.shared.getStaticDataSetPath().appendingPathComponent("Logs")
        try? fileManager.createDirectory(at: logPath, withIntermediateDirectories: true)
        let storeURL = logPath.appendingPathComponent("Pulse.store")

        // 配置日志存储：限制大小为 100MB，启用自动清理
        // sizeLimit: 100MB，当达到此大小后会自动清理旧数据
        // maxAge: 默认 14 天，超过此时间的日志会被自动删除
        // sweep: 默认已启用，会自动定期清理
        var configuration = LoggerStore.Configuration(sizeLimit: 40 * 1_000_000) // 40 MB
        configuration.maxAge = 7 * 86400 // 14 天

        // LoggerStore 初始化可能抛出错误，使用 try? 处理
        // 默认选项包含 .create 和 .sweep，启用自动清理功能
        if let store = try? LoggerStore(storeURL: storeURL, options: [.create, .sweep], configuration: configuration) {
            loggerStore = store
        } else {
            // 如果创建失败，使用默认的 shared store
            loggerStore = LoggerStore.shared
        }

        // 监听UserDefaults变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )

        // 延迟写入日志头部信息
        DispatchQueue.main.async { [weak self] in
            self?.writeLogHeader()
        }
    }

    @objc private func userDefaultsDidChange() {
        // UserDefaults 变化时，Pulse 会自动处理日志的启用/禁用
        // 不需要重新配置
    }

    private func writeLogHeader() {
        guard ifWriteToFile else { return }

        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo
        let deviceIdentifier = getDeviceIdentifier()
        let memoryInfo = getMemoryUsage()
        let cpuUsage = getCPUUsage()

        // 获取磁盘空间信息
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var availableSpace: Int64 = 0
        var totalSpace: Int64 = 0

        do {
            let values = try documentsPath.resourceValues(forKeys: [
                .volumeAvailableCapacityKey, .volumeTotalCapacityKey,
            ])
            availableSpace = Int64(values.volumeAvailableCapacity ?? 0)
            totalSpace = Int64(values.volumeTotalCapacity ?? 0)
        } catch {
            // 忽略错误，使用默认值
        }

        // 格式化内存显示 (MB)
        let memoryDisplay = String(format: "%.0fMB/%.0fMB", memoryInfo.used, memoryInfo.total)

        // 格式化存储空间显示 (MB)
        let usedStorageMB = Double(totalSpace - availableSpace) / 1024.0 / 1024.0
        let totalStorageMB = Double(totalSpace) / 1024.0 / 1024.0
        let storageDisplay = String(format: "%.0fMB/%.0fMB", usedStorageMB, totalStorageMB)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // 写入日志文件头部信息
        let header = """

        =====================================
        EVE Nexus Debug Log
        Created at: \(dateFormatter.string(from: Date()))

        === 设备信息 ===
        Device Model: \(deviceIdentifier)
        iOS Version: \(device.systemName) \(processInfo.operatingSystemVersionString)
        App Version: v\(AppConfiguration.Version.fullVersion)

        === 系统资源状态 ===
        内存使用: \(memoryDisplay)
        CPU 使用率: \(String(format: "%.1f", cpuUsage))%
        存储使用: \(storageDisplay)

        === 日志配置 ===
        Log Level: All levels enabled
        File Logging: \(ifWriteToFile ? "启用" : "禁用")
        =====================================

        """

        loggerStore.storeMessage(label: "com.eve.nexus.logger", level: .info, message: header, metadata: nil, file: #file, function: #function, line: UInt(#line))
    }

    // 获取设备标识符
    private func getDeviceIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    // 获取当前内存使用情况
    private func getMemoryUsage() -> (used: Double, total: Double) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            let totalMemory = Double(ProcessInfo.processInfo.physicalMemory) / 1024.0 / 1024.0
            return (used: usedMB, total: totalMemory)
        }
        return (used: 0, total: 0)
    }

    // 获取CPU使用率
    private func getCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            var threadsList: thread_act_array_t?
            var threadsCount = mach_msg_type_number_t(0)

            let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)
            if threadsResult == KERN_SUCCESS {
                var totalCPU: Double = 0

                for i in 0 ..< threadsCount {
                    var threadInfo = thread_basic_info()
                    var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)

                    let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                            thread_info(
                                threadsList![Int(i)], thread_flavor_t(THREAD_BASIC_INFO), $0,
                                &threadInfoCount
                            )
                        }
                    }

                    if infoResult == KERN_SUCCESS {
                        totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                    }
                }

                // 清理内存
                vm_deallocate(
                    mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)),
                    vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.size)
                )

                return totalCPU
            }
        }
        return 0
    }

    // 格式化调用位置信息
    private static func formatLocation(file: String, function: String, line: UInt) -> String {
        let fileName = (file as NSString).lastPathComponent
        return "[\(fileName):\(line)] \(function): "
    }

    // 内部辅助函数，用于处理日志消息和位置信息
    private static func _log(
        message: String,
        level: LoggerStore.Level,
        maxLength: Int,
        osLogType: OSLogType,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        // 将调用位置信息附加到消息前面，用换行分隔
        // 注意：由于 Swift 的限制，file/function/line 会在 Logger 方法定义处评估
        // 但至少我们可以在消息中包含这些信息
        let locationPrefix = formatLocation(file: file, function: function, line: line)
        let finalMessage = locationPrefix + "\n" + message
        let truncatedMessage = truncateMessage(finalMessage, maxLength: maxLength)

        #if DEBUG
            os_log("%{private}@", type: osLogType, truncatedMessage)
        #endif

        shared.loggerStore.storeMessage(
            label: "com.eve.nexus.logger",
            level: level,
            message: truncatedMessage
        )
    }

    // 公共日志方法 - 使用默认参数自动捕获调用位置（虽然会显示 Logger 的位置，但会在消息中包含）
    static func debug(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        _log(message: message, level: .debug, maxLength: maxDebugLogLength, osLogType: .debug, file: file, function: function, line: line)
    }

    static func info(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        _log(message: message, level: .info, maxLength: maxInfoLogLength, osLogType: .info, file: file, function: function, line: line)
    }

    static func notice(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        _log(message: message, level: .notice, maxLength: maxInfoLogLength, osLogType: .info, file: file, function: function, line: line)
    }

    static func success(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        _log(message: message, level: .success, maxLength: maxInfoLogLength, osLogType: .info, file: file, function: function, line: line)
    }

    static func warning(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        _log(message: message, level: .warning, maxLength: maxInfoLogLength, osLogType: .default, file: file, function: function, line: line)
    }

    static func error(_ message: String, error: Error? = nil, showAlert _: Bool = true, file: String = #file, function: String = #function, line: UInt = #line) {
        let errorMessage = error != nil ? "\(message) \(error!.localizedDescription)" : message
        _log(message: errorMessage, level: .error, maxLength: maxInfoLogLength, osLogType: .error, file: file, function: function, line: line)
    }

    static func fault(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        _log(message: message, level: .critical, maxLength: maxInfoLogLength, osLogType: .fault, file: file, function: function, line: line)
    }

    // 截断消息到指定长度
    private static func truncateMessage(_ message: String, maxLength: Int) -> String {
        if message.count <= maxLength {
            return message
        } else {
            return message.prefix(maxLength) + "......"
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
