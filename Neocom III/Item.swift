//
//  Item.swift
//  Neocom III
//
//  Created by GG Estamel on 2024/11/28.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
