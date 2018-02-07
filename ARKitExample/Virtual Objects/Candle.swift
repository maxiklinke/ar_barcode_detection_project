/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The virtual candle.
*/

import Foundation
import SceneKit

class Candle: VirtualObject, ReactsToScale {
	
	override init() {
		super.init(modelName: "bars", fileExtension: "bae", thumbImageFilename: "ic_poll_48pt", title: "Statistics")
        
        self.scale = SCNVector3Make(100,100,100)//(0.01, 0.01, 0.01)
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	func reactToScale() {
		// Update the size of the flame
		let flameNode = self.childNode(withName: "flame", recursively: true)
		let particleSize: Float = 0.018
		flameNode?.particleSystems?.first?.reset()
		flameNode?.particleSystems?.first?.particleSize = CGFloat(self.scale.x * particleSize)
	}
}
