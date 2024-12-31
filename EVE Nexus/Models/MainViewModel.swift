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
    @Published var isLoadingCloneStatus = false
    @Published var cloneJumpStatus: String = NSLocalizedString("Main_Jump_Clones_Available", comment: "")
    @AppStorage("currentCharacterId") private var currentCharacterId: Int = 0
    
    // 缓存最新的数据
    private var cachedSkills: CharacterSkills?
    private var cachedWalletBalance: Double?
    private var cachedSkillQueue: [QueuedSkill]?
    private var cachedCloneJumpHours: Double?
    
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
//                Task {
//                    await refreshAllData()
//                }
            } else {
                Logger.warning("找不到保存的角色（ID: \(currentCharacterId)），重置选择")
                resetCharacterInfo()
            }
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
    
    // 从缓存获取钱包余额
    private func getCachedWalletBalance(characterId: Int) -> Double? {
        if let balanceString = UserDefaults.standard.string(forKey: "wallet_cache_\(characterId)") {
            return Double(balanceString)
        }
        return nil
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
                        // 更新内存缓存
                        self.cachedSkills = CharacterSkills(
                            total_sp: skillsResponse.total_sp,
                            unallocated_sp: skillsResponse.unallocated_sp
                        )
                        self.updateSkillPoints(skillsResponse.total_sp)
                        
                        // 更新数据库缓存
                        let skillsJson = try? JSONEncoder().encode(skillsResponse)
                        if let skillsData = skillsJson {
                            let query = """
                                INSERT OR REPLACE INTO character_skills 
                                (character_id, skills_data, total_sp, unallocated_sp, last_updated) 
                                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                            """
                            let result = CharacterDatabaseManager.shared.executeQuery(
                                query,
                                parameters: [
                                    character.CharacterID,
                                    String(data: skillsData, encoding: .utf8) ?? "",
                                    skillsResponse.total_sp,
                                    skillsResponse.unallocated_sp
                                ]
                            )
                            
                            if case .error(let error) = result {
                                Logger.error("保存技能数据到数据库失败: \(error)")
                            }
                        }
                        
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
                        // 更新内存缓存
                        self.cachedWalletBalance = balance
                        self.updateWalletBalance(balance)
                        
                        // 更新 UserDefaults 缓存
                        UserDefaults.standard.set(
                            String(balance),
                            forKey: "wallet_cache_\(character.CharacterID)"
                        )
                        
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
                        // 更新内存缓存
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
                        
                        // 更新数据库缓存
                        let queueJson = try? JSONEncoder().encode(queueResponse)
                        if let queueData = queueJson {
                            let query = """
                                INSERT OR REPLACE INTO character_skill_queue 
                                (character_id, queue_data, last_updated) 
                                VALUES (?, ?, CURRENT_TIMESTAMP)
                            """
                            let result = CharacterDatabaseManager.shared.executeQuery(
                                query,
                                parameters: [
                                    character.CharacterID,
                                    String(data: queueData, encoding: .utf8) ?? ""
                                ]
                            )
                            
                            if case .error(let error) = result {
                                Logger.error("保存技能队列到数据库失败: \(error)")
                            }
                        }
                        
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
            
            // 位置信息请求
            Task {
                if let location = try? await CharacterLocationAPI.shared.fetchCharacterLocation(
                    characterId: character.CharacterID,
                    forceRefresh: forceRefresh
                ) {
                    // 更新 UserDefaults 缓存
                    let locationData = try? JSONEncoder().encode(location)
                    if let data = locationData {
                        UserDefaults.standard.set(data, forKey: "location_\(character.CharacterID)")
                    }
                }
            }
            
            // 克隆体状态请求
            Task {
                await MainActor.run { self.isLoadingCloneStatus = true }
                if let remainingHours = await CharacterClonesAPI.shared.getJumpCooldownHours(
                    characterId: character.CharacterID
                ) {
                    await MainActor.run {
                        // 更新内存缓存
                        self.cachedCloneJumpHours = remainingHours
                        
                        if remainingHours <= 0 {
                            self.cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
                        } else {
                            let hours = Int(ceil(remainingHours))
                            self.cloneJumpStatus = String(format: NSLocalizedString("Main_Jump_Clones_Cooldown", comment: ""), hours)
                        }
                        
                        self.isLoadingCloneStatus = false
                    }
                } else {
                    await MainActor.run {
                        self.cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
                        self.isLoadingCloneStatus = false
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
        cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Available", comment: "")
        isLoadingCloneStatus = false
        cachedCloneJumpHours = nil
    }
    
    // 从本地快速更新数据（缓存+数据库）
    func quickRefreshFromLocal() async {
        guard let character = selectedCharacter else { return }
        
        // 从数据库读取技能信息
        let query = """
            SELECT skills_data, total_sp, unallocated_sp 
            FROM character_skills 
            WHERE character_id = ? 
            AND datetime(last_updated) > datetime('now', '-1 hour')
        """
        if case .success(let result) = CharacterDatabaseManager.shared.executeQuery(query, parameters: [character.CharacterID]),
           let row = result.first,
           let totalSp = row["total_sp"] as? Int,
           let unallocatedSp = row["unallocated_sp"] as? Int {
            await MainActor.run {
                self.cachedSkills = CharacterSkills(
                    total_sp: totalSp,
                    unallocated_sp: unallocatedSp
                )
                self.updateSkillPoints(totalSp)
            }
        }
        
        // 从缓存读取钱包余额
        let balanceString = await CharacterWalletAPI.shared.getCachedWalletBalance(characterId: character.CharacterID)
        if !balanceString.isEmpty {
            Logger.info("尝试读取钱包余额缓存 - 角色ID: \(character.CharacterID)")
            if let balance = Double(balanceString) {
                Logger.info("成功读取钱包余额缓存: \(balance) ISK")
                await MainActor.run {
                    self.cachedWalletBalance = balance
                    self.updateWalletBalance(balance)
                }
            } else {
                Logger.warning("钱包余额缓存格式错误: \(balanceString)")
            }
        } else {
            Logger.warning("未找到钱包余额缓存 - 角色ID: \(character.CharacterID)")
        }
        
        // 从数据库读取技能队列
        let queueQuery = """
            SELECT queue_data 
            FROM character_skill_queue 
            WHERE character_id = ? 
            AND datetime(last_updated) > datetime('now', '-1 hour')
        """
        if case .success(let result) = CharacterDatabaseManager.shared.executeQuery(queueQuery, parameters: [character.CharacterID]),
           let row = result.first,
           let queueData = row["queue_data"] as? String,
           let queueResponse = try? JSONDecoder().decode([SkillQueueItem].self, from: queueData.data(using: .utf8) ?? Data()) {
            await MainActor.run {
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
            }
        }
        
        // 从 UserDefaults 读取位置信息
        if let locationData = UserDefaults.standard.data(forKey: "location_\(character.CharacterID)"),
           let location = try? JSONDecoder().decode(CharacterLocation.self, from: locationData) {
            // 更新位置信息
            await MainActor.run {
                self.characterStats.location = location.locationStatus.description
            }
        }
        
        // 从数据库读取克隆体状态
        if let remainingHours = await CharacterClonesAPI.shared.getJumpCooldownHours(characterId: character.CharacterID) {
            await MainActor.run {
                self.cachedCloneJumpHours = remainingHours
                if remainingHours <= 0 {
                    self.cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
                } else {
                    let hours = Int(ceil(remainingHours))
                    self.cloneJumpStatus = String(format: NSLocalizedString("Main_Jump_Clones_Cooldown", comment: ""), hours)
                }
            }
        } else {
            await MainActor.run {
                self.cloneJumpStatus = NSLocalizedString("Main_Jump_Clones_Ready", comment: "")
            }
        }
    }
} 
