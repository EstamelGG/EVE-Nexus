import SwiftUI

// 自定义军团图标视图，处理特殊军团ID的深色/浅色模式
struct CorporationIconView: View {
    let corporationId: Int
    let iconFileName: String
    let size: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(corporationId: Int, iconFileName: String, size: CGFloat = 32) {
        self.corporationId = corporationId
        self.iconFileName = iconFileName
        self.size = size
    }
    
    var body: some View {
        IconManager.shared.loadImage(for: iconFileName)
            .resizable()
            .frame(width: size, height: size)
            .cornerRadius(size == 64 ? 8 : 6)
            .modifier(CorporationIconModifier(corporationId: corporationId, colorScheme: colorScheme))
    }
}

// 军团图标修饰符，处理特殊军团ID的颜色反转
struct CorporationIconModifier: ViewModifier {
    let corporationId: Int
    let colorScheme: ColorScheme
    
    func body(content: Content) -> some View {
        if corporationId == 1000297 && colorScheme == .light {
            // 军团ID 1000297 在浅色模式下反色
            content
                .colorInvert()
        } else {
            // 其他情况保持原图
            content
        }
    }
} 