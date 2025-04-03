import Foundation

enum EVEConfig {
    // OAuth 认证相关配置
    enum OAuth {
        static let clientId = "7339147833b44ad3815c7ef0957950c2"
        static let clientSecret = "cgEH3hswersReqCFUyzRmsvb7C7wBAPYVq2IM2Of"
        static let redirectURI = URL(string: "eveauthpanel://callback/")!

        // API 端点
        static let authorizationEndpoint = URL(
            string: "https://login.eveonline.com/v2/oauth/authorize/")!
        static let tokenEndpoint = URL(string: "https://login.eveonline.com/v2/oauth/token")!
        static let verifyEndpoint = URL(string: "https://login.eveonline.com/oauth/verify")!

        // 基础URL
        static let baseURL = URL(string: "https://login.eveonline.com")!
    }
}
