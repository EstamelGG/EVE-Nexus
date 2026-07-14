import Foundation
import JWTDecode

class JWTTokenValidator {
    static let shared = JWTTokenValidator()

    private init() {}

    /// 解析JWT令牌并提取信息
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

            return EVECharacterInfo(
                CharacterID: characterIDInt,
                CharacterName: characterName,
                ExpiresOn: expiresOn,
                Scopes: scopesJoined,
                TokenType: "Bearer",
                CharacterOwnerHash: ownerHash
            )
        } catch {
            Logger.error("JWT令牌解析失败: \(error)")
            return nil
        }
    }

    /// 解析 JWT 过期时间；非 JWT 或缺 exp 时返回 nil
    func expirationDate(of token: String) -> Date? {
        do {
            let jwt = try JWTDecode.decode(jwt: token)
            return jwt.expiresAt
        } catch {
            return nil
        }
    }
}
