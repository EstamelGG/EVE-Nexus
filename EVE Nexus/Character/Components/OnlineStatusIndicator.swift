import SwiftUI

struct OnlineStatusIndicator: View {
    let isOnline: Bool
    let size: CGFloat
    let isLoading: Bool
    let statusUnknown: Bool
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(
                isLoading || statusUnknown
                    ? Color.yellow.opacity(0.7)
                    : (isOnline ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
            )
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            .shadow(
                color: isLoading || statusUnknown
                    ? Color.yellow.opacity(0.2)
                    : (isOnline ? Color.green.opacity(0.2) : Color.red.opacity(0.2)),
                radius: 2,
                x: 0,
                y: 1
            )
            .scaleEffect(isAnimating ? 0.8 : 1.0)
            .animation(
                isAnimating
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                value: isAnimating
            )
            .onAppear {
                if isLoading {
                    isAnimating = true
                }
            }
    }
}
