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
    }
    
    // MARK: - Published Properties
    @Published var characterStats = CharacterStats()
    @Published var serverStatus: ServerStatus?
    @Published var selectedCharacter: EVECharacterInfo?
    @Published var characterPortrait: UIImage?
    @Published var cloneJumpStatus: String = NSLocalizedString("Main_Jump_Clones_Available", comment: "")
    
    // MARK: - Loading States
    @Published var isRefreshing = false
    @Published var isLoadingPortrait = false
    @Published var isLoadingSkills = false
    @Published var isLoadingWallet = false
    @Published var isLoadingQueue = false
    @Published var isLoadingServerStatus = false
    @Published var isLoadingCloneStatus = false
    
    // MARK: - Private Properties
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    private var cachedSkills: CharacterSkills?
    private var cachedWalletBalance: Double?
    private var cachedSkillQueue: [QueuedSkill]?
    
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
    
    private func updateQueueStatus(length: Int?, finishTime: TimeInterval?) {
        if let qLength = length {
            if let time = finishTime {
                let days = Int(time) / 86400
                let hours = (Int(time) % 86400) / 3600
                let minutes = (Int(time) % 3600) / 60
                characterStats.queueStatus = NSLocalizedString("Main_Skills_Queue_Training", comment: "")
                    .replacingOccurrences(of: "$num", with: "\(qLength)")
                    .replacingOccurrences(of: "$day", with: "\(days)")
                    .replacingOccurrences(of: "$hour", with: "\(hours)")
                    .replacingOccurrences(of: "$minutes", with: "\(minutes)")
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
    
    // MARK: - Public Methods
    func refreshAllData(forceRefresh: Bool = false) async {
        isRefreshing = true
        let service = CharacterDataService.shared
        
        // 并发执行所有请求
        async let serverStatusTask = service.getServerStatus(forceRefresh: forceRefresh)
        
        if let character = selectedCharacter {
            async let skillInfoTask = service.getSkillInfo(id: character.CharacterID, forceRefresh: forceRefresh)
            async let walletTask = service.getWalletBalance(id: character.CharacterID, forceRefresh: forceRefresh)
            async let locationTask = service.getLocation(id: character.CharacterID, forceRefresh: forceRefresh)
            async let cloneTask = service.getCloneStatus(id: character.CharacterID, forceRefresh: forceRefresh)
            
            // 处理服务器状态
            if let status = try? await serverStatusTask {
                self.serverStatus = status
            }
            
            // 处理技能信息
            if let (skillsResponse, queue) = try? await skillInfoTask {
                self.cachedSkills = CharacterSkills(
                    total_sp: skillsResponse.total_sp,
                    unallocated_sp: skillsResponse.unallocated_sp
                )
                self.updateSkillPoints(skillsResponse.total_sp)
                
                self.cachedSkillQueue = queue.map { skill in
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
            
            // 处理钱包余额
            if let balance = try? await walletTask {
                self.cachedWalletBalance = balance
                self.updateWalletBalance(balance)
            }
            
            // 处理位置信息
            if let location = try? await locationTask {
                self.characterStats.location = location.locationStatus.description
            }
            
            // 处理克隆状态
            if let cloneInfo = try? await cloneTask {
                self.updateCloneStatus(from: cloneInfo)
            }
            
            // 如果没有头像，请求头像
            if characterPortrait == nil {
                if let portrait = try? await service.getCharacterPortrait(
                    id: character.CharacterID,
                    forceRefresh: forceRefresh
                ) {
                    self.characterPortrait = portrait
                }
            }
        } else {
            // 如果没有选中角色，只更新服务器状态
            if let status = try? await serverStatusTask {
                self.serverStatus = status
            }
        }
        
        isRefreshing = false
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
        isLoadingPortrait = false
        isLoadingSkills = false
        isLoadingWallet = false
        isLoadingQueue = false
        isLoadingServerStatus = false
        currentCharacterId = 0
        
        // 清除缓存的数据
        cachedSkills = nil
        cachedWalletBalance = nil
        cachedSkillQueue = nil
        cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Available", comment: "")
        isLoadingCloneStatus = false
    }
    
    // 从本地快速更新数据（缓存+数据库）
    func quickRefreshFromLocal() async {
        guard let character = selectedCharacter else { return }
        let service = CharacterDataService.shared
        
        // 技能信息和队列
        if let (skillsResponse, queue) = try? await service.getSkillInfo(id: character.CharacterID) {
            await MainActor.run {
                self.cachedSkills = CharacterSkills(
                    total_sp: skillsResponse.total_sp,
                    unallocated_sp: skillsResponse.unallocated_sp
                )
                self.updateSkillPoints(skillsResponse.total_sp)
                
                self.cachedSkillQueue = queue.map { skill in
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
        }
        
        // 钱包余额
        if let balance = try? await service.getWalletBalance(id: character.CharacterID) {
            await MainActor.run {
                self.cachedWalletBalance = balance
                self.updateWalletBalance(balance)
            }
        }
        
        // 位置信息
        if let location = try? await service.getLocation(id: character.CharacterID) {
            await MainActor.run {
                self.characterStats.location = location.locationStatus.description
            }
        }
        
        // 克隆状态
        if let cloneInfo = try? await service.getCloneStatus(id: character.CharacterID) {
            await MainActor.run {
                if let lastJumpDate = cloneInfo.last_clone_jump_date {
                    let dateFormatter = ISO8601DateFormatter()
                    dateFormatter.formatOptions = [.withInternetDateTime]
                    
                    if let jumpDate = dateFormatter.date(from: lastJumpDate) {
                        let now = Date()
                        let timeSinceLastJump = now.timeIntervalSince(jumpDate)
                        let cooldownPeriod: TimeInterval = 24 * 3600 // 24小时冷却
                        
                        if timeSinceLastJump >= cooldownPeriod {
                            self.cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
                        } else {
                            let remainingHours = Int(ceil((cooldownPeriod - timeSinceLastJump) / 3600))
                            self.cloneJumpStatus = String(format: NSLocalizedString("Main_Jump_Clones_Cooldown", comment: ""), remainingHours)
                        }
                    }
                } else {
                    self.cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
                }
            }
        }
    }
} 
