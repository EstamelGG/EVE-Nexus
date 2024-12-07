import SwiftUI

enum LoadingState {
    case unzipping
    case unzippingComplete
    case loadingDB
    case loadingDBComplete
    case complete
}

struct LoadingView: View {
    @Binding var loadingState: LoadingState
    let progress: Double
    let onComplete: () -> Void
    
    @State private var showCheckmark = false
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // 背景圆圈
                Circle()
                    .stroke(lineWidth: 4)
                    .opacity(0.3)
                    .foregroundColor(.gray)
                    .frame(width: 80, height: 80)
                
                // 动态进度
                switch loadingState {
                case .unzipping:
                    // 实际解压进度
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .foregroundColor(.green)
                        .frame(width: 80, height: 80)
                        .rotationEffect(Angle(degrees: -90))  // 从顶部开始
                    
                    // 进度文本
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                
                case .unzippingComplete:
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .foregroundColor(.green)
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.green)
                        .opacity(showCheckmark ? 1 : 0)
                        .onAppear {
                            withAnimation(.easeIn(duration: 0.2)) {
                                showCheckmark = true
                            }
                        }
                
                case .loadingDB:
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .foregroundColor(.blue)
                        .frame(width: 80, height: 80)
                        .rotationEffect(Angle(degrees: rotationAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotationAngle = 360
                            }
                        }
                
                case .loadingDBComplete:
                    Circle()
                        .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .foregroundColor(.green)
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.green)
                        .opacity(showCheckmark ? 1 : 0)
                        .onAppear {
                            withAnimation(.easeIn(duration: 0.2)) {
                                showCheckmark = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                loadingState = .complete
                            }
                        }
                
                case .complete:
                    EmptyView()
                }
            }
            
            // 加载文本
            Text(loadingText)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .onChange(of: loadingState) { _, newState in
            if newState == .complete {
                onComplete()
            }
        }
    }
    
    private var loadingText: String {
        switch loadingState {
        case .unzipping:
            return "Unzipping Icons... \(Int(progress * 100))%"
        case .unzippingComplete:
            return "Icons Ready"
        case .loadingDB:
            return "Loading Database..."
        case .loadingDBComplete:
            return "Database Ready"
        case .complete:
            return ""
        }
    }
} 