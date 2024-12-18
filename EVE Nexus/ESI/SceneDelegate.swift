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
    }
    
    // URL 处理
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else {
            Logger.error("SceneDelegate: URL上下文为空")
            return
        }
        
        EVELogin.shared.handleAuthenticationCallback(url: url) { [weak self] result in
            guard let self = self,
                  let window = self.window,
                  let rootViewController = window.rootViewController,
                  let presentedVC = rootViewController.presentedViewController as? UIHostingController<AccountsView> else {
                return
            }
            
            switch result {
            case .success(let character):
                presentedVC.rootView.characterInfo = character
                presentedVC.rootView.isLoggedIn = true
                presentedVC.rootView.showingWebView = false
                
            case .failure(let error):
                presentedVC.rootView.errorMessage = error.localizedDescription
                presentedVC.rootView.showingError = true
                presentedVC.rootView.showingWebView = false
            }
        }
    }
} 