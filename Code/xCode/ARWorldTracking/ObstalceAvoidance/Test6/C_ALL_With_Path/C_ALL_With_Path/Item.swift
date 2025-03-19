//
//  Item.swift
//  C_ALL_With_Path
//
//  Created by SSW - Design Team  on 11/18/24.
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
