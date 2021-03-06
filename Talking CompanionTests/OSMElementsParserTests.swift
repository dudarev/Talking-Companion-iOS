//
//  OSMElementsParserTests.swift
//  Talking Companion
//
//  Created by Sergey Butenko on 05.07.14.
//  Copyright (c) 2014 serejahh inc. All rights reserved.
//

import XCTest
import Talking_Companion

let emptyFile = NSBundle.mainBundle().pathForResource("empty", ofType:"osm")
let donetskFile = NSBundle.mainBundle().pathForResource("map", ofType:"osm")

class OSMElementsParserTests: XCTestCase {

    // MARK: - Nodes
    
    func testParsingNodes() {
        let parser = OSMElementsParser(filePath: donetskFile!)
        parser.parseWithComplitionHandler { nodes, ways in
            XCTAssertEqual(nodes.count, 886)
        }
    }
    
    // MARK: - Ways
    
    func testParsingWays() {
        let parser = OSMElementsParser(filePath: donetskFile!)
        parser.parseWithComplitionHandler { nodes, ways in
             XCTAssertEqual(ways.count, 108)
        }
    }
}
