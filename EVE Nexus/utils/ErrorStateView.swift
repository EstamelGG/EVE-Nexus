import SwiftUI

/// 通用错误状态视图（军团/业务页面统一标准）
/// 结构：橙色警告图标 + Common_Error 标题 + 错误描述 + 重试按钮（accentColor 胶囊）
struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(NSLocalizedString("Common_Error", comment: ""))
                .font(.headline)
                .foregroundColor(.primary)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text(NSLocalizedString("ESI_Status_Retry", comment: ""))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.top, 8)
        }
        .padding()
    }
}

/// List 内使用的错误状态 Section（居中布局，保留 insetGrouped 卡片背景）
struct ErrorStateSection: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Section {
            HStack {
                Spacer()
                ErrorStateView(message: message, retry: retry)
                Spacer()
            }
        }
    }
}
