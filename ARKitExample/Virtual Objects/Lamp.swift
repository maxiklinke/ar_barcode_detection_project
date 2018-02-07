/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The virtual lamp.
*/

import Foundation
import ARKit

class Lamp: VirtualObject {
	
	override init() {
		super.init(modelName: "pitch", fileExtension: "dae", thumbImageFilename: "ic_favorite", title: "Football pitch")
        
        self.scale = SCNVector3Make(0.0001, 0.0001, 0.0001)
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
