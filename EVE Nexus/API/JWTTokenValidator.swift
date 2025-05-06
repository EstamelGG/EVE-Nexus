import Foundation
import JWTDecode

class JWTTokenValidator {
    static let shared = JWTTokenValidator()

    private init() {}

    // 解析JWT令牌并提取信息
    func parseToken(_ token: String) -> EVECharacterInfo? {
        do {
            let jwt = try JWTDecode.decode(jwt: token)

            // 从JWT中提取基本信息
            guard let characterID = jwt.claim(name: "sub").string,
                let characterName = jwt.claim(name: "name").string,
                let ownerHash = jwt.claim(name: "owner").string,
                let scopes = jwt.claim(name: "scp").array
            else {
                Logger.error("JWT令牌缺少必要的声明")
                return nil
            }

            // 将characterID格式为 "CHARACTER:EVE:12345678" 转换为整数ID
            let characterIDString = characterID.components(separatedBy: ":").last ?? ""
            guard let characterIDInt = Int(characterIDString) else {
                Logger.error("无法解析角色ID: \(characterID)")
                return nil
            }

            // 构建EVECharacterInfo对象
            let expiresOn = jwt.expiresAt?.timeIntervalSince1970.description ?? ""
            let scopesJoined = scopes.joined(separator: " ")

            let characterInfo = EVECharacterInfo(
                CharacterID: characterIDInt,
                CharacterName: characterName,
                ExpiresOn: expiresOn,
                Scopes: scopesJoined,
                TokenType: "Bearer",
                CharacterOwnerHash: ownerHash
            )

            return characterInfo
        } catch {
            Logger.error("JWT令牌解析失败: \(error)")
            return nil
        }
    }

    // 验证令牌是否有效（检查过期时间）
    func isTokenValid(_ token: String) -> Bool {
        do {
            let jwt = try JWTDecode.decode(jwt: token)

            // 检查令牌是否已过期
            if let expiresAt = jwt.expiresAt, expiresAt > Date() {
                return true
            } else {
                Logger.error("JWT令牌已过期")
                return false
            }
        } catch {
            Logger.error("JWT令牌验证失败: \(error)")
            return false
        }
    }
}
