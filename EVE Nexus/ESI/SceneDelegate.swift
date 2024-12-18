import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        Logger.info("SceneDelegate: 开始初始化场景")
        Logger.info("SceneDelegate: 检查 Info.plist URL Scheme 配置...")
        if let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]],
           let urlSchemes = urlTypes.first?["CFBundleURLSchemes"] as? [String] {
            Logger.info("SceneDelegate: 已配置的 URL Schemes: \(urlSchemes)")
        } else {
            Logger.error("SceneDelegate: 未找到 URL Scheme 配置")
        }
        
        // 检查是否有启动时的URL上下文
        if !connectionOptions.urlContexts.isEmpty {
            Logger.info("SceneDelegate: 启动时存在URL上下文: \(connectionOptions.urlContexts)")
            for urlContext in connectionOptions.urlContexts {
                Logger.info("SceneDelegate: 处理启动URL: \(urlContext.url.absoluteString)")
            }
        } else {
            Logger.info("SceneDelegate: 启动时没有URL上下文")
        }
        
        guard let windowScene = (scene as? UIWindowScene) else { 
            Logger.error("SceneDelegate: 无法获取windowScene")
            return 
        }
        
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
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        Logger.info("SceneDelegate: 收到 URL 上下文")
        Logger.info("SceneDelegate: URLContexts 数量: \(URLContexts.count)")
        
        for urlContext in URLContexts {
            Logger.info("SceneDelegate: 处理URL上下文: \(urlContext.url.absoluteString)")
            Logger.info("SceneDelegate: URL来源应用程序: \(urlContext.options.sourceApplication ?? "未知")")
            Logger.info("SceneDelegate: URL打开选项: \(urlContext.options)")
        }
        
        // 处理应用运行时收到的 URL
        guard let url = URLContexts.first?.url else {
            Logger.error("SceneDelegate: URL 上下文为空")
            return
        }
        
        Logger.info("SceneDelegate: 准备处理URL...")
        handleURL(url)
    }
    
    private func handleURL(_ url: URL) {
        Logger.info("SceneDelegate: 开始处理 URL")
        Logger.info("SceneDelegate: 收到 URL: \(url.absoluteString)")
        Logger.info("SceneDelegate: URL scheme: \(url.scheme ?? "nil")")
        Logger.info("SceneDelegate: URL host: \(url.host ?? "nil")")
        Logger.info("SceneDelegate: URL path: \(url.path)")
        Logger.info("SceneDelegate: URL query: \(url.query ?? "nil")")
        
        // 检查是否包含授权码
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            Logger.info("SceneDelegate: 检测到授权码: \(code.prefix(10))...")
        } else {
            Logger.error("SceneDelegate: URL 中没有找到授权码")
            return
        }
        
        // 确保是我们的认证回调
        guard let config = EVELogin.shared.config else {
            Logger.error("SceneDelegate: 无法获取配置信息")
            return
        }
        
        // 解析配置的回调URL
        guard let configCallbackURL = URL(string: config.callbackUrl) else {
            Logger.error("SceneDelegate: 无法解析配置的回调 URL")
            return
        }
        
        Logger.info("SceneDelegate: 配置的回调URL = \(configCallbackURL)")
        
        // 验证URL的scheme和host是否匹配
        guard url.scheme == configCallbackURL.scheme else {
            Logger.error("SceneDelegate: 收到未知的 URL scheme: \(url.scheme ?? "nil")，期望的 scheme: \(configCallbackURL.scheme ?? "nil")")
            return
        }
        
        // 将 URL 传递给 AppDelegate 处理
        Logger.info("SceneDelegate: 验证通过，准备将 URL 传递给 AppDelegate")
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            Logger.info("SceneDelegate: 成功获取 AppDelegate，开始处理 URL")
            let result = appDelegate.application(UIApplication.shared, open: url, options: [:])
            Logger.info("SceneDelegate: AppDelegate 处理结果: \(result)")
        } else {
            Logger.error("SceneDelegate: 无法获取 AppDelegate")
        }
    }
} 