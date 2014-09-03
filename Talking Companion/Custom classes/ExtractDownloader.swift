//
//  ExctractDownloader.swift
//  Talking Companion
//
//  Created by Sergey Butenko on 8/8/14.
//  Copyright (c) 2014 serejahh inc. All rights reserved.
//

import UIKit

let OSMExtractURL = "https://s3.amazonaws.com/metro-extracts.mapzen.com/"
let OSMExtractFormat = ".osm.bz2"

let JSONExtractURL = "download.locograph.com/city/"
let JSONExtractFormat = ".json.bz2"


@objc protocol ExtractDownloaderDelegate:NSObjectProtocol {
    func extractDownloaderFinished(nodes:[OSMNode])
    func extractDownloaderFailed(error:NSError)
}

class ExtractDownloader: NSObject {
   
    let delegate:ExtractDownloaderDelegate
    
    init(delegate:ExtractDownloaderDelegate) {
        self.delegate = delegate
    }
    
    func downloadCity(city:String) {
        let urlString = "\(OSMExtractURL)\(city)\(OSMExtractFormat)"
        
        //[client.parameterEncoding = AFJSONParameterEncoding;
        //[client setDefaultHeader:@"Accept" value:@"text/json"];
        
        // downloading extract
        let request = NSURLRequest(URL: NSURL(string: urlString))
        var operation = AFHTTPRequestOperation(request: request)
        operation.setCompletionBlockWithSuccess({ (_, responseObject) in
            NSLog("extract downloaded")
            
            let compressedData = responseObject as NSData
            let uncompressedData = compressedData.bunzip2()
            self.parseXMLFromString(uncompressedData)
        },
        failure: { [unowned self] (_, error) in })
        operation.start()
    }
    
    func parseXMLFromString(xmlData:NSData) {
        let parser = OSMElementsParser(xmlData: xmlData)
        parser.parseWithComplitionHandler() { nodes, _ in
            self.delegate.extractDownloaderFinished(nodes)
        };
    }
    
    func downloadExtractForCity(city:String) {
        let urlString = "\(JSONExtractURL)\(city)\(JSONExtractFormat)"
        
        // downloading extract
        let request = NSURLRequest(URL: NSURL(string: urlString))
        var operation = AFHTTPRequestOperation(request: request)
        operation.setCompletionBlockWithSuccess({ (_, responseObject) in

            },
            failure: { [unowned self] (operation, error) in
                self.delegate.extractDownloaderFailed(error)
            })
        operation.start()
    }
}
