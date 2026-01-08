//
//  Item.swift
//  metaface
//
//  Created by Justin Williams on 1/8/26.
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
