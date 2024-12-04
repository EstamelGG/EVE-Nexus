//
//  getIconName.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/12/4.
//

import SQLite3

// 获取 iconFile_new 的函数
func SelectIconName(from db: OpaquePointer, iconID: Int) -> String {
    // 如果 iconID 为 0，直接返回默认的图标文件名
    if iconID == 0 {
        return "items_73_16_50.png"
    }

    let query = "SELECT iconFile_new FROM iconIDs WHERE icon_id = ?"
    var statement: OpaquePointer?
    var iconFileNew = ""

    // 准备并执行 SQL 查询
    if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
        sqlite3_bind_int(statement, 1, Int32(iconID))

        // 检查查询是否成功
        if sqlite3_step(statement) == SQLITE_ROW {
            // 获取 iconFile_new 字段值
            if let iconFileNewPointer = sqlite3_column_text(statement, 0) {
                iconFileNew = String(cString: iconFileNewPointer)
            }
        }
        sqlite3_finalize(statement)
    } else {
        print("Failed to prepare iconIDs query")
    }

    // 如果未找到结果或 iconFile_new 为空，返回空字符串
    return iconFileNew.isEmpty ? "" : iconFileNew
}
