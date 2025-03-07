import Foundation

enum AppConfiguration {
    // 应用版本信息
    enum Version {
        static var fullVersion: String {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? "Unknown"
        }
    }

    // 数据库版本信息
    enum Database {
        static var version: String {
            Bundle.main.object(forInfoDictionaryKey: "EVEDatabaseVersion") as? String ?? "Unknown"
        }
    }
}
