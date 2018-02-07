//
//  VideoStream.swift
//  ARKitExample
//
//  Created by Maximilian Klinke on 20.01.18.
//  Copyright © 2018 Apple. All rights reserved.
//

import Foundation
import ARKit

class VideoStream: SCNPlane {
    
    override init() {
        super.init()
        //DO NOTHING
    }
    
    init(viewController: ViewController) {
        super.init()
        
        let sceneView = viewController.sceneView!
        
        // A SpriteKit scene to contain the SpriteKit video node
        let spriteKitScene = SKScene(size: CGSize(width: sceneView.frame.width, height: sceneView.frame.height))
        spriteKitScene.scaleMode = .aspectFit
        
        // Create a video player, which will be responsible for the playback of the video material
        let videoUrl = URL(string: "http://dl.mnac-s-000000136.c.nmdn.net/mnac-s-000000136/20180120/0/0_21ptf6zo_0_tkgz11l3_2.mp4")!
        //Bundle.main.url(forResource: "videos/video", withExtension: "mp4")!
        let videoPlayer = AVPlayer(url: videoUrl)
        
        // To make the video loop
        videoPlayer.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(viewController.playerItemDidReachEnd),
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: videoPlayer.currentItem)
        
        // Create the SpriteKit video node, containing the video player
        let videoSpriteKitNode = SKVideoNode(avPlayer: videoPlayer)
        videoSpriteKitNode.position = CGPoint(x: spriteKitScene.size.width / 2.0, y: spriteKitScene.size.height / 2.0)
        videoSpriteKitNode.size = spriteKitScene.size
        videoSpriteKitNode.yScale = -1.0
        videoSpriteKitNode.play()
        spriteKitScene.addChild(videoSpriteKitNode)
        
        //sceneView.background.firstMaterial?.diffuse.contents = spriteKitScene
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
