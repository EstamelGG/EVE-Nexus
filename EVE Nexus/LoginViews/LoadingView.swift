import SwiftUI

enum LoadingState {
    case processing
    case complete
}

struct LoadingView: View {
    @Binding var loadingState: LoadingState
    let progress: Double
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // 背景圆圈
                Circle()
                    .stroke(lineWidth: 4)
                    .opacity(0.3)
                    .foregroundColor(.gray)
                    .frame(width: 80, height: 80)

                // 进度圈
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .foregroundColor(.green)
                    .frame(width: 80, height: 80)
                    .rotationEffect(Angle(degrees: -90))

                // 进度文本
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.green)
            }

            // 加载文本
            Text("Unzipping Icons...")
                .font(.headline)
        }
        .onChange(of: loadingState) { _, newState in
            if newState == .complete {
                onComplete()
            }
        }
    }
}
