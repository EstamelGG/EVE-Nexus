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
                let character = try await EVELogin.shared.getCharacterInfo(token: token.access_token)
                
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
                print("Authentication error: \(error)")
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