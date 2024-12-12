//
//  Item.swift
//  C_ALL_With_Avoidance
//
//  Created by SSW - Design Team  on 12/11/24.
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
