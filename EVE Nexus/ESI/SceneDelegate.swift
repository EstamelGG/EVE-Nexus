import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    // 场景初始化
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        Logger.info("SceneDelegate: 开始初始化场景")
        
        guard let windowScene = (scene as? UIWindowScene) else { 
            Logger.error("SceneDelegate: 无法获取windowScene")
            return 
        }
        
        let databaseManager = DatabaseManager()
        let contentView = ContentView(databaseManager: databaseManager)
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
        
        Logger.info("SceneDelegate: 场景初始化完成")
    }
    
    // URL 处理
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        Logger.info("SceneDelegate: 收到URL上下文")
        
        guard let url = URLContexts.first?.url else {
            Logger.error("SceneDelegate: URL上下文为空")
            return
        }
        
        Logger.info("SceneDelegate: 准备处理URL: \(url.absoluteString)")
        
        Task {
            do {
                // 1. 处理授权回调，获取token
                let token = try await EVELogin.shared.handleAuthCallback(url: url)
                
                // 2. 获取角色信息
                let character = try await EVELogin.shared.getCharacterInfo(token: token.access_token)
                Logger.info("SceneDelegate: 获取到角色信息: CharacterID=\(character.CharacterID), CharacterName=\(character.CharacterName)")
                
                // 3. 保存认证信息
                EVELogin.shared.saveAuthInfo(token: token, character: character)
                
                // 4. 更新UI状态
                if let window = self.window,
                   let rootViewController = window.rootViewController,
                   let presentedVC = rootViewController.presentedViewController as? UIHostingController<AccountsView> {
                    await MainActor.run {
                        presentedVC.rootView.characterInfo = character
                        presentedVC.rootView.isLoggedIn = true
                        presentedVC.rootView.showingWebView = false
                    }
                }
                
            } catch {
                Logger.error("SceneDelegate: 认证过程出错: \(error)")
                if let window = self.window,
                   let rootViewController = window.rootViewController,
                   let presentedVC = rootViewController.presentedViewController as? UIHostingController<AccountsView> {
                    await MainActor.run {
                        presentedVC.rootView.errorMessage = error.localizedDescription
                        presentedVC.rootView.showingError = true
                        presentedVC.rootView.showingWebView = false
                    }
                }
            }
        }
    }
} 