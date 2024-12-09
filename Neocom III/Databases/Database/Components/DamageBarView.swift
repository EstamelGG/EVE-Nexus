import SwiftUI

struct DamageBarView: View {
    let percentage: Int
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景条 - 使用更深的相同色调
                Rectangle()
                    .fill(color.opacity(0.8))
                    .overlay(Color.black.opacity(0.5))
                    .frame(width: geometry.size.width)
                
                // 进度条 - 增加亮度和饱和度
                Rectangle()
                    .fill(color)
                    .saturation(1.2)     // 增加饱和度
                    .frame(width: geometry.size.width * CGFloat(percentage) / 100)
                
                // 百分比文字 - 使用额外的 ZStack 使文本居中
                ZStack {
                    Text("\(percentage)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                }
                .frame(width: geometry.size.width) // 让文本容器占满整个宽度
            }
        }
        .frame(height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                // .stroke(color, lineWidth: 1.5)
                .stroke(color, lineWidth: 0) // 边框粗细
                .saturation(1.2)     // 增加饱和度
        )
    }
} 
