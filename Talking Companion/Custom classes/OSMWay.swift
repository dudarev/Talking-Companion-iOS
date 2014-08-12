//
//  OSMWay.swift
//  Talking Companion
//
//  Created by Sergey Butenko on 25.06.14.
//  Copyright (c) 2014 serejahh inc. All rights reserved.
//

import UIKit

class OSMWay: NSObject {
   
    // MARK: - Properties
    
    let wayId:String
    var nodes:Array<String> = Array()
    
    var amenity:String?
    var building:String?
    var name:String?
    var shop:String?
    
    // MARK: - Initializing
    
    init(wayId:String) {
        self.wayId = wayId
    }
    
    // MARK: - Other
    
    func description() -> String {
        var description = isClosedWay() ? "closed" : "open"
        description += " way[\(wayId)]"
        description += " nodes = \(nodes.count)"

        if let amenity = self.amenity {
            description += "; amenity = '\(amenity)'"
        }
        if let building = self.building {
            description += "; building = '\(building)'"
        }
        if let name = self.name {
            description += "; name = '\(name)'"
        }
        if let shop = self.shop {
            description += "; shop = '\(shop)'"
        }
        
        return description
    }
    
    func isClosedWay() -> Bool {
        if (nodes.count > 1) {
            return nodes[0] == nodes[nodes.count-1]
        }
        return false
    }
}
