//
//  ViewController.swift
//  BitFit
//x
//  Created by Michael Dales on 19/05/2019.
//  Copyright © 2019 Digital Flapjack Ltd. All rights reserved.
//

import UIKit
import HealthKit
import CoreLocation
import AVKit

class RecordWorkoutViewController: UIViewController {

    @IBOutlet weak var toggleButton: UIButton!
    @IBOutlet weak var distanceLabel: UILabel!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var activityButton: UIButton!
    
    let splitDistance = 1609.34
    var splits = [Date]()
    
    let syncQ = DispatchQueue(label: "workout")
    
    let synthesizer = AVSpeechSynthesizer()
    let healthStore = HKHealthStore()
    
    let locationManager = CLLocationManager()
    var workoutBuilder: HKWorkoutBuilder?
    var routeBuilder: HKWorkoutRouteBuilder?
    
    var lastLocation: CLLocation?
    var distance: CLLocationDistance = 0.0
    
    var activityType = HKWorkoutActivityType.running
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        synthesizer.delegate = self
        
        locationManager.delegate = self
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        locationManager.requestAlwaysAuthorization()
        
        let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        
        let healthKitTypesToWrite: Set<HKSampleType> = [distanceType!, HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        
        healthStore.requestAuthorization(toShare: healthKitTypesToWrite, read: nil) { (success, error) in
            
            if let err = error {
                print("Failed to auth health store: \(err)")
                return
            }
            
            if !success {
                print("health store auth wasn't a success")
                return
            }
        }
    }
    
    @IBAction func changeActivity(_ sender: Any) {
        
        if activityType == .running {
            activityType = .cycling
            activityButton.setImage(UIImage(named:"Cycling"), for: .normal)
            print("cycling!")
        } else {
            activityType = .running
            activityButton.setImage(UIImage(named:"Running"), for: .normal)
            print("running!")
        }
    }
    
    @IBAction func toggleWorkout(_ sender: Any) {
        
        if workoutBuilder == nil {
            let alert = UIAlertController(title: "Start workout",
                                          message: "Are you sure you wish to start a workout?",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                self.startWorkout()
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
            
        } else {
            let alert = UIAlertController(title: "Stop workout",
                                          message: "Are you sure you wish to stop the workout?",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                self.stopWorkout()
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    func startWorkout() {
        
        print("Starting workout")
        
        assert(routeBuilder == nil)
        
        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = .outdoor
        
        workoutBuilder = HKWorkoutBuilder(healthStore: healthStore,
                                          configuration: config,
                                          device: nil)
        
        workoutBuilder?.beginCollection(withStart: Date(), completion: { (success, error) in
            
            if let err = error {
                print("Failed to begin workout: \(err)")
                return
            }
            
            if !success {
                print("Beginning wasn't a success")
                return
            }
            
            HKSeriesType.workoutRoute()
            self.routeBuilder = HKWorkoutRouteBuilder(healthStore: self.healthStore, device: nil)
            
            self.lastLocation = nil
            self.distance = 0.0
            self.locationManager.startUpdatingLocation()
                                        
        })
        
        
        toggleButton.setTitle("Stop", for: .normal)
        activityButton.isEnabled = false
    }
    
    func stopWorkout() {
        
        print("Stopping workout")
        
        guard let workoutBuilder = self.workoutBuilder else {
            return
        }
        
        locationManager.stopUpdatingLocation()
        
        let endDate = Date()
        
        let distanceQuantity = HKQuantity(unit: HKUnit.meter(), doubleValue: distance)
        let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)
        let distanceSample = HKQuantitySample(type: distanceType!, quantity: distanceQuantity,
                                              start: workoutBuilder.startDate!, end: endDate)
        
        workoutBuilder.add([distanceSample]) { (success, error) in
            
            if let err = error {
                print("Failed to add sample: \(err)")
                return
            }
            
            if !success {
                print("adding sample wasn't a success")
                return
            }
        }
        
        workoutBuilder.endCollection(withEnd: endDate) { (success, error) in
            
            if let err = error {
                print("Failed to end workout: \(err)")
                return
            }
            
            if !success {
                print("Ending wasn't a success")
                return
            }
            
            workoutBuilder.finishWorkout { (workout, error) in
                
                if let err = error {
                    print("Failed to finish workout: \(err)")
                    return
                }
                
                guard let finishedWorkout = workout else {
                    print("Failde to get workout")
                    return
                }
                
                guard let routeBuilder = self.routeBuilder else {
                    print("Failed to get route builder")
                    return
                }
                
                routeBuilder.finishRoute(with: finishedWorkout, metadata: nil, completion: { (route, error) in
                    if let err = error {
                        print("Failed to finish route: \(err)")
                    }
                })
                
                self.workoutBuilder = nil
                self.routeBuilder = nil
            }
        }
        toggleButton.setTitle("Start", for: .normal)
        activityButton.isEnabled = true
    }
}


extension RecordWorkoutViewController: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        guard let builder = routeBuilder else {
            return
        }
        
        print("Inserting location data")
        
        for location in locations {
            if let last = lastLocation {
                distance += location.distance(from: last)
            }
            lastLocation = location
        }
        
        if distance > (splitDistance * Double(splits.count + 1)) {
            
            let now = Date()
            splits.append(now)
            
            let miles = distance / splitDistance
            let start = self.workoutBuilder!.startDate!
            let duration = now.timeIntervalSince(start)
            let minutes = Int(duration / 60.0)
            let seconds = Int(duration) - (minutes * 60)
            
            DispatchQueue.main.async {
                self.distanceLabel.text = String(format: "%.1f miles", miles)
                self.durationLabel.text = String(format: "%d minutes and %d seconds", minutes, seconds)
                
                let audioSession = AVAudioSession.sharedInstance()
                do {
                    try audioSession.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
                    try audioSession.setActive(true)
                } catch {
                    print("Failed to duck other sounds")
                }
                
                
                let part1 = AVSpeechUtterance(string: self.distanceLabel.text! + " " + self.durationLabel.text!)
                self.synthesizer.speak(part1)
            }
        }
        
        builder.insertRouteData(locations) { (success, error) in
            if let err = error {
                print("Failed to insert data! \(err)")
            } else if !success {
                print("Failed to insert data")
            }
        }
    }
}


extension RecordWorkoutViewController: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false)
    }
    
}
