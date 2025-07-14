import Foundation
import SwiftUI

// MARK: - 数据模型
struct UpdateLog: Identifiable, Codable {
    let id = UUID()
    let version: String
    let date: String
    let changes: [String]
    
    private enum CodingKeys: String, CodingKey {
        case version, date, changes
    }
}

// MARK: - 更新日志管理器
class UpdateLogManager: ObservableObject {
    static let shared = UpdateLogManager()
    
    private let lastShownVersionKey = "lastShownUpdateVersion"
    
    private init() {
        // 移除初始化时的加载
    }
    
    // MARK: - 公共方法
    
    /// 标记已显示更新通知
    func markUpdateNotificationShown() {
        let currentVersion = AppConfiguration.Version.fullVersion
        UserDefaults.standard.set(currentVersion, forKey: lastShownVersionKey)
        Logger.info("已标记更新通知为已显示 - 版本: \(currentVersion)")
    }
    
    /// 获取所有更新日志（用于设置页面）
    func getAllUpdateLogs() -> [UpdateLog] {
        return loadUpdateLogs()
    }
    
    // MARK: - 私有方法
    
    private func loadUpdateLogs() -> [UpdateLog] {
        guard let path = Bundle.main.path(forResource: "\(NSLocalizedString("whats_new", comment: ""))", ofType: "md"),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            Logger.error("无法读取 whats_new.md 文件")
            return []
        }
        
        let updateLogs = parseMarkdownContent(content)
        Logger.info("成功从 \(path) 加载 \(updateLogs.count) 个版本的更新日志")
        return updateLogs
    }
    
    private func parseMarkdownContent(_ content: String) -> [UpdateLog] {
        let lines = content.components(separatedBy: .newlines)
        var logs: [UpdateLog] = []
        var currentVersion: String?
        var currentDate: String?
        var currentChanges: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.hasPrefix("# ") {
                // 保存前一个版本的日志
                if let version = currentVersion, let date = currentDate {
                    logs.append(UpdateLog(
                        version: version,
                        date: date,
                        changes: currentChanges
                    ))
                }
                
                // 解析新版本标题
                let titleParts = trimmedLine.dropFirst(2).components(separatedBy: " ")
                if titleParts.count >= 2 {
                    currentVersion = titleParts[0]
                    currentDate = titleParts.dropFirst().joined(separator: " ")
                    currentChanges = []
                }
            } else if trimmedLine.hasPrefix("## ") {
                // 处理二级标题作为变更项
                let title = String(trimmedLine.dropFirst(3))
                if !title.isEmpty {
                    currentChanges.append("**\(title)**")
                }
            } else if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                // 处理普通文本行
                currentChanges.append(trimmedLine)
            }
        }
        
        // 保存最后一个版本的日志
        if let version = currentVersion, let date = currentDate {
            logs.append(UpdateLog(
                version: version,
                date: date,
                changes: currentChanges
            ))
        }
        
        return logs
    }
}

// MARK: - 更新通知视图
struct UpdateNotificationView: View {
    let updateLog: UpdateLog
    @Binding var isPresented: Bool
    @State private var animateContent = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 标题区域
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            Text(NSLocalizedString("Update_Notification_Title", comment: "更新内容"))
                                .font(.title2)
                                .fontWeight(.bold)
                        }
                        
                        Text(String(format: NSLocalizedString("Update_Notification_Version", comment: "版本 %@ - %@"), 
                                  updateLog.version, updateLog.date))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // 更新内容
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(updateLog.changes.enumerated()), id: \.offset) { index, change in
                            HStack(alignment: .top, spacing: 12) {
                                // 图标
                                if change.hasPrefix("**") && change.hasSuffix("**") {
                                    // 标题类型
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                        .frame(width: 16, height: 16)
                                } else {
                                    // 普通更新项
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .frame(width: 16, height: 16)
                                }
                                
                                // 内容
                                Text(formatChangeText(change))
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Spacer()
                            }
                            .opacity(animateContent ? 1 : 0)
                            .offset(y: animateContent ? 0 : 20)
                            .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.1), value: animateContent)
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Update_Notification_Got_It", comment: "知道了")) {
                        isPresented = false
                        UpdateLogManager.shared.markUpdateNotificationShown()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                animateContent = true
                UpdateLogManager.shared.markUpdateNotificationShown()
            }
        }
    }
    
    private func formatChangeText(_ change: String) -> String {
        if change.hasPrefix("**") && change.hasSuffix("**") {
            // 移除markdown标记并返回标题
            return String(change.dropFirst(2).dropLast(2))
        }
        return change
    }
}

// MARK: - 更新日志列表视图（用于设置页面）
struct UpdateLogListView: View {
    @StateObject private var updateLogManager = UpdateLogManager.shared
    
    var body: some View {
        NavigationView {
            List {
                ForEach(updateLogManager.getAllUpdateLogs().reversed()) { log in
                    NavigationLink(destination: UpdateLogDetailView(updateLog: log)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(NSLocalizedString("Update_Log_Version", comment: "版本") + " \(log.version)")
                                .font(.headline)
                            
                            Text(log.date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(String(format: NSLocalizedString("Update_Log_Changes_Count", comment: "%d 项更新"), log.changes.count))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Update_Log_History", comment: "更新历史"))
    }
}

// MARK: - 更新日志详情视图
struct UpdateLogDetailView: View {
    let updateLog: UpdateLog
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 版本信息
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("Update_Log_Version", comment: "版本") + " \(updateLog.version)")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(updateLog.date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // 更新内容
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(updateLog.changes.enumerated()), id: \.offset) { _, change in
                        HStack(alignment: .top, spacing: 12) {
                            if change.hasPrefix("**") && change.hasSuffix("**") {
                                Image(systemName: "folder.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .frame(width: 16, height: 16)
                            }
                            
                            Text(formatChangeText(change))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Spacer()
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle(NSLocalizedString("Update_Log_Details", comment: "更新详情"))
    }
    
    private func formatChangeText(_ change: String) -> String {
        if change.hasPrefix("**") && change.hasSuffix("**") {
            return String(change.dropFirst(2).dropLast(2))
        }
        return change
    }
} 
