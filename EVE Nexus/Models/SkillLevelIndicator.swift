import SwiftUI

struct SkillLevelIndicator: View {
    let currentLevel: Int
    let trainingLevel: Int
    let isTraining: Bool
    
    // 动画状态
    @State private var isBlinking = false
    
    // 常量定义
    private let frameWidth: CGFloat = 55.5  // 37 * 1.5
    private let frameHeight: CGFloat = 9    // 6 * 1.5
    private let blockWidth: CGFloat = 9     // 6 * 1.5
    private let blockHeight: CGFloat = 6    // 4 * 1.5
    private let blockSpacing: CGFloat = 1.5 // 1 * 1.5
    
    // 颜色定义
    private let darkGray = Color.primary.opacity(0.8)
    private let lightGray = Color.secondary.opacity(0.6)
    private let borderColor = Color.primary.opacity(0.8)
    
    var body: some View {
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .center)) {
            // 外框 - 使用方形边框
            Rectangle()
                .stroke(borderColor, lineWidth: 0.5)
                .frame(width: frameWidth, height: frameHeight)
            
            // 使用固定偏移来放置方块组
            HStack(spacing: blockSpacing) {
                ForEach(0..<5) { index in
                    // 方块 - 使用方形
                    Rectangle()
                        .frame(width: blockWidth, height: blockHeight)
                        .foregroundColor(blockColor(for: index))
                        .opacity(blockOpacity(for: index))
                }
            }
            .offset(x: blockSpacing + 0.5) // 0.5是边框宽度，加上1.5像素间距
        }
        .onAppear {
            if isTraining {
                withAnimation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                ) {
                    isBlinking.toggle()
                }
            }
        }
    }
    
    // 确定方块颜色
    private func blockColor(for index: Int) -> Color {
        if index < currentLevel {
            return darkGray
        } else if index < trainingLevel {
            return lightGray
        }
        return .clear
    }
    
    // 确定方块透明度
    private func blockOpacity(for index: Int) -> Double {
        if isTraining && index == trainingLevel - 1 {
            return isBlinking ? 0.3 : 1.0
        }
        return 1.0
    }
}

#Preview {
    VStack(spacing: 20) {
        // 预览不同状态
        SkillLevelIndicator(currentLevel: 2, trainingLevel: 2, isTraining: false)
        SkillLevelIndicator(currentLevel: 2, trainingLevel: 3, isTraining: false)
        SkillLevelIndicator(currentLevel: 2, trainingLevel: 3, isTraining: true)
        SkillLevelIndicator(currentLevel: 3, trainingLevel: 4, isTraining: true)
        SkillLevelIndicator(currentLevel: 4, trainingLevel: 5, isTraining: true)
    }
    .padding()
} 
