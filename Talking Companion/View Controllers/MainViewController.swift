//
//  MainViewController.swift
//  Talking Companion
//
//  Created by Sergey Butenko on 25.06.14.
//  Copyright (c) 2014 serejahh inc. All rights reserved.
//

import UIKit
import CoreLocation
import AVFoundation

/// for debug using 5s, for release 60s
let kDownloadTilesTimeInterval:NSTimeInterval = 60

/// Time for waiting to disappear gear(settings) icon
let kHideSettingsButtonInterval:NSTimeInterval = 10

/// zoom for tiles from OpenStreetMap
let kDefaultZoom = 16

/// A kilometer has 1000 meters
let kKilometer = 1000

let kMaxFeet = 2640

/// constant for convertion meters to feet
let kMetersToFeet = 3.2808

/// Minimal travelled distance for speaking (meters)
let kMinimalTravelledDistance:CLLocationDistance = 25

/// 
let kMaxDistance:CLLocationDistance = CLLocationDistance(10 * kKilometer)

/// choosen by @dudarev (described in issue #30)
let kMaxCountClosestPlaces = 10

/// chosen experimentally by @dudarev
let kSpeachSpeedReduceRate:Float = 2.2

class MainViewController: UIViewController, CLLocationManagerDelegate, OSMTilesDownloaderDelegate {
    
    // MARK: - Outlets
    
    @IBOutlet weak var settingsButton: UIButton!
    
    @IBOutlet weak var typeLabel: UILabel!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var statusLabel: UILabel!
    
    // MARK: - Properties
    
    private let locationManager = CLLocationManager()
    private var currentLocation:CLLocation?
    private var previousLocation:CLLocation?
    private var closestPlaceLocation:CLLocation?
    
    private var tilesDownloader:OSMTilesDownloader?
    private let synth = AVSpeechSynthesizer()
    
    private var hideSettingsButtonTimer:NSTimer!
    private var tilesTimer:NSTimer?
    private var announceDistanceTimer:NSTimer?
    private var announceDistanceTimeInterval:NSTimeInterval?
    
    private var nodes = [OSMNode]()
    private var transtalor:TypeTranslator!
    
    // MARK: - ViewController Methods
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: true)
        
        self.previousLocation = nil
        self.locationManager.startUpdatingLocation()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("path to documents: \(NSHomeDirectory())")
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "voiceFrequencyChanged", name: kVoiceFrequencyNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "requestAccessToLocationServices", name: kApplicationBecomeActiveNotification, object: nil)
        self.settingsButton.setTitle(kSettingsButtonIcon, forState: .Normal)
        
        let language = NSLocale.preferredLanguages().first as! String
        self.transtalor = TypeTranslator(language: language)
        
        self.updateNodesFromDB()
        
        let tap = UITapGestureRecognizer(target: self, action: "showSettingsButton:")
        self.view.addGestureRecognizer(tap)
        self.startHideButtonTimer()
        
        self.tilesDownloader = OSMTilesDownloader(delegate: self)
        self.tilesDownloader?.delegate = self
        loadLocationManager()
    }
    
    override func viewWillDisappear(animated: Bool) {
        self.navigationController?.setNavigationBarHidden(false, animated: true)
        super.viewWillDisappear(animated)
    }
    
    func loadLocationManager() {
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.requestAccessToLocationServices()
        self.locationManager.startUpdatingLocation()
    }
    
    func voiceFrequencyChanged() {
        announceDistanceTimer?.invalidate()
        
        let index = NSUserDefaults.standardUserDefaults().integerForKey(kVoiceFrequency)
        let settings = NSDictionary(contentsOfFile: NSBundle.mainBundle().pathForResource("Settings", ofType: "plist")!)!
        let durations = settings["Durations"] as! [Double]
        announceDistanceTimeInterval = durations[index]
        announceDistanceTimer = NSTimer.scheduledTimerWithTimeInterval(announceDistanceTimeInterval!, target: self, selector: "announceClosestPlace", userInfo: nil, repeats: true)
        announceDistanceTimer!.fire()
    }
    
    private func isMoving() -> Bool {
        if currentLocation == nil || previousLocation == nil || currentLocation?.distanceFromLocation(previousLocation) < kMinimalTravelledDistance {
            return false
        }
        return true
    }
    
    private func updateStatus() {
        var status = ""
        
        if !self.isMoving() {
            status += NSLocalizedString("StartMoving", comment: "")
            status += "\n"
        }
        
        status += "\(self.nodes.count) 📍 "
        status += NSLocalizedString("PointsAround", comment: "")
        self.statusLabel.text = status
    }
    
    func requestAccessToLocationServices() {
        if (self.locationManager.respondsToSelector("requestAlwaysAuthorization")) {
            self.locationManager.requestAlwaysAuthorization()
        }
    }
    
    // MARK: - Settings Button
    
    func showSettingsButton(recognizer:UIGestureRecognizer) {
        self.settingsButton.hidden = !self.settingsButton.hidden
        
        if self.settingsButton.hidden {
            hideSettingsButtonTimer.invalidate()
        }
        else {
            self.startHideButtonTimer()
        }
    }
    
    func startHideButtonTimer() {
        self.hideSettingsButtonTimer = NSTimer.scheduledTimerWithTimeInterval(kHideSettingsButtonInterval, target: self, selector: "hideSettingsButton", userInfo: nil, repeats: false)
    }
    
    func hideSettingsButton() {
        self.settingsButton.hidden = true
    }
    
    @IBAction func showSettingsViewController(sender: UIButton!) {
        if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
            self.performSegueWithIdentifier("Popover Settings", sender: sender)
        }
        else {
            self.performSegueWithIdentifier("Push Settings", sender: sender)
        }
    }
    
    // MARK: - Fetching Nodes
    
    func updateNodesFromDB() {
        if let current = self.currentLocation {
            let centerTile = OSMTile(latitude: current.coordinate.latitude, longitude: current.coordinate.longitude, zoom: kDefaultZoom)
            
            let shoulUpdateFrequencyTimer = count(self.nodes) == 0
            
            var tmpNodes = [OSMNode]()
            let neighboringTiles = centerTile.neighboringTiles()
            for currentTile in neighboringTiles {
                tmpNodes += Database.nodesForTile(currentTile)
            }
            self.nodes = tmpNodes
            
            self.updateStatus()
            if shoulUpdateFrequencyTimer {
                self.voiceFrequencyChanged()
            }
        }
    }
    
    func downloadNeighboringTiles() {
        if let current = self.currentLocation {
            self.statusLabel.text = NSLocalizedString("LoadingData", comment: "")
            let centerTile = OSMTile(latitude: current.coordinate.latitude, longitude: current.coordinate.longitude, zoom: kDefaultZoom)
            self.tilesDownloader?.downloadNeighboringTilesFor(tile: centerTile)
            //NSLog(@"downloading neighboring tiles for tile(%lf; %lf) @ %@", coordinates.latitude, coordinates.longitude, [[OSMBoundingBox alloc] initWithTile:centerTile].url);
        }
    }
    
    // MARK: - OSMTileDownloader Delegate
    
    func tileDownloaded() {
        self.updateNodesFromDB()
    }
    
    // MARK: - Place details
    
    func announceClosestPlace() {
        self.updateStatus()
        
        var closestPlace:OSMNode?
        var distanceToClosestPlace:CLLocationDistance = Double(INT_MAX)
        let bound = min(count(nodes), kMaxCountClosestPlaces)
        
        // choose unannounced
        for var i = 0; i < bound; i++ {
            let node = nodes[i]
            let distance = currentLocation!.distanceFromLocation(node.location)
            
            if !node.isAnnounced && distanceToClosestPlace > distance {
                distanceToClosestPlace = distance
                closestPlace = node
            }
        }
        
        // if all places were announced, choose a place that was announced longest time ago
        if closestPlace == nil {
            var latestDate = NSDate()
            for var i = 0; i < bound; i++ {
                let node = nodes[i]
                if node.announcedDate!.compare(latestDate) == NSComparisonResult.OrderedAscending {
                    closestPlace = node
                    latestDate = node.announcedDate!
                    distanceToClosestPlace = currentLocation!.distanceFromLocation(node.location)
                }
            }
        }
        
        // no places nearby
        if closestPlace == nil {
            return
        }
        
        // have a place for announcing
        closestPlaceLocation = closestPlace!.location
        var distance = self.distanceStringWithDistance(distanceToClosestPlace)

        if isMoving() && currentLocation != nil && previousLocation != nil {
            let angle = Calculations.thetaForCurrentLocation(currentLocation!, previousLocation: previousLocation!, placeLocation: closestPlaceLocation!)
            let direction = Direction(angle: angle)
            distance += " \(direction.description)"
        }
        self.previousLocation = currentLocation
        
        self.speakPlace(closestPlace!, distance: distance)
        
        self.nameLabel.text = transtalor.traslatedNameForDisplaying(node: closestPlace!)
        self.distanceLabel.text = "\(distance)"

        if let type = transtalor.translatedTypeForTypes(types: closestPlace!.types) {
            self.typeLabel.text = type
        }
    }
    
    // TODO: rewrite
    func distanceStringWithDistance(var distance:CLLocationDistance) -> String {
        let language = NSLocale.preferredLanguages().first as! String
        var isMetric = true
        if language != "ru" && !NSLocale.currentLocale().objectForKey(NSLocaleUsesMetricSystem)!.boolValue! {
            isMetric = false
        }
        
        var distanceString = ""
        if isMetric {
            if distance > kMaxDistance {
                distanceString = NSString(format: "%@ %d %@", NSLocalizedString("OverDistance", comment: ""), Int(kMaxDistance) / kKilometer, NSLocalizedString("KilometerShort", comment: "")) as String
            }
            else if distance > Double(kKilometer) {
                distanceString = NSString(format: "%.1lf %@", distance / Double(kKilometer), NSLocalizedString("KilometerShort", comment: "")) as String
            }
            else {
                distanceString = NSString(format: "%d %@", Int(distance), NSLocalizedString("MeterShort", comment: "")) as String
            }
        }
        else {
            if distance > kMaxDistance * kMetersToFeet {
                distanceString = NSString(format: "%@ %d %@", NSLocalizedString("OverDistance", comment: ""), Int(kMaxDistance * kMetersToFeet) / kKilometer, NSLocalizedString("MilesShort", comment: "")) as String
            }
            else if distance > Double(kMaxFeet) {
                distanceString = NSString(format: "%.1lf %@", distance / Double(kMaxFeet), NSLocalizedString("MilesShort", comment: "")) as String
            }
            else {
                distanceString = NSString(format: "%d %@", Int(distance), NSLocalizedString("FeetShort", comment: "")) as String
            }
        }
        
        return distanceString
    }
    
    func speakPlace(place:OSMNode, distance:String) {
        var placeString = ""
        if let type = transtalor.translatedTypeForTypes(types: place.types) {
            placeString += "\(type). "
        }
        let name = transtalor.traslatedNameForSpeaking(node: place)
        placeString += "\(name), \(distance)"
        
        let utterance = AVSpeechUtterance(string: placeString)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate / kSpeachSpeedReduceRate
        synth.speakUtterance(utterance)
        place.announce()
        NSLog("announce place \"\(placeString)\"")
    }
    
    // MARK: - CLLocationManager Delegate
    
    func locationManager(manager: CLLocationManager!, didUpdateToLocation newLocation: CLLocation!, fromLocation oldLocation: CLLocation!) {
        self.currentLocation = newLocation

        if self.previousLocation == nil {
            NSLog("initial coordinates: \(currentLocation?.coordinate.latitude); \(currentLocation?.coordinate.longitude)")
            self.previousLocation = newLocation
            
            self.updateNodesFromDB()
            self.downloadNeighboringTiles()
        }
    }
    
    func locationManager(manager: CLLocationManager!, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        NSLog("location manager status: \(status.rawValue)")
        self.checkLocationsPermissions()
    }
    
    func locationManager(manager: CLLocationManager!, didFailWithError error: NSError!) {
        NSLog("location manager error: \(error)")
        self.checkLocationsPermissions()
    }
    
    // start or stop downloading
    func checkLocationsPermissions() {
        let isLocationEnabled = CLLocationManager.locationServicesEnabled()
//        let correctPermissions = CLLocationManager.authorizationStatus() == .Authorized || CLLocationManager.authorizationStatus() == .AuthorizedWhenInUse)
        
        if isLocationEnabled {
            tilesTimer = NSTimer.scheduledTimerWithTimeInterval(kDownloadTilesTimeInterval, target: self, selector: "downloadNeighboringTiles", userInfo: nil, repeats: true)
            tilesTimer?.fire()
            self.voiceFrequencyChanged()
        }
        else {
            tilesTimer?.invalidate()
            announceDistanceTimer?.invalidate()
        }
        
        self.statusLabel.text = isLocationEnabled ? "" : NSLocalizedString("AllowLocationAccess", comment: "")
    }
}
