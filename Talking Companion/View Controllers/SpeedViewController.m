//
//  SpeedViewController.m
//  Talking Companion
//
//  Created by Sergey Butenko on 25.06.14.
//  Copyright (c) 2014 serejahh inc. All rights reserved.
//

#import "SpeedViewController.h"

static const NSTimeInterval pronounceSpeedTimeInterval = 15;
static const NSTimeInterval announceDirectionTimeInterval = 10;
static const double kKilometersPerHour = 3.6;

static const NSTimeInterval downloadTilesTimeInterval = 5; // 60
static const NSInteger kDefaultZoom = 16;
static const CLLocationDistance maxDistance = 10 * 1000;

@implementation SpeedViewController

#pragma mark - View Methonds

- (void)viewDidLoad
{
    [super viewDidLoad];
    tilesDownloader = [[OSMTilesDownloader alloc] init];
    tilesDownloader.delegate = self;
    
    [self loadLocationManager];
    
    NSLog(@"path to documents: %@", NSHomeDirectory());
}

- (void)updateNodesFromDB
{
    OSMTile *centerTile = [[OSMTile alloc] initWithLatitude:currentLocation.coordinate.latitude
                                                  longitude:currentLocation.coordinate.longitude zoom:kDefaultZoom];
    
    NSMutableArray *tmpNodes = [NSMutableArray array];
    NSArray *neighboringTiles = [centerTile neighboringTiles];
    for (OSMTile *currentTile in neighboringTiles) {
        [tmpNodes addObjectsFromArray:[SQLAccess nodesForTile:currentTile]];
    }
    nodes = [NSArray arrayWithArray:tmpNodes];
    NSLog(@"received nodes: %li", nodes.count);
}

- (void)checkLocationsPermissions
{
    if (isLocationEnabled) {
        speechTimer = [NSTimer scheduledTimerWithTimeInterval:pronounceSpeedTimeInterval target:self selector:@selector(speakSpeed) userInfo:nil repeats:YES];
        tilesTimer = [NSTimer scheduledTimerWithTimeInterval:downloadTilesTimeInterval target:self selector:@selector(downloadTiles) userInfo:nil repeats:YES];
        announceDirectionTimer = [NSTimer scheduledTimerWithTimeInterval:announceDirectionTimeInterval target:self selector:@selector(announceDirection) userInfo:nil repeats:YES];
    }
    else {
        if ([speechTimer isValid]) {
            [speechTimer invalidate];
        }
        if ([tilesTimer isValid]) {
            [tilesTimer invalidate];
        }
        if ([announceDirectionTimer isValid]) {
            [announceDirectionTimer invalidate];
        }
    }
    
    self.allowAccessLabel.hidden = isLocationEnabled;
}

#pragma mark -

- (void)downloadTiles
{
    [self neighboringTilesForCoordinates:currentLocation.coordinate];
}

- (void)neighboringTilesForCoordinates:(CLLocationCoordinate2D)coordinates
{
    NSLog(@"downloading neighboring tiles for tile(%lf; %lf)", coordinates.latitude, coordinates.longitude);
    
    OSMTile *centerTile = [[OSMTile alloc] initWithLatitude:coordinates.latitude longitude:coordinates.longitude zoom:kDefaultZoom];
    [tilesDownloader downloadNeighboringTilesForTile:centerTile];
}

#pragma mark - Place details

#pragma mark Speed

- (void)speakSpeed
{
    if (currentSpeed > 0) {
        NSString *speedString = [NSString stringWithFormat:@"%i km per hour", (int)currentSpeed];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:speedString];
        [synth speakUtterance:utterance];
        
        NSLog(@"speak speed: %@", speedString);
    }
    else {
        NSLog(@"try to speak speed");
    }
}

#pragma mark Closest place

- (void)speakPlace:(OSMNode*)place distance:(CLLocationDistance)distance
{
    if (distance > 0) {
        NSString *placeString = [NSString stringWithFormat:@"Closest place is %@, %@ with distance %li m", place.name, place.type, (long)distance];
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:placeString];
        [synth speakUtterance:utterance];
        [place announce];
        
         NSLog(@"announce place \"%@\"", placeString);
    }
}

- (void)announceClosestPlaceWithAngle:(double)angle
{
    OSMNode *closestPlace;
    CLLocationDistance minDistance = INT_MAX;
    
    for (OSMNode *node in nodes) {
        CLLocationDistance distance = [currentLocation distanceFromLocation:node.location];

        if (minDistance > distance) {
            minDistance = distance;
            closestPlace = node;
        }
    }
    
    if (minDistance > maxDistance) {
        _distanceLabel.text = @"can't detect";
        return;
    }
    
    if (!closestPlace.isAnnounced) {
        [self speakPlace:closestPlace distance:minDistance];
    }
    
    NSString *direction = @"can't detect";
    if (angle >=0 && angle < 45) {
        direction = @"in front";
    }
    else if (angle >=45 && angle < 135) {
        direction = @"right";
    }
    else if (angle >=135 && angle < 225) {
        direction = @"back";
    }
    else if (angle >=225 && angle < 315) {
        direction = @"left";
    }
    else if (angle >=315 && angle <= 360) {
        direction = @"in front";
    }
    
    _nameLabel.text = closestPlace.name;
    _distanceLabel.text = [NSString stringWithFormat:@"%li m.", (long)minDistance];
    _typeLabel.text = closestPlace.type;
    _directionLabel.text = [NSString stringWithFormat:@"%@ (%i degree)", direction, (int)angle];
    closestPlaceLocation = closestPlace.location;
}

#pragma mark Direction

- (void)announceDirection
{
    double theta = [Calculations thetaForCurrentLocation:currentLocation previousLocation:previousLocation placeLocation:closestPlaceLocation];
    [self announceClosestPlaceWithAngle:theta];
    previousLocation = currentLocation;
}

#pragma mark - CLLocationManager Delegate

- (void)loadLocationManager
{
    manager = [[CLLocationManager alloc] init];
    manager.delegate = self;
    manager.desiredAccuracy = kCLLocationAccuracyBest;
    //[manager requestAlwaysAuthorization];
    [manager startUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation
{
    currentSpeed = newLocation.speed * kKilometersPerHour;
    currentSpeed = currentSpeed > 0 ? currentSpeed : 0;
    _currentSpeedLabel.text = [NSString stringWithFormat:@"%.2lf km/h", currentSpeed];
    
    currentLocation = newLocation;
    
    if (previousLocation == nil) {
        NSLog(@"initial coordinates: (%lf; %lf)", currentLocation.coordinate.latitude, currentLocation.coordinate.longitude);
        previousLocation = newLocation;
        
        [self updateNodesFromDB];
        [self downloadTiles];
        [self announceDirection];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    NSLog(@"location manager error: %@", error);
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    NSLog(@"location manager status: %i", status);
    if (status == kCLAuthorizationStatusDenied || status == kCLAuthorizationStatusNotDetermined) {
        isLocationEnabled = NO;
    }
    else {
        isLocationEnabled = YES;
    }
    [self checkLocationsPermissions];
}

#pragma mark - OSMTileDownloader Delegate

- (void)tilesDownloaded
{
    [self updateNodesFromDB];
}

@end
