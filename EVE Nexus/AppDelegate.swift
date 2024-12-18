import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        Task {
            do {
                let token = try await EVELogin.shared.handleAuthCallback(url: url)
                Logger.info("获取到认证令牌: access_token=\(token.access_token), expires_in=\(token.expires_in), token_type=\(token.token_type)")
                
                let character = try await EVELogin.shared.getCharacterInfo(token: token.access_token)
                Logger.info("获取到角色信息: CharacterID=\(character.CharacterID), CharacterName=\(character.CharacterName), ExpiresOn=\(character.ExpiresOn)")
                
                // 保存认证信息
                EVELogin.shared.saveAuthInfo(token: token, character: character)
                
                // 更新UI状态
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let accountsView = windowScene.windows.first?.rootViewController?.presentedViewController as? UIHostingController<AccountsView> {
                    await MainActor.run {
                        accountsView.rootView.characterInfo = character
                        accountsView.rootView.isLoggedIn = true
                    }
                }
            } catch {
                Logger.error("认证错误: \(error)")
                // 显示错误信息
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let accountsView = windowScene.windows.first?.rootViewController?.presentedViewController as? UIHostingController<AccountsView> {
                    await MainActor.run {
                        accountsView.rootView.errorMessage = error.localizedDescription
                        accountsView.rootView.showingError = true
                    }
                }
            }
        }
        return true
    }
} 