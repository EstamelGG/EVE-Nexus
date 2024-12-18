import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        Logger.info("收到授权回调 URL: \(url.absoluteString)")
        
        Task {
            do {
                Logger.info("开始处理授权回调...")
                let token = try await EVELogin.shared.handleAuthCallback(url: url)
                Logger.info("获取到认证令牌: access_token=\(token.access_token.prefix(10))..., expires_in=\(token.expires_in), token_type=\(token.token_type)")
                
                Logger.info("开始获取角色信息...")
                let character = try await EVELogin.shared.getCharacterInfo(token: token.access_token)
                Logger.info("获取到角色信息: CharacterID=\(character.CharacterID), CharacterName=\(character.CharacterName), ExpiresOn=\(character.ExpiresOn)")
                
                // 保存认证信息
                Logger.info("开始保存认证信息...")
                EVELogin.shared.saveAuthInfo(token: token, character: character)
                Logger.info("认证信息保存完成")
                
                // 更新UI状态
                Logger.info("开始更新UI状态...")
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let accountsView = windowScene.windows.first?.rootViewController?.presentedViewController as? UIHostingController<AccountsView> {
                    Logger.info("找到 AccountsView，准备更新...")
                    await MainActor.run {
                        accountsView.rootView.characterInfo = character
                        accountsView.rootView.isLoggedIn = true
                        Logger.info("UI状态更新完成")
                    }
                } else {
                    Logger.error("未找到 AccountsView 视图")
                }
            } catch {
                Logger.error("认证过程出错: \(error)")
                // 显示错误信息
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let accountsView = windowScene.windows.first?.rootViewController?.presentedViewController as? UIHostingController<AccountsView> {
                    await MainActor.run {
                        accountsView.rootView.errorMessage = error.localizedDescription
                        accountsView.rootView.showingError = true
                    }
                } else {
                    Logger.error("未找到 AccountsView 视图，无法显示错误")
                }
            }
        }
        return true
    }
} 