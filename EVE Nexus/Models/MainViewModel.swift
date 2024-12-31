import SwiftUI
import Foundation

// 定义 CharacterSkills 结构体
struct CharacterSkills {
    let total_sp: Int
    let unallocated_sp: Int
}

// 定义 QueuedSkill 结构体
struct QueuedSkill {
    let skill_id: Int
    let skillLevel: Int
    let remainingTime: TimeInterval?
    let progress: Double
    let isCurrentlyTraining: Bool
}

// 定义 CharacterStats 结构体
struct CharacterStats {
    var skillPoints: String = "--"
    var queueStatus: String = "--"
    var walletBalance: String = "--"
    var location: String = "--"
    
    static func empty() -> CharacterStats {
        CharacterStats()
    }
}

@MainActor
class MainViewModel: ObservableObject {
    // MARK: - Constants
    private enum Constants {
        static let cloneCooldownPeriod: TimeInterval = 24 * 3600 // 24小时冷却
        static let emptyValue = "--"
        static let secondsInDay = 86400
        static let secondsInHour = 3600
        static let secondsInMinute = 60
        static let maxRetryCount = 3
        static let retryDelay: TimeInterval = 1.0
    }
    
    // MARK: - Loading State
    enum LoadingState: String {
        case idle
        case loadingPortrait
        case loadingSkills
        case loadingWallet
        case loadingQueue
        case loadingServerStatus
        case loadingCloneStatus
        
        var isLoading: Bool {
            self != .idle
        }
    }
    
    // MARK: - Error Handling
    enum RefreshError: Error {
        case skillInfoFailed
        case walletFailed
        case locationFailed
        case cloneFailed
        case serverStatusFailed
        case portraitFailed
        
        var localizedDescription: String {
            switch self {
            case .skillInfoFailed:
                return NSLocalizedString("Error_Skill_Info_Failed", comment: "")
            case .walletFailed:
                return NSLocalizedString("Error_Wallet_Failed", comment: "")
            case .locationFailed:
                return NSLocalizedString("Error_Location_Failed", comment: "")
            case .cloneFailed:
                return NSLocalizedString("Error_Clone_Failed", comment: "")
            case .serverStatusFailed:
                return NSLocalizedString("Error_Server_Status_Failed", comment: "")
            case .portraitFailed:
                return NSLocalizedString("Error_Portrait_Failed", comment: "")
            }
        }
    }
    
    // MARK: - Published Properties
    @Published var characterStats = CharacterStats()
    @Published var serverStatus: ServerStatus?
    @Published var selectedCharacter: EVECharacterInfo?
    @Published var characterPortrait: UIImage?
    @Published var cloneJumpStatus: String = NSLocalizedString("Main_Jump_Clones_Available", comment: "")
    @Published var isRefreshing = false
    @Published var loadingState: LoadingState = .idle
    @Published var lastError: RefreshError?
    
    // MARK: - Private Properties
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    
    // MARK: - Cache Management
    private struct Cache {
        var skills: CharacterSkills?
        var walletBalance: Double?
        var skillQueue: [QueuedSkill]?
        
        mutating func clear() {
            skills = nil
            walletBalance = nil
            skillQueue = nil
        }
    }
    
    private var cache = Cache()
    
    // MARK: - Initialization
    init() {
        loadSavedCharacter()
    }
    
    // MARK: - Private Methods
    private func updateCloneStatus(from cloneInfo: CharacterCloneInfo) {
        if let lastJumpDate = cloneInfo.last_clone_jump_date {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime]
            
            if let jumpDate = dateFormatter.date(from: lastJumpDate) {
                let now = Date()
                let timeSinceLastJump = now.timeIntervalSince(jumpDate)
                
                if timeSinceLastJump >= Constants.cloneCooldownPeriod {
                    cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
                } else {
                    let remainingHours = Int(ceil((Constants.cloneCooldownPeriod - timeSinceLastJump) / 3600))
                    cloneJumpStatus = String(format: NSLocalizedString("Main_Jump_Clones_Cooldown", comment: ""), remainingHours)
                }
            }
        } else {
            cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
        }
    }
    
    private func updateSkillPoints(_ totalSP: Int?) {
        if let sp = totalSP {
            characterStats.skillPoints = NSLocalizedString("Main_Skills_Ponits", comment: "")
                .replacingOccurrences(of: "$num", with: FormatUtil.format(Double(sp)))
        } else {
            characterStats.skillPoints = NSLocalizedString("Main_Skills_Ponits", comment: "")
                .replacingOccurrences(of: "$num", with: Constants.emptyValue)
        }
    }
    
    private func formatTimeComponents(seconds: Int) -> (days: Int, hours: Int, minutes: Int) {
        let days = seconds / Constants.secondsInDay
        let hours = (seconds % Constants.secondsInDay) / Constants.secondsInHour
        let minutes = (seconds % Constants.secondsInHour) / Constants.secondsInMinute
        return (days, hours, minutes)
    }
    
    private func updateQueueStatus(length: Int?, finishTime: TimeInterval?) {
        if let qLength = length {
            if let time = finishTime {
                let components = formatTimeComponents(seconds: Int(time))
                characterStats.queueStatus = NSLocalizedString("Main_Skills_Queue_Training", comment: "")
                    .replacingOccurrences(of: "$num", with: "\(qLength)")
                    .replacingOccurrences(of: "$day", with: "\(components.days)")
                    .replacingOccurrences(of: "$hour", with: "\(components.hours)")
                    .replacingOccurrences(of: "$minutes", with: "\(components.minutes)")
            } else {
                characterStats.queueStatus = NSLocalizedString("Main_Skills_Queue_Paused", comment: "")
                    .replacingOccurrences(of: "$num", with: "\(qLength)")
            }
        } else {
            characterStats.queueStatus = NSLocalizedString("Main_Skills_Queue_Empty", comment: "")
                .replacingOccurrences(of: "$num", with: "0")
        }
    }
    
    private func updateWalletBalance(_ balance: Double?) {
        if let bal = balance {
            characterStats.walletBalance = NSLocalizedString("Main_Wealth_ISK", comment: "")
                .replacingOccurrences(of: "$num", with: FormatUtil.format(bal))
        } else {
            characterStats.walletBalance = NSLocalizedString("Main_Wealth_ISK", comment: "")
                .replacingOccurrences(of: "$num", with: Constants.emptyValue)
        }
    }
    
    private func processSkillInfo(skillsResponse: CharacterSkillsResponse, queue: [SkillQueueItem]) {
        self.cache.skills = CharacterSkills(
            total_sp: skillsResponse.total_sp,
            unallocated_sp: skillsResponse.unallocated_sp
        )
        self.updateSkillPoints(skillsResponse.total_sp)
        
        self.cache.skillQueue = queue.map { skill in
            QueuedSkill(
                skill_id: skill.skill_id,
                skillLevel: skill.finished_level,
                remainingTime: skill.remainingTime,
                progress: skill.progress,
                isCurrentlyTraining: skill.isCurrentlyTraining
            )
        }
        self.updateQueueStatus(
            length: queue.count,
            finishTime: queue.last?.remainingTime
        )
    }
    
    private func retryOperation<T>(
        named operationName: String,
        maxRetries: Int = Constants.maxRetryCount,
        operation: () async throws -> T
    ) async throws -> T {
        var retryCount = 0
        var lastError: Error?
        
        while retryCount < maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                retryCount += 1
                if retryCount < maxRetries {
                    Logger.warning("操作失败: \(operationName) (尝试 \(retryCount)/\(maxRetries)) - 错误: \(error)")
                    try await Task.sleep(nanoseconds: UInt64(Constants.retryDelay * 1_000_000_000))
                }
            }
        }
        
        Logger.error("操作最终失败: \(operationName) - 错误: \(lastError?.localizedDescription ?? "未知错误")")
        throw lastError ?? RefreshError.serverStatusFailed
    }
    
    // MARK: - Public Methods
    func refreshAllData(forceRefresh: Bool = false) async {
        isRefreshing = true
        lastError = nil
        let service = CharacterDataService.shared
        
        // 创建一个独立的任务来处理服务器状态
        Task {
            do {
                self.serverStatus = try await service.getServerStatus(forceRefresh: forceRefresh)
            } catch {
                lastError = .serverStatusFailed
                Logger.error("获取服务器状态失败: \(error)")
            }
        }
        
        // 如果有选中的角色，立即开始加载角色数据
        if let character = selectedCharacter {
            do {
                // 并发执行所有请求
                async let skillInfoTask = retryOperation(named: "获取技能信息") {
                    try await service.getSkillInfo(id: character.CharacterID, forceRefresh: forceRefresh)
                }
                async let walletTask = retryOperation(named: "获取钱包余额") {
                    try await service.getWalletBalance(id: character.CharacterID, forceRefresh: forceRefresh)
                }
                async let locationTask = retryOperation(named: "获取位置信息") {
                    try await service.getLocation(id: character.CharacterID, forceRefresh: forceRefresh)
                }
                async let cloneTask = retryOperation(named: "获取克隆状态") {
                    try await service.getCloneStatus(id: character.CharacterID, forceRefresh: forceRefresh)
                }
                
                // 等待所有角色数据请求完成
                let ((skillsResponse, queue), balance, location, cloneInfo) = try await (
                    skillInfoTask,
                    walletTask,
                    locationTask,
                    cloneTask
                )
                
                // 处理技能信息
                processSkillInfo(skillsResponse: skillsResponse, queue: queue)
                
                // 处理钱包余额
                self.cache.walletBalance = balance
                self.updateWalletBalance(balance)
                
                // 处理位置信息
                self.characterStats.location = location.locationStatus.description
                
                // 处理克隆状态
                self.updateCloneStatus(from: cloneInfo)
                
                // 如果没有头像，请求头像
                if characterPortrait == nil {
                    loadingState = .loadingPortrait
                    if let portrait = try? await service.getCharacterPortrait(
                        id: character.CharacterID,
                        forceRefresh: forceRefresh
                    ) {
                        self.characterPortrait = portrait
                    }
                    loadingState = .idle
                }
            } catch {
                lastError = error as? RefreshError ?? .serverStatusFailed
                Logger.error("刷新数据失败: \(error)")
            }
        }
        
        isRefreshing = false
        loadingState = .idle
    }
    
    // 加载保存的角色信息
    private func loadSavedCharacter() {
        Logger.info("正在加载保存的角色信息...")
        Logger.info("当前保存的所选角色ID: \(currentCharacterId)")
        
        if currentCharacterId != 0 {
            if let auth = EVELogin.shared.getCharacterByID(currentCharacterId) {
                selectedCharacter = auth.character
                Logger.info("成功加载保存的角色信息: \(auth.character.CharacterName)")
                
                // 异步加载头像和其他数据
//                Task {
//                    await refreshAllData()
//                }
            } else {
                Logger.warning("找不到保存的角色（ID: \(currentCharacterId)），重置选择")
                resetCharacterInfo()
            }
        }
    }
    
    // 重置角色信息
    func resetCharacterInfo() {
        characterStats = CharacterStats()
        selectedCharacter = nil
        characterPortrait = nil
        isRefreshing = false
        loadingState = .idle
        currentCharacterId = 0
        lastError = nil
        
        // 清除缓存的数据
        cache.clear()
        cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Available", comment: "")
    }
    
    // 从本地快速更新数据（缓存+数据库）
    func quickRefreshFromLocal() async {
        guard let character = selectedCharacter else { return }
        let service = CharacterDataService.shared
        
        // 并发执行所有请求，不强制刷新
        async let skillInfoTask = retryOperation(named: "快速获取技能信息") {
            try await service.getSkillInfo(id: character.CharacterID)
        }
        async let walletTask = retryOperation(named: "快速获取钱包余额") {
            try await service.getWalletBalance(id: character.CharacterID)
        }
        async let locationTask = retryOperation(named: "快速获取位置信息") {
            try await service.getLocation(id: character.CharacterID)
        }
        async let cloneTask = retryOperation(named: "快速获取克隆状态") {
            try await service.getCloneStatus(id: character.CharacterID)
        }
        
        do {
            // 处理技能信息
            let (skillsResponse, queue) = try await skillInfoTask
            processSkillInfo(skillsResponse: skillsResponse, queue: queue)
            
            // 处理钱包余额
            let balance = try await walletTask
            self.cache.walletBalance = balance
            self.updateWalletBalance(balance)
            
            // 处理位置信息
            let location = try await locationTask
            self.characterStats.location = location.locationStatus.description
            
            // 处理克隆状态
            let cloneInfo = try await cloneTask
            self.updateCloneStatus(from: cloneInfo)
        } catch {
            Logger.error("快速刷新数据失败: \(error)")
            // 快速刷新失败不设置错误状态，因为这是一个静默的后台操作
        }
    }
} 
