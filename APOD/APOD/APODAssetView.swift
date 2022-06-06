//
//  APODAssetView.swift
//  APOD
//
//  Created by user220349 on 5/29/22.
//

import Foundation
import UIKit
import AVKit


class APODAssetView: UIView {
    @IBOutlet var loading: UIActivityIndicatorView?
    @IBOutlet var imageView: UIImageView?
    
    private var videoPlayer: AVPlayer?
    private var playerViewController: AVPlayerViewController?
    
    @objc func videoEnded() {
        NotificationCenter.default.removeObserver(self)
        
        UIView.animate(withDuration: 1.0, delay: 0, options: .curveEaseInOut) {
            self.imageView?.isHidden = false
            if let playerView = self.playerViewController?.view {
                playerView.removeFromSuperview()
            }

        } completion: { success in
        }
    }
    
    func loadResource(type: MediaType = .none, url: URL?) {
        guard let fileURL = url else {
            imageView?.image = nil
            imageView?.isHidden = false
            loading?.startAnimating()
            if let playerView = self.playerViewController?.view, playerView.superview != nil {
                self.videoPlayer?.removeObserver(self, forKeyPath: "status")
                playerView.removeFromSuperview()
            }
            return
        }
        loading?.stopAnimating()
        
        if type == .image  {
            if let data = FileManager.default.contents(atPath: fileURL.path) {
	                imageView?.image = UIImage(data: data)
            } else {
                print("Image not found")
            }
        } else if type == .video {
                self.videoPlayer = AVPlayer(url: fileURL)
                self.playerViewController = AVPlayerViewController()
                self.playerViewController?.player = self.videoPlayer
                self.playerViewController?.view.frame = self.bounds
                self.videoPlayer?.addObserver(self, forKeyPath: "status", options: .new, context: nil)
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        let player = object as! AVPlayer
        if keyPath == "status", player.status == .readyToPlay {
            UIView.animate(withDuration: 1.0, delay: 0, options: .curveEaseInOut) {
                self.imageView?.isHidden = true
                if let playerView = self.playerViewController?.view {
                    self.addSubview(playerView)
                }

            } completion: { success in
                self.playerViewController?.player?.play()
                NotificationCenter.default.addObserver(self, selector: #selector(self.videoEnded), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.videoPlayer)
            }
        } else if player.status == .failed {
            
        }
    }
}
