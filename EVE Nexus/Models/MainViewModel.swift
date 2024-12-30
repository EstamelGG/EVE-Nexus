import SwiftUI

@MainActor
class MainViewModel: ObservableObject {
    @Published var characterStats = CharacterStats()
    @Published var serverStatus: ServerStatus?
    @Published var selectedCharacter: EVECharacterInfo?
    @Published var characterPortrait: UIImage?
    @Published var isRefreshing = false
    
    struct CharacterStats {
        var skillPoints: String = "--"
        var queueStatus: String = "--"
        var walletBalance: String = "--"
        var location: String = "--"
        
        static func empty() -> CharacterStats {
            CharacterStats()
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
        defer { isRefreshing = false }
        
        if let character = selectedCharacter {
            // 获取技能信息
            if let skills = try? await CharacterSkillsAPI.shared.fetchCharacterSkills(
                characterId: character.CharacterID,
                forceRefresh: forceRefresh
            ) {
                updateSkillPoints(skills.total_sp)
            }
            
            // 获取钱包余额
            if let balance = try? await CharacterWalletAPI.shared.getWalletBalance(
                characterId: character.CharacterID,
                forceRefresh: forceRefresh
            ) {
                updateWalletBalance(balance)
            }
            
            // 获取技能队列
            if let queue = try? await CharacterSkillsAPI.shared.fetchSkillQueue(
                characterId: character.CharacterID,
                forceRefresh: forceRefresh
            ) {
                updateQueueStatus(
                    length: queue.count,
                    finishTime: queue.last?.remainingTime
                )
            }
            
            // 获取角色头像
            if characterPortrait == nil {
                if let portrait = try? await CharacterAPI.shared.fetchCharacterPortrait(
                    characterId: character.CharacterID,
                    forceRefresh: forceRefresh
                ) {
                    characterPortrait = portrait
                }
            }
        }
        
        // 刷新服务器状态
        if let status = try? await ServerStatusAPI.shared.fetchServerStatus() {
            serverStatus = status
        }
    }
    
    // 重置角色信息
    func resetCharacterInfo() {
        characterStats = CharacterStats()
        selectedCharacter = nil
        characterPortrait = nil
        isRefreshing = false
    }
} 
