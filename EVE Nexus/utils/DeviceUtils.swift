import SwiftUI

// 布局模式枚举
enum LayoutMode: String, CaseIterable {
    case portrait
    case landscape
    case iPad
}

enum DeviceUtils {
    static var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    // 判断当前设备是否为 iPad
    static var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    // 判断当前设备是否为 iPhone
    static var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    // 判断当前界面是否处于横屏模式
    static var isLandscape: Bool {
        let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return windowScene?.interfaceOrientation.isLandscape ?? false
    }

    // 判断是否是 iPhone 的横屏模式
    static var isIPhoneLandscape: Bool {
        isIPhone && isLandscape
    }

    // MARK: - 布局模式相关

    // 获取当前布局模式
    static var currentLayoutMode: LayoutMode {
        if isIPad {
            return .iPad
        } else if isLandscape {
            return .landscape
        } else {
            return .portrait
        }
    }

    // 判断是否应该使用紧凑布局（横屏或iPad）
    static var shouldUseCompactLayout: Bool {
        isLandscape || isIPad
    }

    // 比较两个布局模式是否需要重新渲染视图
    static func shouldUpdateLayout(from oldMode: LayoutMode, to newMode: LayoutMode) -> Bool {
        return oldMode != newMode
    }
}
