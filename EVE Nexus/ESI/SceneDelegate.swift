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
                
                // 检查钱包余额
                checkWalletBalance()
                
            case .failure(let error):
                presentedVC.rootView.errorMessage = error.localizedDescription
                presentedVC.rootView.showingError = true
                presentedVC.rootView.showingWebView = false
            }
        }
    }
    
    // 在 SceneDelegate 类中添加新方法
    private func checkWalletBalance() {
        Task {
            do {
                // 获取当前角色信息
                guard let character = EVELogin.shared.loadAuthInfo().character else {
                    Logger.error("SceneDelegate: 无法获取角色信息")
                    return
                }
                
                // 检查是否需要获取新的钱包权限token
                // TODO: 这里需要实现获取新token的UI交互流程
                
                // 获取钱包余额
                let balance = try await EVELogin.shared.getWalletBalance(characterId: character.CharacterID)
                let formattedBalance = String(format: "%.2f", balance)
                Logger.info("SceneDelegate: 角色 \(character.CharacterName) 的钱包余额: \(formattedBalance) ISK")
                
            } catch {
                Logger.error("SceneDelegate: 获取钱包余额失败: \(error)")
            }
        }
    }
} 