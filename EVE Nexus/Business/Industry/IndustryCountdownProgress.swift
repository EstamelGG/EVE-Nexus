import SwiftUI

struct IndustryCountdownView: View {
    let endDate: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            Text(getDisplayText(at: context.date))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func getDisplayText(at currentDate: Date) -> String {
        let remainingTime = endDate.timeIntervalSince(currentDate)

        if remainingTime <= 0 {
            return NSLocalizedString("Industry_Status_completed", comment: "")
        }

        let totalSeconds = Int(remainingTime)
        let days = totalSeconds / (24 * 3600)
        let hours = (totalSeconds % (24 * 3600)) / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if days > 0 {
            if hours > 0 {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Days_Hours", comment: ""),
                    days, hours
                )
            } else {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Days", comment: ""),
                    days
                )
            }
        } else if hours > 0 {
            if minutes > 0 {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Hours_Minutes", comment: ""),
                    hours, minutes
                )
            } else {
                return String(
                    format: NSLocalizedString("Industry_Remaining_Hours", comment: ""),
                    hours
                )
            }
        } else if minutes > 0 {
            return String(
                format: NSLocalizedString("Industry_Remaining_Minutes_Seconds", comment: "%d分%d秒"),
                minutes, seconds
            )
        } else {
            return String(
                format: NSLocalizedString("Industry_Remaining_Seconds", comment: "%d秒"),
                seconds
            )
        }
    }
}

/// 工业项目实时进度条组件
struct IndustryProgressView: View {
    let job: IndustryJob

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            PulsingProgressBar(
                progress: getProgress(at: context.date),
                color: getProgressColor(at: context.date),
                height: 4,
                cornerRadius: 2
            )
        }
    }

    private func getProgress(at currentDate: Date) -> Double {
        // 先检查是否已完成（根据状态或时间）
        if job.status == "delivered" || job.status == "ready" || currentDate >= job.end_date {
            return 1.0
        }

        switch job.status {
        case "cancelled", "revoked", "failed": // 已取消或失败
            return 1.0
        default: // 进行中
            let totalDuration = Double(job.duration)
            let elapsedTime = currentDate.timeIntervalSince(job.start_date)
            let progress = elapsedTime / totalDuration
            return min(max(progress, 0), 1)
        }
    }

    private func getProgressColor(at _: Date) -> Color {
        // 先检查特殊状态
        switch job.status {
        case "cancelled", "revoked", "failed": // 已取消或失败
            return .red
        case "delivered", "ready": // 已完成
            return .green
        case "active", "paused": // 进行中或暂停
            // 根据活动类型返回不同颜色
            switch job.activity_id {
            case 1: // 制造
                return Color(red: 204 / 255, green: 153 / 255, blue: 0 / 255)
            case 3, 4: // 时间效率研究、材料效率研究
                return Color.blue
            case 5: // 复制
                return Color.blue
            case 8: // 发明
                return Color.blue
            case 9: // 反应
                return Color.cyan
            default:
                return Color.gray
            }
        default:
            return Color.gray
        }
    }
}
