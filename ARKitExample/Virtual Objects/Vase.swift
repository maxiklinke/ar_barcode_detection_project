/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The virtual vase.
*/

import Foundation
import ARKit

class Vase: VirtualObject {
	
	override init() {
		super.init(modelName: "arena", fileExtension: "dae", thumbImageFilename: "ic_favorite", title: "Allianz Arena")
        
        self.scale = SCNVector3Make(0.00005, 0.00005, 0.00005)
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
