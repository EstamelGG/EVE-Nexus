import UIKit
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        Logger.info("AppDelegate: 应用程序启动")
        if let launchOptions = launchOptions {
            Logger.info("AppDelegate: 启动选项: \(launchOptions)")
        }
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        Logger.info("AppDelegate: 收到URL打开请求")
        Logger.info("AppDelegate: URL = \(url.absoluteString)")
        Logger.info("AppDelegate: URL components = \(URLComponents(url: url, resolvingAgainstBaseURL: true)?.description ?? "nil")")
        Logger.info("AppDelegate: Options = \(options)")
        
        // 检查是否是我们的回调 URL
        guard let config = EVELogin.shared.config else {
            Logger.error("AppDelegate: 无法获取配置信息")
            return false
        }
        
        // 解析配置的回调URL
        guard let configCallbackURL = URL(string: config.callbackUrl) else {
            Logger.error("AppDelegate: 无法解析配置的回调 URL")
            return false
        }
        
        Logger.info("AppDelegate: 配置的回调URL = \(configCallbackURL.absoluteString)")
        Logger.info("AppDelegate: 收到的URL scheme = \(url.scheme ?? "nil")")
        Logger.info("AppDelegate: 期望的URL scheme = \(configCallbackURL.scheme ?? "nil")")
        Logger.info("AppDelegate: 收到的URL host = \(url.host ?? "nil")")
        Logger.info("AppDelegate: 期望的URL host = \(configCallbackURL.host ?? "nil")")
        Logger.info("AppDelegate: 收到的URL path = \(url.path)")
        Logger.info("AppDelegate: 期望的URL path = \(configCallbackURL.path)")
        
        // 验证URL的scheme是否匹配
        guard url.scheme == configCallbackURL.scheme else {
            Logger.error("AppDelegate: 收到未知的 URL scheme: \(url.scheme ?? "nil")，期望的 scheme: \(configCallbackURL.scheme ?? "nil")")
            return false
        }
        
        Task {
            do {
                Logger.info("AppDelegate: 开始处理授权回调...")
                let token = try await EVELogin.shared.handleAuthCallback(url: url)
                Logger.info("AppDelegate: 获取到认证令牌: access_token=\(token.access_token.prefix(10))..., expires_in=\(token.expires_in), token_type=\(token.token_type)")
                
                Logger.info("AppDelegate: 开始获取角色信息...")
                let character = try await EVELogin.shared.getCharacterInfo(token: token.access_token)
                Logger.info("AppDelegate: 获取到角色信息: CharacterID=\(character.CharacterID), CharacterName=\(character.CharacterName)")
                
                // 保存认证信息
                Logger.info("AppDelegate: 开始保存认证信息...")
                EVELogin.shared.saveAuthInfo(token: token, character: character)
                Logger.info("AppDelegate: 认证信息保存完成")
                
                // 更新UI状态
                Logger.info("AppDelegate: 开始更新UI状态...")
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    Logger.info("AppDelegate: 成功获取到窗口场景")
                    if let window = windowScene.windows.first {
                        Logger.info("AppDelegate: 成功获取到窗口")
                        if let rootViewController = window.rootViewController {
                            Logger.info("AppDelegate: 成功获取到根视图控制器，类型: \(type(of: rootViewController))")
                            // 查找 AccountsView
                            if let presentedVC = rootViewController.presentedViewController as? UIHostingController<AccountsView> {
                                Logger.info("AppDelegate: 找到 AccountsView，准备更新...")
                                await MainActor.run {
                                    presentedVC.rootView.characterInfo = character
                                    presentedVC.rootView.isLoggedIn = true
                                    presentedVC.rootView.showingWebView = false
                                    Logger.info("AppDelegate: UI状态更新完成")
                                }
                            } else {
                                Logger.error("AppDelegate: 未找到 AccountsView 视图")
                                if let presentedVC = rootViewController.presentedViewController {
                                    Logger.error("AppDelegate: presentedViewController的实际类型: \(type(of: presentedVC))")
                                } else {
                                    Logger.error("AppDelegate: presentedViewController为nil")
                                }
                            }
                        } else {
                            Logger.error("AppDelegate: 未找到根视图控制器")
                        }
                    } else {
                        Logger.error("AppDelegate: 未找到窗口")
                    }
                } else {
                    Logger.error("AppDelegate: 未找到主窗口场景")
                }
            } catch {
                Logger.error("AppDelegate: 认证过程出错: \(error)")
                // 显示错误信息
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootViewController = window.rootViewController,
                   let presentedVC = rootViewController.presentedViewController as? UIHostingController<AccountsView> {
                    await MainActor.run {
                        presentedVC.rootView.errorMessage = error.localizedDescription
                        presentedVC.rootView.showingError = true
                        presentedVC.rootView.showingWebView = false
                        Logger.info("AppDelegate: 错误信息已显示")
                    }
                } else {
                    Logger.error("AppDelegate: 未找到 AccountsView 视图，无法显示错误")
                }
            }
        }
        return true
    }
} 