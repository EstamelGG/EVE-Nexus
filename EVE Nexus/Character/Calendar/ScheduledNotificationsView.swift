import SwiftUI
import UserNotifications

struct ScheduledNotificationsView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) private var dismiss

    /// 按日期预分组的通知（在 loadNotifications 时计算，避免每次 body 重渲染都重新分组排序）
    @State private var groupedNotifications: [String: [UNNotificationRequest]] = [:]
    @State private var isLoading = true

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView(NSLocalizedString("Calendar_Loading", comment: "Loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if groupedNotifications.isEmpty {
                    NotificationEmptyStateView()
                } else {
                    // 通知列表
                    List {
                        ForEach(groupedNotifications.keys.sorted(), id: \.self) { dateKey in
                            Section(header: Text(formatSectionDate(dateKey))) {
                                ForEach(groupedNotifications[dateKey] ?? [], id: \.identifier) {
                                    notification in
                                    NotificationRow(
                                        notification: notification,
                                        category: .eveEvent
                                    ) {
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
            .navigationTitle(
                NSLocalizedString(
                    "Calendar_Scheduled_Notifications", comment: "Scheduled Notifications"
                )
            )
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

    /// 加载待发送的通知（仅 EVE 事件类别，按日期预分组排序）
    private func loadNotifications() async {
        isLoading = true

        let notifications = await notificationManager.getPendingNotifications(
            category: .eveEvent
        )
        let grouped = Self.groupByDate(notifications)

        await MainActor.run {
            groupedNotifications = grouped
            isLoading = false
        }
    }

    /// 取消通知
    private func cancelNotification(_ notification: UNNotificationRequest) {
        notificationManager.cancelNotification(notification)

        // 从分组中移除
        for (dateKey, list) in groupedNotifications {
            if list.contains(where: { $0.identifier == notification.identifier }) {
                var newList = list
                newList.removeAll { $0.identifier == notification.identifier }
                groupedNotifications[dateKey] = newList.isEmpty ? nil : newList
                break
            }
        }
    }

    /// 按触发日期分组并按时间升序排序
    private static func groupByDate(
        _ notifications: [UNNotificationRequest]
    ) -> [String: [UNNotificationRequest]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        var grouped: [String: [UNNotificationRequest]] = [:]

        for notification in notifications {
            if let trigger = notification.trigger as? UNCalendarNotificationTrigger,
               let triggerDate = trigger.nextTriggerDate()
            {
                let dateKey = formatter.string(from: triggerDate)
                if grouped[dateKey] == nil {
                    grouped[dateKey] = []
                }
                grouped[dateKey]?.append(notification)
            }
        }

        // 对每个日期组内的通知按时间排序
        for dateKey in grouped.keys {
            grouped[dateKey]?.sort { lhs, rhs in
                guard let l = lhs.trigger as? UNCalendarNotificationTrigger,
                      let r = rhs.trigger as? UNCalendarNotificationTrigger,
                      let ld = l.nextTriggerDate(),
                      let rd = r.nextTriggerDate()
                else {
                    return false
                }
                return ld < rd
            }
        }

        return grouped
    }

    /// 格式化日期段标题
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

#Preview {
    ScheduledNotificationsView()
}
