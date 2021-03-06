/*
 * Copyright (c) 2015 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import CoreData
import CoreLocation
import HealthKit
import MapKit
import AudioToolbox

let DetailSegueName = "RunDetails"

class NewRunViewController: UIViewController,MKMapViewDelegate,CLLocationManagerDelegate {
    var managedObjectContext: NSManagedObjectContext?
    
    var run: Run!
    var seconds = 0.0
    var distance = 0.0
    var instantPace = 0.0
    var vertClimb = 0.0
    var vertDescent = 0.0
    var previousAlt = 0.0
    lazy var locationManager: CLLocationManager = {
        var _locationManager = CLLocationManager()
        _locationManager.delegate = self
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest
        _locationManager.activityType = .fitness
        
        // Movement threshold for new events
        _locationManager.distanceFilter = 10.0
        return _locationManager
    }()
    
    lazy var locations = [CLLocation]()
    lazy var timer = Timer()
    var mapOverlay: MKTileOverlay!
    var upcomingBadge : Badge?
    
    @IBOutlet weak var mapView2: MKMapView!
    @IBOutlet weak var promptLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var paceLabel: UILabel!
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var stopButton: UIButton!
    @IBOutlet weak var climbLabel: UILabel!
    @IBOutlet weak var descentLabel: UILabel!
    @IBOutlet weak var nextBadgeImageView: UIImageView!
    @IBOutlet weak var nextBadgeLabel: UILabel!
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startButton.isHidden = false
        promptLabel.isHidden = false
        
        timeLabel.isHidden = true
        distanceLabel.isHidden = true
        paceLabel.isHidden = true
        climbLabel.isHidden = true
        descentLabel.isHidden = true
        stopButton.isHidden = true
        mapView2.isHidden = false
        nextBadgeLabel.isHidden = true
        nextBadgeImageView.isHidden = true
        
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.allowsBackgroundLocationUpdates = true
        //locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness
        locationManager.distanceFilter = 10.0
        locationManager.requestAlwaysAuthorization()
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        mapView2.delegate = self;
        
        mapView2.showsUserLocation = true
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let regionRadius: CLLocationDistance = 1000
        let coordinateRegion = MKCoordinateRegionMakeWithDistance(mapView2.userLocation.coordinate,regionRadius * 2.0, regionRadius * 2.0)
        mapView2.setRegion(coordinateRegion, animated: true)
    }
    @IBAction func startPressed(_ sender: AnyObject) {
        startButton.isHidden = true
        promptLabel.isHidden = true
        
        timeLabel.isHidden = false
        distanceLabel.isHidden = false
        paceLabel.isHidden = false
        climbLabel.isHidden = false
        descentLabel.isHidden = false
        stopButton.isHidden = false
        mapView2.isHidden = false
        nextBadgeLabel.isHidden = false
        nextBadgeImageView.isHidden = false
        
        seconds = 0.0
        distance = 0.0
        vertClimb = 0.0
        vertDescent = 0.0
        instantPace = 0.0
        previousAlt = -1000
        locations.removeAll(keepingCapacity: false)
        timer = Timer.scheduledTimer(timeInterval: 1,
                                     target: self,
                                     selector: #selector(eachSecond(_:)),
                                     userInfo: nil,
                                     repeats: true)
        startLocationUpdates()
    }
    
    @IBAction func stopPressed(_ sender: AnyObject) {
        self.locationManager.stopUpdatingLocation();
        let actionSheet = UIAlertController.init(title: "Run Stopped", message: nil, preferredStyle: .actionSheet)
                        actionSheet.addAction(UIAlertAction.init(title: "Save Run", style: UIAlertActionStyle.default, handler: { (action) in
                            self.saveRun();
                            self.performSegue(withIdentifier: DetailSegueName, sender: nil);
        }))
        actionSheet.addAction(UIAlertAction.init(title: "Discard Run", style: UIAlertActionStyle.destructive, handler: { (action) in
            self.navigationController?.popToRootViewController(animated: true)

        }))

        actionSheet.addAction(UIAlertAction.init(title: "Cancel", style: UIAlertActionStyle.cancel, handler: { (action) in
            // self.dismissViewControllerAnimated(true, completion: nil) is not needed, this is handled automatically,
            //Plus whatever method you define here, gets called,
            //If you tap outside the UIAlertController action buttons area, then also this handler gets called.
                self.startLocationUpdates()
        }))

        //Present the controller
        self.present(actionSheet, animated: true, completion: nil)

        
        
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let detailViewController = segue.destination as? DetailViewController {
            detailViewController.run = run
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer.invalidate()
    }
    
    func eachSecond(_ timer: Timer) {
        seconds += 1
        let (h,m,s) = secondsToHoursMinutesSeconds(seconds: Int(seconds))
        let secondsQuantity = HKQuantity(unit: HKUnit.second(), doubleValue: Double(s))
        let minutesQuantity = HKQuantity(unit: HKUnit.minute(), doubleValue: Double(m))
        let hoursQuantity = HKQuantity(unit: HKUnit.hour(), doubleValue: Double(h))
        timeLabel.text = "Time: "+hoursQuantity.description+" "+minutesQuantity.description+" "+secondsQuantity.description
        let distanceQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: distance)
        distanceLabel.text = "Distance: " + distanceQuantity.description
        
        paceLabel.text = "Current speed: "+String((instantPace*3.6*10).rounded()/10)+" km/h"//"Pace: "+String((distance/seconds*3.6*10).rounded()/10)+" km/h"
        
        climbLabel.text = "Total climb: "+String((vertClimb*10).rounded()/10)+" m"
        descentLabel.text = "Total descent: "+String((vertDescent*10).rounded()/10)+" m"
        
        checkNextBadge()
        if let upcomingBadge = upcomingBadge {
            let nextBadgeDistanceQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: upcomingBadge.distance! - distance)
            nextBadgeLabel.text = "\(nextBadgeDistanceQuantity.description) until \(upcomingBadge.name!)"
            nextBadgeImageView.image = UIImage(named: upcomingBadge.imageName!)
        }
    }
    func secondsToHoursMinutesSeconds (seconds : Int) -> (Int, Int, Int) {
        return (seconds / 3600, (seconds % 3600) / 60, (seconds % 3600) % 60)
    }
    func startLocationUpdates() {
        locationManager.startUpdatingLocation()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            
            let howRecent = location.timestamp.timeIntervalSinceNow
            
            if abs(howRecent) < 10 && location.horizontalAccuracy < 20 {
                //update distance
                if self.locations.count > 0 {
                    distance += location.distance(from: self.locations.last!)
                    
                    var coords = [CLLocationCoordinate2D]()
                    coords.append(self.locations.last!.coordinate)
                    coords.append(location.coordinate)
                    
                    instantPace = location.distance(from: self.locations.last!)/(location.timestamp.timeIntervalSince(self.locations.last!.timestamp))

                    let region = MKCoordinateRegionMakeWithDistance(location.coordinate, 500, 500)
                    mapView2.setRegion(region, animated: true)
                    
                    mapView2.add(MKPolyline(coordinates: &coords, count: coords.count))
                    
                    if previousAlt == -1000{
                        previousAlt = location.altitude
                    }
                    if previousAlt < location.altitude{
                        vertClimb += location.altitude-previousAlt
                    }
                    if previousAlt > location.altitude{
                        vertDescent += previousAlt-location.altitude
                    }
                    previousAlt=location.altitude
                }
                
                //save location
                self.locations.append(location)
            }
        }
        
    }
    func centerMapOnLocation(location: CLLocation, distance: CLLocationDistance) {
        let regionRadius = distance
        let coordinateRegion = MKCoordinateRegionMakeWithDistance(location.coordinate,regionRadius * 2.0, regionRadius * 2.0)
        mapView2.setRegion(coordinateRegion, animated: true)
    }
    
    func saveRun() {
        // 1
        let savedRun = NSEntityDescription.insertNewObject(forEntityName: "Run",
                                                           into: managedObjectContext!) as! Run
        savedRun.distance = NSNumber(value: distance)
        savedRun.duration = (NSNumber(value: seconds))
        savedRun.timestamp = NSDate() as Date
        savedRun.climb = NSNumber(value: vertClimb)
        savedRun.descent = NSNumber(value: vertDescent)
        
        // 2
        var savedLocations = [Location]()
        for location in locations {
            let savedLocation = NSEntityDescription.insertNewObject(forEntityName: "Location",
                                                                    into: managedObjectContext!) as! Location
            savedLocation.timestamp = location.timestamp
            savedLocation.latitude = NSNumber(value: location.coordinate.latitude)
            savedLocation.longitude = NSNumber(value: location.coordinate.longitude)
            savedLocations.append(savedLocation)
        }
        
        savedRun.locations = NSOrderedSet(array: savedLocations)
        run = savedRun

        do{
            try managedObjectContext!.save()
        }catch{
            print("Could not save the run!")
        }
    }
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKPolyline {
            let polylineRenderer = MKPolylineRenderer(overlay: overlay)
            polylineRenderer.strokeColor = UIColor.blue
            polylineRenderer.lineWidth = 5
            return polylineRenderer
        }
        return MKOverlayRenderer()
    }
    func playSuccessSound() {
        let soundURL = Bundle.main.url(forResource: "success", withExtension: "wav")
        var soundID : SystemSoundID = 0
        AudioServicesCreateSystemSoundID(soundURL!as CFURL, &soundID)
        AudioServicesPlaySystemSound(soundID)
        
        //also vibrate
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate));
    }
    
    func checkNextBadge() {
        let nextBadge = BadgeController.sharedController.nextBadgeForDistance(distance: distance)
        
        if let upcomingBadge = upcomingBadge {
            if upcomingBadge.name! != nextBadge.name! {
                playSuccessSound()
            }
        }
        
        upcomingBadge = nextBadge
    }
}

// MARK: UIActionSheetDelegate
/*:extension NewRunViewController: UIActionSheetDelegate {
    private func actionSheet(_ actionSheet: UIAlertController, clickedButtonAt buttonIndex: Int) {
        //save
        if buttonIndex == 1 {
            saveRun()
            performSegue(withIdentifier: DetailSegueName, sender: nil)
        }
            //discard
        else if buttonIndex == 2 {
            navigationController?.popToRootViewController(animated: true)
        }
    }
} */
