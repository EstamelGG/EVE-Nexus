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

        // JWKS元数据端点（用于验证JWT token）
        static let jwksMetadataEndpoint = URL(
            string: "https://login.eveonline.com/.well-known/oauth-authorization-server")!

        // 基础URL
        static let baseURL = URL(string: "https://login.eveonline.com")!
    }
}
