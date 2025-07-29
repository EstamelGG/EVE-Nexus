import SwiftUI
import UserNotifications

struct ScheduledNotificationsView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var pendingNotifications: [UNNotificationRequest] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView(NSLocalizedString("Calendar_Loading", comment: "Loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pendingNotifications.isEmpty {
                    // 空状态
                    VStack(spacing: 16) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text(NSLocalizedString("Calendar_No_Scheduled_Notifications", comment: "No Scheduled Notifications"))
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(NSLocalizedString("Calendar_No_Scheduled_Notifications_Description", comment: "You haven't scheduled any event notifications yet"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 通知列表
                    List {
                        ForEach(groupedNotifications.keys.sorted(), id: \.self) { dateKey in
                            Section(header: Text(formatSectionDate(dateKey))) {
                                ForEach(groupedNotifications[dateKey] ?? [], id: \.identifier) { notification in
                                    NotificationRow(notification: notification) {
                                        // 删除通知的回调
                                        cancelNotification(notification)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle(NSLocalizedString("Calendar_Scheduled_Notifications", comment: "Scheduled Notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Calendar_Refresh", comment: "Refresh")) {
                        Task {
                            await loadNotifications()
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("Common_Done", comment: "Done")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadNotifications()
        }
    }
    
    // 按日期分组通知
    private var groupedNotifications: [String: [UNNotificationRequest]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var grouped: [String: [UNNotificationRequest]] = [:]
        
        for notification in pendingNotifications {
            if let trigger = notification.trigger as? UNCalendarNotificationTrigger,
               let triggerDate = trigger.nextTriggerDate() {
                let dateKey = formatter.string(from: triggerDate)
                if grouped[dateKey] == nil {
                    grouped[dateKey] = []
                }
                grouped[dateKey]?.append(notification)
            }
        }
        
        // 对每个日期组内的通知按时间排序
        for dateKey in grouped.keys {
            grouped[dateKey]?.sort { notification1, notification2 in
                guard let trigger1 = notification1.trigger as? UNCalendarNotificationTrigger,
                      let trigger2 = notification2.trigger as? UNCalendarNotificationTrigger,
                      let date1 = trigger1.nextTriggerDate(),
                      let date2 = trigger2.nextTriggerDate() else {
                    return false
                }
                return date1 < date2
            }
        }
        
        return grouped
    }
    
    // 加载待发送的通知
    private func loadNotifications() async {
        isLoading = true
        
        let notifications = await notificationManager.getPendingNotifications()
        
        // 只显示EVE事件相关的通知
        let eveNotifications = notifications.filter { notification in
            if let type = notification.content.userInfo["type"] as? String {
                return type == "eveEvent"
            }
            return false
        }
        
        await MainActor.run {
            pendingNotifications = eveNotifications
            isLoading = false
        }
    }
    
    // 取消通知
    private func cancelNotification(_ notification: UNNotificationRequest) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notification.identifier])
        
        // 从列表中移除
        pendingNotifications.removeAll { $0.identifier == notification.identifier }
        
        Logger.info("已取消通知: \(notification.identifier)")
    }
    
    // 格式化日期段标题
    private func formatSectionDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .full
        outputFormatter.locale = Locale.current
        
        return outputFormatter.string(from: date)
    }
}

struct NotificationRow: View {
    let notification: UNNotificationRequest
    let onCancel: () -> Void
    
    private var eventTime: Date? {
        guard let eventTimeInterval = notification.content.userInfo["eventTime"] as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: eventTimeInterval)
    }
    
    private var triggerTime: Date? {
        guard let trigger = notification.trigger as? UNCalendarNotificationTrigger else {
            return nil
        }
        return trigger.nextTriggerDate()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 事件标题
            Text(notification.content.title)
                .font(.headline)
                .lineLimit(2)
            
            // 通知时间
            if let triggerTime = triggerTime {
                HStack {
                    Image(systemName: "bell")
                        .foregroundColor(.blue)
                        .font(.caption)
                    
                    Text(NSLocalizedString("Calendar_Notification_Time", comment: "Notification Time") + ": " + formatTime(triggerTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 事件时间
            if let eventTime = eventTime {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.green)
                        .font(.caption)
                    
                    Text(NSLocalizedString("Calendar_Reminder_Event_Time", comment: "Event Time") + formatTime(eventTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // 通知策略
            if let triggerTime = triggerTime, let eventTime = eventTime {
                let timeDifference = eventTime.timeIntervalSince(triggerTime)
                let strategy = getNotificationStrategy(timeDifference: timeDifference)
                
                HStack {
                    Image(systemName: "clock.badge")
                        .foregroundColor(.orange)
                        .font(.caption)
                    
                    Text(strategy)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            // 事件内容预览
            if !notification.content.body.isEmpty {
                Text(notification.content.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(NSLocalizedString("Calendar_Cancel_Notification", comment: "Cancel")) {
                onCancel()
            }
            .tint(.red)
        }
        .contextMenu {
            Button(NSLocalizedString("Calendar_Cancel_Notification", comment: "Cancel"), role: .destructive) {
                onCancel()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
    
    private func getNotificationStrategy(timeDifference: TimeInterval) -> String {
        let oneHour: TimeInterval = 3600
        let thirtyMinutes: TimeInterval = 1800
        
        if abs(timeDifference - oneHour) < 60 {
            return NSLocalizedString("Calendar_Strategy_One_Hour_Before", comment: "1 hour before")
        } else if abs(timeDifference - thirtyMinutes) < 60 {
            return NSLocalizedString("Calendar_Strategy_Thirty_Minutes_Before", comment: "30 minutes before")
        } else if abs(timeDifference) < 60 {
            return NSLocalizedString("Calendar_Strategy_At_Event_Time", comment: "At event time")
        } else {
            let minutes = Int(timeDifference / 60)
            return String(format: NSLocalizedString("Calendar_Strategy_Minutes_Before", comment: "%d minutes before"), minutes)
        }
    }
}

#Preview {
    ScheduledNotificationsView()
} 