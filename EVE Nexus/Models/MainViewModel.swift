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

@MainActor
class MainViewModel: ObservableObject {
    @Published var characterStats = CharacterStats()
    @Published var serverStatus: ServerStatus?
    @Published var selectedCharacter: EVECharacterInfo?
    @Published var characterPortrait: UIImage?
    @Published var isRefreshing = false
    @Published var isLoadingPortrait = false
    @Published var isLoadingSkills = false
    @Published var isLoadingWallet = false
    @Published var isLoadingQueue = false
    @Published var isLoadingServerStatus = false
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    
    // 缓存最新的数据
    private var cachedSkills: CharacterSkills?
    private var cachedWalletBalance: Double?
    private var cachedSkillQueue: [QueuedSkill]?
    
    // 提供访问缓存数据的方法
    var skills: CharacterSkills? { cachedSkills }
    var walletBalance: Double? { cachedWalletBalance }
    var skillQueue: [QueuedSkill]? { cachedSkillQueue }
    
    init() {
        loadSavedCharacter()
    }
    
    struct CharacterStats {
        var skillPoints: String = "--"
        var queueStatus: String = "--"
        var walletBalance: String = "--"
        var location: String = "--"
        
        static func empty() -> CharacterStats {
            CharacterStats()
        }
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
                Task {
                    await refreshAllData()
                }
            } else {
                Logger.warning("找不到保存的角色（ID: \(currentCharacterId)），重置选择")
                resetCharacterInfo()
            }
        }
    }
    
    // 设置当前角色
    func setCurrentCharacter(_ character: EVECharacterInfo, portrait: UIImage?) {
        resetCharacterInfo()
        selectedCharacter = character
        characterPortrait = portrait
        currentCharacterId = character.CharacterID
        
        Task {
            await refreshAllData()
        }
    }
    
    // 更新方法
    private func updateSkillPoints(_ totalSP: Int?) {
        if let sp = totalSP {
            characterStats.skillPoints = NSLocalizedString("Main_Skills_Ponits", comment: "")
                .replacingOccurrences(of: "$num", with: FormatUtil.format(Double(sp)))
        } else {
            characterStats.skillPoints = NSLocalizedString("Main_Skills_Ponits", comment: "")
                .replacingOccurrences(of: "$num", with: "--")
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
                .replacingOccurrences(of: "$num", with: "--")
        }
    }
    
    // 刷新数据
    func refreshAllData(forceRefresh: Bool = false) async {
        isRefreshing = true
        
        // 服务器状态请求
        Task {
            await MainActor.run { self.isLoadingServerStatus = true }
            if let status = try? await ServerStatusAPI.shared.fetchServerStatus() {
                await MainActor.run {
                    self.serverStatus = status
                    self.isLoadingServerStatus = false
                }
            } else {
                await MainActor.run { self.isLoadingServerStatus = false }
            }
        }
        
        if let character = selectedCharacter {
            // 技能信息请求
            Task {
                await MainActor.run { self.isLoadingSkills = true }
                if let skillsResponse = try? await CharacterSkillsAPI.shared.fetchCharacterSkills(
                    characterId: character.CharacterID,
                    forceRefresh: forceRefresh
                ) {
                    await MainActor.run {
                        // 转换为我们的 CharacterSkills 类型
                        self.cachedSkills = CharacterSkills(
                            total_sp: skillsResponse.total_sp,
                            unallocated_sp: skillsResponse.unallocated_sp
                        )
                        self.updateSkillPoints(skillsResponse.total_sp)
                        self.isLoadingSkills = false
                    }
                } else {
                    await MainActor.run { self.isLoadingSkills = false }
                }
            }
            
            // 钱包余额请求
            Task {
                await MainActor.run { self.isLoadingWallet = true }
                if let balance = try? await CharacterWalletAPI.shared.getWalletBalance(
                    characterId: character.CharacterID,
                    forceRefresh: forceRefresh
                ) {
                    await MainActor.run {
                        self.cachedWalletBalance = balance
                        self.updateWalletBalance(balance)
                        self.isLoadingWallet = false
                    }
                } else {
                    await MainActor.run { self.isLoadingWallet = false }
                }
            }
            
            // 技能队列请求
            Task {
                await MainActor.run { self.isLoadingQueue = true }
                if let queueResponse = try? await CharacterSkillsAPI.shared.fetchSkillQueue(
                    characterId: character.CharacterID,
                    forceRefresh: forceRefresh
                ) {
                    await MainActor.run {
                        // 转换为我们的 QueuedSkill 类型
                        self.cachedSkillQueue = queueResponse.map { skill in
                            QueuedSkill(
                                skill_id: skill.skill_id,
                                skillLevel: skill.finished_level,
                                remainingTime: skill.remainingTime,
                                progress: skill.progress,
                                isCurrentlyTraining: skill.isCurrentlyTraining
                            )
                        }
                        self.updateQueueStatus(
                            length: queueResponse.count,
                            finishTime: queueResponse.last?.remainingTime
                        )
                        self.isLoadingQueue = false
                    }
                } else {
                    await MainActor.run { self.isLoadingQueue = false }
                }
            }
            
            // 如果没有头像，请求头像
            if characterPortrait == nil {
                Task {
                    await MainActor.run { self.isLoadingPortrait = true }
                    if let portrait = try? await CharacterAPI.shared.fetchCharacterPortrait(
                        characterId: character.CharacterID,
                        forceRefresh: forceRefresh
                    ) {
                        await MainActor.run {
                            self.characterPortrait = portrait
                            self.isLoadingPortrait = false
                        }
                    } else {
                        await MainActor.run { self.isLoadingPortrait = false }
                    }
                }
            }
        }
        
        // 立即结束全局刷新状态
        await MainActor.run { self.isRefreshing = false }
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
    }
} 
