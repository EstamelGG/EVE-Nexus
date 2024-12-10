//
//  getIconName.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/12/4.
//

import Foundation

// 获取 iconFile_new 的函数
func SelectIconName(databaseManager: DatabaseManager, iconID: Int) -> String {
    // 如果 iconID 为 0，直接返回默认的图标文件名
    if iconID == 0 {
        return "items_73_16_50.png"
    }

    let query = "SELECT icon_file_new FROM icon_ids WHERE icon_id = ?"
    let result = databaseManager.executeQuery(query, parameters: [iconID])
    
    switch result {
    case .success(let rows):
        if let row = rows.first,
           let iconFileNew = row["icon_file_new"] as? String {
            return iconFileNew.isEmpty ? "" : iconFileNew
        }
    case .error(let error):
        Logger.error("Failed to get icon name: \(error)")
    }
    
    return ""
}
