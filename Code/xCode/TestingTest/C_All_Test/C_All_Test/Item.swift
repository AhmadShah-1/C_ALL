//
//  Item.swift
//  C_All_Test
//
//  Created by SSW - Design Team  on 2/13/25.
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
