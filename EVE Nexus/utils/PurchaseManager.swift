import Foundation
import StoreKit

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    @Published var purchasedRanks: Set<Int> = []
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var purchasingBadge: String? = nil // 正在购买的角标

    /// 产品ID定义 - 只保留一个赞助产品ID，购买后解锁 Factions/Deadspace/Officers
    private let sponsorProductID = "com.evenexus.badge.rank_officer"

    /// 免费角标的rank列表（T1, T2, T3）
    private let freeRanks: Set<Int> = [1, 2, 3]

    /// 赞助后解锁的rank列表（Factions, Deadspace, Officers）
    private let sponsorUnlockedRanks: Set<Int> = [4, 5, 6]

    /// 角标到rank的映射
    let badgeToRank: [String: Int] = [
        "T1": 1,
        "T2": 2,
        "T3": 3,
        "Factions": 4,
        "Deadspace": 5,
        "Officers": 6,
    ]

    private let purchasedRanksKey = "purchasedBadgeRanks"

    private init() {
        loadPurchasedRanks()
        // T1, T2, T3 默认免费解锁
        purchasedRanks.insert(1)
        purchasedRanks.insert(2)
        purchasedRanks.insert(3)

        // 在后台检查已购买的产品
        Task {
            await checkPurchasedProducts()
        }

        // 监听交易更新
        Task {
            await listenForTransactions()
        }
    }

    /// 检查已购买的产品
    private func checkPurchasedProducts() async {
        // 保存旧的购买记录用于对比
        let oldPurchasedRanks = purchasedRanks

        // 创建新的集合，包含免费角标
        var validRanks: Set<Int> = freeRanks

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                // 如果检测到赞助产品，解锁所有付费角标
                if transaction.productID == sponsorProductID {
                    validRanks.formUnion(sponsorUnlockedRanks)
                    Logger.info("[+] 检测到赞助购买，解锁所有付费角标")
                }
            } catch {
                Logger.error("[x] 验证交易失败: \(error)")
            }
        }

        // 检查是否有被移除的购买（退款）
        let removedRanks = oldPurchasedRanks.subtracting(validRanks).subtracting(freeRanks)
        if !removedRanks.isEmpty {
            Logger.info("[!] 检测到退款项目: \(removedRanks)")
        }

        // 用有效的购买列表替换旧的缓存
        purchasedRanks = validRanks
        savePurchasedRanks()
    }

    /// 监听交易更新
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            do {
                let transaction = try checkVerified(result)

                // 如果检测到赞助产品
                if transaction.productID == sponsorProductID {
                    // 检查是否为退款
                    if let revocationDate = transaction.revocationDate {
                        // 退款：移除所有付费角标
                        purchasedRanks.subtract(sponsorUnlockedRanks)
                        savePurchasedRanks()

                        let reason = transaction.revocationReason?.rawValue ?? 0
                        Logger.info("[!] 检测到退款，移除所有付费角标，退款时间: \(revocationDate), 原因: \(reason)")
                    } else {
                        // 正常购买：解锁所有付费角标
                        purchasedRanks.formUnion(sponsorUnlockedRanks)
                        savePurchasedRanks()
                        Logger.info("[+] 检测到新的赞助交易，解锁所有付费角标")
                    }
                }

                await transaction.finish()
            } catch {
                Logger.error("[x] 验证交易更新失败: \(error)")
            }
        }
    }

    /// 加载已购买的rank
    private func loadPurchasedRanks() {
        if let data = UserDefaults.standard.data(forKey: purchasedRanksKey),
           let ranks = try? JSONDecoder().decode(Set<Int>.self, from: data)
        {
            purchasedRanks = ranks
        }
        // 确保免费角标始终解锁
        purchasedRanks.formUnion(freeRanks)
    }

    /// 保存已购买的rank
    private func savePurchasedRanks() {
        if let data = try? JSONEncoder().encode(purchasedRanks) {
            UserDefaults.standard.set(data, forKey: purchasedRanksKey)
        }
    }

    /// 检查角标是否已解锁
    func isBadgeUnlocked(_ badge: String) -> Bool {
        guard let rank = badgeToRank[badge] else { return false }
        // T1, T2, T3 始终免费
        if freeRanks.contains(rank) {
            return true
        }
        // 其他角标需要检查是否已购买
        return purchasedRanks.contains(rank)
    }

    /// 获取角标对应的产品ID（只有付费角标需要产品ID）
    func getProductID(for badge: String) -> String? {
        guard let rank = badgeToRank[badge] else { return nil }
        // 免费角标不需要产品ID
        if freeRanks.contains(rank) {
            return nil
        }
        // 所有付费角标使用同一个赞助产品ID
        return sponsorProductID
    }

    /// 加载产品信息
    func loadProducts() async {
        isLoading = true
        errorMessage = nil

        do {
            products = try await Product.products(for: [sponsorProductID])
            Logger.info("[+] 成功加载 \(products.count) 个内购产品")
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("[x] 加载内购产品失败: \(error)")
        }

        isLoading = false
    }

    /// 购买产品（赞助）
    func purchase(_ product: Product, for badge: String) async -> Bool {
        isLoading = true
        purchasingBadge = badge
        errorMessage = nil

        do {
            let result = try await product.purchase()

            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()

                // 如果购买的是赞助产品，解锁所有付费角标
                if product.id == sponsorProductID {
                    purchasedRanks.formUnion(sponsorUnlockedRanks)
                    savePurchasedRanks()
                    Logger.info("[+] 成功赞助，解锁所有付费角标: \(sponsorUnlockedRanks)")
                }

                isLoading = false
                purchasingBadge = nil
                return true

            case .userCancelled:
                Logger.info("[-] 用户取消赞助")
                isLoading = false
                purchasingBadge = nil
                return false

            case .pending:
                Logger.info("[!] 赞助待处理")
                isLoading = false
                purchasingBadge = nil
                return false

            @unknown default:
                Logger.info("[-] 未知购买状态")
                isLoading = false
                purchasingBadge = nil
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("[x] 赞助失败: \(error)")
            isLoading = false
            purchasingBadge = nil
            return false
        }
    }

    /// 恢复购买
    func restorePurchases() async {
        isLoading = true
        errorMessage = nil

        do {
            try await AppStore.sync()

            // 保存旧的购买记录用于对比
            let oldPurchasedRanks = purchasedRanks

            // 创建新的集合，包含免费角标
            var validRanks: Set<Int> = freeRanks

            // 检查所有交易
            for await result in Transaction.currentEntitlements {
                do {
                    let transaction = try checkVerified(result)

                    // 如果检测到赞助产品，解锁所有付费角标
                    if transaction.productID == sponsorProductID {
                        validRanks.formUnion(sponsorUnlockedRanks)
                        Logger.info("[+] 恢复赞助，解锁所有付费角标")
                    }
                } catch {
                    Logger.error("[x] 验证交易失败: \(error)")
                }
            }

            // 检查是否有被移除的购买（退款）
            let removedRanks = oldPurchasedRanks.subtracting(validRanks).subtracting(freeRanks)
            if !removedRanks.isEmpty {
                Logger.info("[!] 恢复购买时检测到退款项目: \(removedRanks)")
            }

            // 用有效的购买列表替换旧的缓存
            purchasedRanks = validRanks
            savePurchasedRanks()
            Logger.info("[+] 恢复购买完成")
        } catch {
            errorMessage = error.localizedDescription
            Logger.error("[x] 恢复购买失败: \(error)")
        }

        isLoading = false
    }

    /// 验证交易
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw PurchaseError.unverifiedTransaction
        case let .verified(safe):
            return safe
        }
    }

    /// 获取产品价格字符串
    func getPriceString(for badge: String) -> String? {
        guard let rank = badgeToRank[badge] else {
            return nil
        }

        // T1, T2, T3 是免费的
        if freeRanks.contains(rank) {
            return NSLocalizedString("Purchase_Price_Free", comment: "")
        }

        // 如果正在加载且产品列表为空，返回占位符
        if isLoading, products.isEmpty {
            return NSLocalizedString("Purchase_Price_Loading", comment: "")
        }

        // 付费角标使用赞助产品的价格
        // 如果产品列表为空（但不在加载中），返回占位符
        if products.isEmpty {
            return NSLocalizedString("Purchase_Price_Loading", comment: "")
        }

        // 查找赞助产品
        if let product = products.first(where: { $0.id == sponsorProductID }) {
            return product.displayPrice
        }

        // 如果找不到产品，返回占位符（可能还在加载）
        return NSLocalizedString("Purchase_Price_Loading", comment: "")
    }
}

enum PurchaseError: Error {
    case unverifiedTransaction
}
