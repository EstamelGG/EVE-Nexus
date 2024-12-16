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
    case 0.9...1.0:
        return Color(red: 65/255, green: 115/255, blue: 212/255)
    case 0.8..<0.9:
        return Color(red: 85/255, green: 154/255, blue: 239/255)
    case 0.7..<0.8:
        return Color(red: 114/255, green: 204/255, blue: 237/255)
    case 0.6..<0.7:
        return Color(red: 129/255, green: 216/255, blue: 169/255)
    case 0.5..<0.6:
        return Color(red: 143/255, green: 225/255, blue: 103/255)
    case 0.4..<0.5:
        return Color(red: 242/255, green: 254/255, blue: 149/255)
    case 0.0..<0.4:
        return Color(red: 208/255, green: 113/255, blue: 45/255)
    default:
        return Color(red: 131/255, green: 55/255, blue: 100/255)
    }
}
