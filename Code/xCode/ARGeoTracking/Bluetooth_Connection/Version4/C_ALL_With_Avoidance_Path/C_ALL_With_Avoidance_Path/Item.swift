//
//  Item.swift
//  C_ALL_With_Avoidance_Path
//
//  Created by SSW - Design Team  on 1/28/25.
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
