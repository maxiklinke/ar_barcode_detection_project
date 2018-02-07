/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The virtual cup.
*/

import Foundation
import ARKit

class Cup: VirtualObject {
	
	override init() {
		super.init(modelName: "robben", fileExtension: "dae", thumbImageFilename: "ic_accessibility_48pt", title: "Arien Robben")
        
        self.scale = SCNVector3Make(0.01, 0.01, 0.01)
        
        let vecRotation = SCNVector3Make(1.0, 0, 0)
        self.rotation = SCNVector4Make(vecRotation.x, vecRotation.y, vecRotation.z, Float.pi/2.0)
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
