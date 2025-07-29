import Foundation
import UserNotifications

// 通知时间选项
enum NotificationTime: CaseIterable {
    case twoHours
    case oneHour
    case thirtyMinutes
    case fifteenMinutes
    case atEventTime
    
    var displayName: String {
        switch self {
        case .twoHours:
            return NSLocalizedString("Calendar_Notification_Two_Hours_Before", comment: "2 hours before")
        case .oneHour:
            return NSLocalizedString("Calendar_Notification_One_Hour_Before", comment: "1 hour before")
        case .thirtyMinutes:
            return NSLocalizedString("Calendar_Notification_Thirty_Minutes_Before", comment: "30 minutes before")
        case .fifteenMinutes:
            return NSLocalizedString("Calendar_Notification_Fifteen_Minutes_Before", comment: "15 minutes before")
        case .atEventTime:
            return NSLocalizedString("Calendar_Notification_At_Event_Time", comment: "At event time")
        }
    }
    
    var timeInterval: TimeInterval {
        switch self {
        case .twoHours:
            return -7200  // -2小时
        case .oneHour:
            return -3600  // -1小时
        case .thirtyMinutes:
            return -1800  // -30分钟
        case .fifteenMinutes:
            return -900   // -15分钟
        case .atEventTime:
            return 0      // 事件开始时
        }
    }
    
    var strategyDescription: String {
        switch self {
        case .twoHours:
            return NSLocalizedString("Calendar_Strategy_Two_Hours_Before", comment: "2 hours before")
        case .oneHour:
            return NSLocalizedString("Calendar_Strategy_One_Hour_Before", comment: "1 hour before")
        case .thirtyMinutes:
            return NSLocalizedString("Calendar_Strategy_Thirty_Minutes_Before", comment: "30 minutes before")
        case .fifteenMinutes:
            return NSLocalizedString("Calendar_Strategy_Fifteen_Minutes_Before", comment: "15 minutes before")
        case .atEventTime:
            return NSLocalizedString("Calendar_Strategy_At_Event_Time", comment: "At event time")
        }
    }
}

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private init() {
        updateAuthorizationStatus()
    }
    
    // 更新授权状态
    private func updateAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }
    
    // 请求通知权限
    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await MainActor.run {
                updateAuthorizationStatus()
            }
            return granted
        } catch {
            Logger.error("请求通知权限失败: \(error)")
            return false
        }
    }
    
    // 创建EVE事件通知（使用自定义时间）
    func scheduleEventNotificationWithCustomTime(
        eventId: Int,
        title: String,
        eventTime: Date,
        organizer: String,
        organizerType: String,
        duration: Int,
        description: String?,
        notificationTime: NotificationTime
    ) async -> Bool {
        let triggerDate = eventTime.addingTimeInterval(notificationTime.timeInterval)
        
        return await createNotification(
            eventId: eventId,
            title: title,
            eventTime: eventTime,
            organizer: organizer,
            organizerType: organizerType,
            duration: duration,
            description: description,
            triggerDate: triggerDate,
            strategy: notificationTime.strategyDescription
        )
    }
    
    // 通用的通知创建方法
    private func createNotification(
        eventId: Int,
        title: String,
        eventTime: Date,
        organizer: String,
        organizerType: String,
        duration: Int,
        description: String?,
        triggerDate: Date,
        strategy: String
    ) async -> Bool {
        // 检查权限
        guard authorizationStatus == .authorized else {
            let granted = await requestPermission()
            if !granted {
                Logger.error("用户拒绝了通知权限")
                return false
            }
            // 如果获得了权限，继续执行
            return await createNotification(
                eventId: eventId,
                title: title,
                eventTime: eventTime,
                organizer: organizer,
                organizerType: organizerType,
                duration: duration,
                description: description,
                triggerDate: triggerDate,
                strategy: strategy
            )
        }
        
        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Calendar_Reminder_Title_Prefix", comment: "EVE Event: ") + title
        content.sound = .default
        
        // 格式化事件时间
        let eventTimeString = formatEventDate(eventTime)
        let durationString = formatDuration(duration)
        
        // 设置通知正文
        let bodyText = """
        \(NSLocalizedString("Calendar_Reminder_Event_Time", comment: "Event Time: "))\(eventTimeString)
        \(NSLocalizedString("Calendar_Reminder_Organizer", comment: "Organizer: "))\(organizer) (\(organizerType))
        \(NSLocalizedString("Calendar_Reminder_Duration", comment: "Duration: "))\(durationString)
        """
        
        content.body = bodyText
        
        // 设置用户信息，用于后续处理
        content.userInfo = [
            "eventId": eventId,
            "eventTime": eventTime.timeIntervalSince1970,
            "type": "eveEvent"
        ]
        
        // 检查是否还需要设置通知
        guard triggerDate > Date() else {
            Logger.info("事件时间已过或过于接近，无法设置通知")
            return false
        }
        
        // 创建触发器
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        
        // 创建通知请求
        let identifier = "eve_event_\(eventId)_\(Int(eventTime.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            Logger.info("成功创建EVE事件通知 - 事件ID: \(eventId), 通知时间: \(triggerDate), 策略: \(strategy)")
            return true
        } catch {
            Logger.error("创建通知失败: \(error)")
            return false
        }
    }
    
    // 获取所有待发送的通知
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
    
    // 格式化事件时间
    private func formatEventDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
    
    // 格式化持续时间
    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) " + NSLocalizedString("Calendar_Minutes", comment: "minutes")
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) " + NSLocalizedString("Calendar_Hours", comment: "hours")
            } else {
                return "\(hours) " + NSLocalizedString("Calendar_Hours", comment: "hours") + 
                       " \(remainingMinutes) " + NSLocalizedString("Calendar_Minutes", comment: "minutes")
            }
        }
    }
} 
