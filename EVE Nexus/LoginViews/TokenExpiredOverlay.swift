import SwiftUI

/// Token过期提示覆盖层组件
/// 用于在角色头像上显示token过期的视觉提示
struct TokenExpiredOverlay: View {
    var body: some View {
        ZStack {
            // Token过期的灰色蒙版
            Circle()
                .fill(Color.black.opacity(0.4))
                .frame(width: 64, height: 64)

            ZStack {
                // 红色边框三角形
                Image(systemName: "triangle")
                    .font(.system(size: 32))
                    .foregroundColor(.red)

                // 红色感叹号
                Image(systemName: "exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
            }
        }
    }
}
