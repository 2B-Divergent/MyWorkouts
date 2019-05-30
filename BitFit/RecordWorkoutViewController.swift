//
//  ViewController.swift
//  BitFit
//
//  Created by Michael Dales on 19/05/2019.
//  Copyright © 2019 Digital Flapjack Ltd. All rights reserved.
//

import UIKit
import HealthKit
import AVKit
import os.log

class RecordWorkoutViewController: UIViewController {

    @IBOutlet weak var toggleButton: UIButton!
    @IBOutlet weak var activityButton: UIButton!
    @IBOutlet weak var splitsTableView: UITableView!
    
    let synthesizer = AVSpeechSynthesizer()
    
    var updateTimer: Timer? = nil
    var workoutTracker: WorkoutTracker?
    
    var activityTypeIndex = 0
    
    var latestSplits = [WorkoutSplit]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        synthesizer.delegate = self
        
        activityTypeIndex = UserDefaults.standard.integer(forKey: "LastActivityIndex")
        
        let activityType = WorkoutTracker.supportedWorkouts[activityTypeIndex]
        activityButton.setImage(UIImage(named:activityType.String()), for: .normal)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.locationManager.requestAlwaysAuthorization()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } catch {
            print("Failed to duck other sounds")
        }
    }
    
    @IBAction func changeActivity(_ sender: Any) {
        
        activityTypeIndex = (activityTypeIndex + 1) % WorkoutTracker.supportedWorkouts.count
        UserDefaults.standard.set(activityTypeIndex, forKey: "LastActivityIndex")
        
        let activityType = WorkoutTracker.supportedWorkouts[activityTypeIndex]
        activityButton.setImage(UIImage(named:activityType.String()), for: .normal)
    }
    
    @IBAction func toggleWorkout(_ sender: Any) {
        
        if workoutTracker == nil {
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
        
        assert(workoutTracker == nil)
        assert(updateTimer == nil)
        
        latestSplits = [WorkoutSplit]()
        
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        
        let activityType = WorkoutTracker.supportedWorkouts[activityTypeIndex]
        let splitDistance = WorkoutTracker.getDistanceUnitSetting() == .Miles ? 1609.34 : 1000.0
        let workout = WorkoutTracker(activityType: activityType,
                                     splitDistance: splitDistance / 10,
                                     locationManager: appDelegate.locationManager,
                                     splitsUpdateCallback: { splits, final in
                                        DispatchQueue.main.async {
                                            
                                            print(String(format: "%@: %@", final ? "true" : "false", splits))
                                            
                                            self.latestSplits = splits
                                            if self.latestSplits.count > 1 {
                                                self.splitsTableView.insertRows(at: [IndexPath(row: 0, section: 1)], with: .top)
                                            } else {
                                                self.splitsTableView.reloadData()
                                            }
                                            
                                            if splits.count < 2 {
                                                return
                                            }
                                            
                                            let latestSplit = splits[splits.count - 1]
                                            let priorSplit = splits[final ? 0 : splits.count - 2]

                                            let splitDuration = latestSplit.time.timeIntervalSince(priorSplit.time)
                                            let splitDistance = latestSplit.distance - priorSplit.distance

                                            var phrase = final ? "Total " : ""

                                            let formatter = DateComponentsFormatter()
                                            formatter.allowedUnits = [.hour, .minute, .second]
                                            formatter.unitsStyle = .full
                                            let durationPhrase = formatter.string(from: splitDuration)!

                                            let units = WorkoutTracker.getDistanceUnitSetting()
                                            switch units {
                                            case .Miles:
                                                let distance = splitDistance / 1609.34
                                                phrase = String(format: "%@ Distance %.2f miles. Time %@", phrase, distance, durationPhrase)
                                            case .Kilometers:
                                                let distance = splitDistance / 1000.0
                                                phrase = String(format: "%@ Distance %.2f kilometers. Time %@", phrase, distance, durationPhrase)
                                            }

                                            let spokenPhrase = AVSpeechUtterance(string: phrase)

                                            let audioSession = AVAudioSession.sharedInstance()
                                            try? audioSession.setActive(true)
                                            self.synthesizer.speak(spokenPhrase)
                                        }
        })
        workoutTracker = workout
        
        do {
            try workout.startWorkout(healthStore: appDelegate.healthStore) { (error) in
                if let err = error {
                    print("Failed to start workout: \(err)")
                    return
                }
                
                DispatchQueue.main.async {
                    self.toggleButton.setTitle("Stop", for: .normal)
                    self.activityButton.isEnabled = false
                    self.splitsTableView.reloadData()
                    
                    self.updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { _ in
                        
                        DispatchQueue.main.async {
                            let set = IndexSet([0])
                            self.splitsTableView.reloadSections(set, with: .none)
                        }
                        
                    })
                }
            }
        } catch {
            print("Failed to start workout: \(error)")
        }
    }
    
    func stopWorkout() {
        
        dispatchPrecondition(condition: .onQueue(DispatchQueue.main))
        
        print("Stopping workout")
        
        if let timer = updateTimer {
            timer.invalidate()
            updateTimer = nil
        }
        
        guard let workout = workoutTracker else {
            return
        }
        
        workout.stopWorkout { (error) in
            if let err = error {
                print("Error stopping workout: \(err)")
            }
            
//            let duration = endDate.timeIntervalSince(finishedWorkout.startDate)
//            let minutes = Int(duration / 60.0)
//            let seconds = Int(duration) - (minutes * 60)
//            var completionProse = "Workout completed. Time \(minutes) minutes and \(seconds) seconds. "
//
//            if let distanceQuantity = finishedWorkout.totalDistance {
//                let distance = distanceQuantity.doubleValue(for: .mile())
//                let distanceProse = String(format: " %.2f miles", distance)
//                completionProse += distanceProse
//            }
//
//            let completePhrase = AVSpeechUtterance(string: completionProse)
            
            DispatchQueue.main.async {
                self.workoutTracker = nil
                //self.synthesizer.speak(completePhrase)
                self.toggleButton.setTitle("Start", for: .normal)
                self.activityButton.isEnabled = true
                self.splitsTableView.reloadData()
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

extension RecordWorkoutViewController: UITableViewDelegate {
}

extension RecordWorkoutViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        if let workout = workoutTracker {
            if workout.isRunning {
                return 2
            }
        }
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        var currentSection = false
        if let workout = workoutTracker {
            if workout.isRunning {
                if section == 0 {
                    currentSection = true
                }
            }
        }
        
        if currentSection {
            return 1
        } else {
            return latestSplits.count > 0 ? latestSplits.count - 1 : 0
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        var currentSection = false
        if let workout = workoutTracker {
            if workout.isRunning {
                if section == 0 {
                    currentSection = true
                }
            }
        }
        
        if currentSection {
            return "Current"
        } else {
            return "Splits"
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "splitsReuseIdentifier", for: indexPath)
        
        if latestSplits.count == 0 {
            return cell
        }
        
        var currentSection = false
        if let workout = workoutTracker {
            if workout.isRunning {
                if indexPath.section == 0 {
                    currentSection = true
                }
            }
        }
        
        if currentSection {
            
            guard let workout = workoutTracker else {
                return cell
            }
            
            let firstSplit = latestSplits[0]
            
            let splitDuration = Date().timeIntervalSince(firstSplit.time)
            
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second, .nanosecond]
            formatter.unitsStyle = .abbreviated
            cell.textLabel?.text = formatter.string(from: splitDuration)
            
            let units = WorkoutTracker.getDistanceUnitSetting()
            switch units {
            case .Miles:
                let distance = workout.estimatedDistance / 1609.34
                cell.detailTextLabel?.text = String(format: "%.2f miles", distance)
            case .Kilometers:
                let distance = workout.estimatedDistance / 1000.0
                cell.detailTextLabel?.text = String(format: "%.2f km", distance)
            }
            
            return cell
        } else {
            
            let index = (latestSplits.count - 1) - indexPath.row
        
            let split = latestSplits[index]
            let firstSplit = latestSplits[0]
            
            let splitDuration = split.time.timeIntervalSince(firstSplit.time)
            
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute, .second, .nanosecond]
            formatter.unitsStyle = .abbreviated
            cell.textLabel?.text = formatter.string(from: splitDuration)
            
            let units = WorkoutTracker.getDistanceUnitSetting()
            switch units {
            case .Miles:
                let distance = split.distance / 1609.34
                cell.detailTextLabel?.text = String(format: "%.2f miles", distance)
            case .Kilometers:
                let distance = split.distance / 1000.0
                cell.detailTextLabel?.text = String(format: "%.2f km", distance)
            }
            
            return cell
        }
    }
    
}
