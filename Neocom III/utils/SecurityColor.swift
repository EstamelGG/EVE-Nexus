//
//  SecurtiyColor.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/12/16.
//

import SwiftUI

// 获取安全等级对应的颜色
func getSecurityColor(_ security: Double) -> Color {
    switch security {
    case 0.5...1.0:
        return .blue
    case 0.1..<0.5:
        return .orange
    default:
        return .red
    }
}
