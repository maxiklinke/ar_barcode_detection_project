//
//  VideoViewController.swift
//  ARKitExample
//
//  Created by Maximilian Klinke on 20.01.18.
//  Copyright © 2018 Apple. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

class VideoViewController: UIViewController {
    
    @IBOutlet var imageView: UIImageView!
    
    override func viewDidAppear(_ animated: Bool) {
        
        let videoUrl = Bundle.main.url(forResource: "video", withExtension: "mp4")
        let videoPlayer = AVPlayer(url: videoUrl!)
        
        
        // To make the video loop
        videoPlayer.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.playerItemDidReachEnd),
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: videoPlayer.currentItem)
        
        
        let videoLayer = AVPlayerLayer(player: videoPlayer)
        videoLayer.frame = self.view.bounds
        videoLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        self.imageView.layer.addSublayer(videoLayer)
        
        videoPlayer.play()
        
    }
    
    // This callback will restart the video when it has reach its end
    @objc func playerItemDidReachEnd(notification: NSNotification) {
        if let playerItem: AVPlayerItem = notification.object as? AVPlayerItem {
            playerItem.seek(to: kCMTimeZero)
        }
    }
    
}
