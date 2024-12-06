import SwiftUI

struct DamageBarView: View {
    let percentage: Int
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景条
                Rectangle()
                    .fill(color.opacity(0.2))
                
                // 进度条
                Rectangle()
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(percentage) / 100)
                
                // 百分比文字
                Text("\(percentage)%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
            }
        }
        .frame(height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
} 