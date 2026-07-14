import Foundation
import Pulse
import PulseUI
import SwiftUI

struct LogsBrowserView: View {
    /// 使用 Logger 的 store 来显示日志
    private var loggerStore: LoggerStore {
        Logger.shared.loggerStore
    }

    var body: some View {
        // 使用 PulseUI 的 ConsoleView 来显示日志
        // 这会显示所有通过 Pulse 记录的日志，包括我们通过 Logger 记录的
        // ConsoleView 默认使用倒序排序（.descending），最新的日志在顶部
        ConsoleView(store: loggerStore, mode: .all)
            .navigationTitle(NSLocalizedString("Main_Setting_Logs_Browser_Title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
    }
}
