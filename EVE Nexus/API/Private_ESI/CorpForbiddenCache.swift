import Foundation

/// 军团接口 403 负缓存（统一组件）
///
/// ESI 的军团权限按角色 token + scope 授权，某角色对某军团某类接口无权限（403）时，
/// 短期内不会恢复，重复请求只会白白撞墙。此组件以 (scope, 军团ID, 角色ID) 为 key
/// 记录 403 时间戳，TTL 内直接抛错跳过，除非调用方强制刷新。
///
/// 仅内存存储：App 重启后重新探测一轮，成本可接受。
final class CorpForbiddenCache {
    static let shared = CorpForbiddenCache()

    /// 403 负缓存有效期（30分钟）
    private let ttl: TimeInterval = 1800

    /// key = "scope_军团ID_角色ID"
    private var cache: [String: Date] = [:]
    private let lock = NSLock()

    private init() {}

    /// 统一包装：命中负缓存则抛 403；operation 403 时记录；成功时清除记录
    ///
    /// - Parameters:
    ///   - scope: 接口维度（如 "corpIndustry"），同一角色的不同军团接口权限互相独立
    ///   - forceRefresh: 强制刷新时跳过负缓存检查（重新探测权限），结果照常更新缓存
    func perform<T>(
        scope: String,
        corporationId: Int,
        characterId: Int,
        forceRefresh: Bool = false,
        operation: () async throws -> T
    ) async throws -> T {
        let key = Self.key(scope: scope, corporationId: corporationId, characterId: characterId)

        if !forceRefresh, isForbidden(key) {
            Logger.info(
                "军团接口 403 负缓存命中，跳过请求 - scope: \(scope), 军团ID: \(corporationId), 角色ID: \(characterId)"
            )
            throw NetworkError.httpError(statusCode: 403, message: "Character does not have required role(s)")
        }

        do {
            let result = try await operation()
            // 请求成功说明权限已恢复，清除负缓存记录
            clear(key)
            return result
        } catch {
            if case let NetworkError.httpError(statusCode, _) = error, statusCode == 403 {
                mark(key)
            }
            throw error
        }
    }

    // MARK: - Private Methods

    private static func key(scope: String, corporationId: Int, characterId: Int) -> String {
        "\(scope)_\(corporationId)_\(characterId)"
    }

    private func isForbidden(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let triggeredAt = cache[key] else { return false }
        return Date().timeIntervalSince(triggeredAt) < ttl
    }

    private func mark(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache[key] = Date()
        Logger.info("军团接口 403 已记录负缓存（\(Int(ttl / 60))分钟内跳过）- key: \(key)")
    }

    private func clear(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        cache.removeValue(forKey: key)
    }
}
