//
//  ImgeURLProtocol.swift
//  APOD
//
//  Created by user220349 on 5/29/22.

import UIKit

class ImageURLProtocol: URLProtocol {

    var cancelledOrComplete: Bool = false
    var block: DispatchWorkItem!
    
    private static let queue = OS_dispatch_queue_serial(label: "com.apple.imageLoaderURLProtocol")
    
    // Mark: - Utility variable
    
    public static var documentsDirectory: String = {
        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
        let documentsDirectory: String = paths[0]
        return documentsDirectory
    }()
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    class override func requestIsCacheEquivalent(_ aRequest: URLRequest, to bRequest: URLRequest) -> Bool {
        return false
    }
    
    final override func startLoading() {
        guard let reqURL = request.url, let urlClient = client else {
            return
        }
        
        block = DispatchWorkItem(block: {
            if self.cancelledOrComplete == false {
                let targetPath = "podAssets" + reqURL.path
                let targetURL = URL(fileURLWithPath: ImageURLProtocol.documentsDirectory + "/" + targetPath)
                do {
                    if let data = try? Data(contentsOf: reqURL) {
                        // Copy the file from temp directory to document directory path
                        try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: targetURL)
                        let fPath = URL(fileURLWithPath: targetPath).absoluteString
                        let filePath = ["filePath": fPath]
                        
                        let data = try JSONSerialization.data(withJSONObject: filePath, options: .fragmentsAllowed)
                        urlClient.urlProtocol(self, didLoad: data)
                        urlClient.urlProtocolDidFinishLoading(self)
                    }
                } catch let error {
                    print("Unable to copy file: \(error.localizedDescription)")
                }
            }
            self.cancelledOrComplete = true
        })
        
        ImageURLProtocol.queue.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: 500 * NSEC_PER_MSEC), execute: block)
    }
    
    final override func stopLoading() {
        ImageURLProtocol.queue.async {
            if self.cancelledOrComplete == false, let cancelBlock = self.block {
                cancelBlock.cancel()
                self.cancelledOrComplete = true
            }
        }
    }
    
    static func urlSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImageURLProtocol.classForCoder()]
        return  URLSession(configuration: config)
    }
    
    static func fileURL(with filePath: String?) -> URL? {
        guard let path = filePath, let fileURL = URL(string: path) else { return nil }
        let filePath = ImageURLProtocol.documentsDirectory.appending(fileURL.path)
        return URL(fileURLWithPath: filePath)
    }
}

