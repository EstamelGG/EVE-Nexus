import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        Logger.info("SceneDelegate: 开始初始化场景")
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        // 创建数据库管理器
        let databaseManager = DatabaseManager()
        
        // 创建主视图
        let contentView = ContentView(databaseManager: databaseManager)
        
        // 创建窗口并设置根视图
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
        
        Logger.info("SceneDelegate: 场景初始化完成")
        
        // 处理启动时的 URL
        if let urlContext = connectionOptions.urlContexts.first {
            Logger.info("SceneDelegate: 处理启动时的 URL")
            handleURL(urlContext.url)
        }
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        Logger.info("SceneDelegate: 收到 URL 上下文")
        // 处理应用运行时收到的 URL
        guard let url = URLContexts.first?.url else {
            Logger.error("SceneDelegate: URL 上下文为空")
            return
        }
        handleURL(url)
    }
    
    private func handleURL(_ url: URL) {
        Logger.info("SceneDelegate: 收到 URL: \(url.absoluteString)")
        
        // 确保是我们的认证回调
        guard let config = EVELogin.shared.config else {
            Logger.error("SceneDelegate: 无法获取配置信息")
            return
        }
        
        guard url.scheme == config.callbackScheme else {
            Logger.error("SceneDelegate: 收到未知的 URL scheme: \(url.scheme ?? "nil")，期望的 scheme: \(config.callbackScheme)")
            return
        }
        
        guard url.host == config.callbackHost else {
            Logger.error("SceneDelegate: 收到未知的 URL host: \(url.host ?? "nil")，期望的 host: \(config.callbackHost)")
            return
        }
        
        // 将 URL 传递给 AppDelegate 处理
        Logger.info("SceneDelegate: 将 URL 传递给 AppDelegate")
        let appDelegate = UIApplication.shared.delegate as? AppDelegate
        _ = appDelegate?.application(UIApplication.shared, open: url, options: [:])
    }
} 