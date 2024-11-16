//
//  Item.swift
//  CreatingLidarModel
//
//  Created by SSW - Design Team  on 11/14/24.
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
