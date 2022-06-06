//
//  APODDataController.swift
//  APOD
//
//  Created by user220349 on 5/29/22.g//

import Foundation
import UIKit
import CoreData

enum MediaType {
    case none, image, video
}

protocol PODDelegate: AnyObject {
    func fetchedPicOfDayDetails(_ details: [String: Any?]?)
}

class APODDataController: NSObject {
    
    private static var pendingRequests = Set<NSURL>()
    private static var pendingRequestCallbacks = [URL: [((String) -> Void)]]()
    weak var podDelegate: PODDelegate?
    
    // On everytime date changes, fetch pic details for that date
    var date: String? = nil {
        didSet {
            guard date != oldValue else { return }
            handleNewDate()
        }
    }
    
    init(_ ds: String) {
        date = ds
        super.init()
        self.handleNewDate()
    }
    
    convenience override init() {
        self.init("")
    }
    
    func markFavorite() {
        guard let date = date, !date.isEmpty else { return }
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let managedContext = appDelegate.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Pics")
        fetchRequest.predicate = NSPredicate(format: "date = %@", date)
        
        do {
            let results = try managedContext.fetch(fetchRequest)
            if let result =  results.first as? NSManagedObject {
                let favorite = result.value(forKey: "favorite") as? Bool ?? false
                result.setValue(!favorite, forKey: "favorite")
                try managedContext.save()
                notifyPodDelegate(result)
            }
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func notifyPodDelegate(_ pod: NSManagedObject?) {
        guard let podDelegate = self.podDelegate else {
            return
        }
        guard let pod = pod else {
            DispatchQueue.main.async {
                podDelegate.fetchedPicOfDayDetails(nil)
            }
            return
        }
        guard pod.value(forKey: "date") as? String == date else { return }
        DispatchQueue.main.async {
            podDelegate.fetchedPicOfDayDetails(["date": pod.value(forKey: "date"),
                                                "title": pod.value(forKey: "title"),
                                                "explanation": pod.value(forKey: "explanation"),
                                                "media_type": pod.value(forKey: "media_type"),
                                                "url": pod.value(forKey: "url"),
                                                "thumbnail_url": pod.value(forKey: "thumbnail_url"),
                                                "favorite": pod.value(forKey: "favorite") as? Bool,
                                               ])
        }
        
    }
    
    func handleNewDate() {
        guard let date = date else { return }
        self.notifyPodDelegate(nil)
        fetchapod(date: date) { [weak self] (pod: NSManagedObject) in
            guard let asset_url = pod.value(forKey: "url") as? String, let asset = URL(string: asset_url) as? NSURL else { return }
            let handleResourceFetchCompletion = { [weak self] (pod: NSManagedObject) in
                DispatchQueue.main.async {
                    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
                    self?.notifyPodDelegate(pod)
                    let managedContext = appDelegate.persistentContainer.viewContext
                    do {
                        try managedContext.save()
                    } catch let error as NSError {
                        print("Error: \(error.localizedDescription)")
                    }
                }
            }
            if pod.value(forKey: "media_type") as? String == "image" {
                self?.handlePODAsset(asset) { (filePath: String) in
                    pod.setValue(filePath, forKey: "url")
                    handleResourceFetchCompletion(pod)
                }
            }
            
            // Note: only for media_type video, thumbnail_url exist
            guard let thumbnail_url = pod.value(forKey: "thumbnail_url") as? String, let thumbnail = URL(string: thumbnail_url) as? NSURL else { return }
            self?.handlePODAsset(thumbnail) { (filePath: String) in
                pod.setValue(filePath, forKey: "thumbnail_url")
                handleResourceFetchCompletion(pod)
            }
        }
    }
    
    func handlePODAsset(_ url: NSURL, _ completion: @escaping ((String) -> Void)) {
        if url.isFileURL, let filePath = url.absoluteString {
            completion(filePath)
            return
        }
        
        guard APODDataController.pendingRequests.contains(url) == false else {
            DispatchQueue.main.async {
                var callbacks = APODDataController.pendingRequestCallbacks[url as URL] ?? []
                callbacks.append(completion)
                APODDataController.pendingRequestCallbacks[url as URL] = callbacks
            }
            return
        }
        
        DispatchQueue.main.async {
            APODDataController.pendingRequests.insert(url)
        }
        
        // Fetch the resource.
        ImageURLProtocol.urlSession().dataTask(with: url as URL) { (data, response, error) in
            // Check for the error, then data and try to create the image.
            guard error == nil, let responseData = data else {
                return
            }
            do {
                DispatchQueue.main.async {
                    APODDataController.pendingRequests.remove(url)
                }
                guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else { return }
                
                if let filePath = json["filePath"] as? String {
                    completion(filePath)
                    if let callbacks = APODDataController.pendingRequestCallbacks[url as URL] {
                        for callback in callbacks {
                            callback(filePath)
                        }
                        DispatchQueue.main.async {
                            APODDataController.pendingRequestCallbacks[url as URL] = nil
                        }
                    }
                }
            } catch {
                print(error)
            }
        }.resume()
    }
    
    // remove this
    func clearPersistentStore() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let managedContext = appDelegate.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Pics")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        do {
            try managedContext.execute(deleteRequest)
            try managedContext.save()
            
            print("cleared persitent store")
        } catch let error {
            print(error.localizedDescription)
        }
    }
    
    func fetchapod(date: String, _ podCallback: @escaping ((NSManagedObject) -> Void)) {
        DispatchQueue.main.async {
            guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
            let managedContext = appDelegate.persistentContainer.viewContext
            
            let findLocal = { (dt: String) -> NSManagedObject? in
                // Look for pic of day details for the date in local data
                // Note: empty date represents fetching default pic of the day, i.e not selected by user
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Pics")
                fetchRequest.predicate = NSPredicate(format: "date = %@", dt)
                
                do {
                    let result = try managedContext.fetch(fetchRequest)
                    return result.first as? NSManagedObject
                } catch {
                    print(error.localizedDescription)
                }
                return nil
            }
            
            if !date.isEmpty, let pod = findLocal(date) {
                podCallback(pod)
                return
            }
            
            //
            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config)
            
            let api_url = "https://api.nasa.gov/planetary/apod?api_key=QIunBvxWbZ79q2C5OEdUuWKrRPUKHSRfhyShy5Re&date=\(date)&thumbs=true"
            guard let url = URL(string: api_url) else { return }
            
            let urlRequest = URLRequest(url: url)
            
            let task = session.dataTask(with: urlRequest) { data, response, error in
                
                // ensure there is no error for this HTTP response
                guard error == nil else {
                    print ("error: \(error!)")
                    return
                }
                
                // ensure there is data returned from this HTTP response
                guard let content = data else {
                    print("No data")
                    return
                }
                
                // serialise the data / NSData object into Dictionary [String : Any]
                guard let json = (try? JSONSerialization.jsonObject(with: content, options: JSONSerialization.ReadingOptions.mutableContainers)) as? [String: Any] else {
                    print("Not containing JSON")
                    return
                }
            
                if date.isEmpty, let dt = json["date"] as? String, let pod = findLocal(dt) {
                    self.date = dt
                    podCallback(pod)
                    return
                }
                // insert new pic entry in core data managed context
                guard let picEntiry = NSEntityDescription.entity(forEntityName: "Pics", in: managedContext) else { return }
                
                let newPic = NSManagedObject(entity: picEntiry, insertInto: managedContext)
                newPic.setValue(json["date"], forKey: "date")
                newPic.setValue(json["explanation"], forKey: "explanation")
                newPic.setValue(json["media_type"], forKey: "media_type")
                newPic.setValue(json["title"], forKey: "title")
                newPic.setValue(json["url"], forKey: "url")
                newPic.setValue(json["thumbnail_url"], forKey: "thumbnail_url")
                podCallback(newPic)
                
                do {
                    try managedContext.save()
                } catch let error as NSError {
                    print("Error: \(error.localizedDescription)")
                }
            }

            // execute the HTTP request
            task.resume()
        }
    }
}
