/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The virtual chair.
*/

import Foundation
import ARKit

class Chair: VirtualObject {
	
	override init() {
		super.init(modelName: "neuer", fileExtension: "dae", thumbImageFilename: "ic_accessibility_48pt", title: "Manuel Neuer")
        
        self.scale = SCNVector3Make(0.001, 0.001, 0.001)
        
        let vecRotation = SCNVector3Make(1.0, 0, 0)
        self.rotation = SCNVector4Make(vecRotation.x, vecRotation.y, vecRotation.z, Float.pi/2.0)
        
        let vectorToCenter = self.position
        
        
        self.place2DImage(width: 0.5, vecNormal: self.position, vecToCenter: vectorToCenter, offsetHoriz: Float(0.0001), offsetVert: Float(-0.001), image: #imageLiteral(resourceName: "neuer-17"))
        
        
	}
	
	required init?(coder aDecoder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
    
    func place2DImage(width: CGFloat, vecNormal: SCNVector3, vecToCenter: SCNVector3, offsetHoriz: Float, offsetVert: Float, image: UIImage) {
        
        let height = width*image.size.height/image.size.width
        
        let plane = SCNPlane(width: width, height: height)
        plane.firstMaterial?.diffuse.contents = image
        // HOW TO PLACE AN VIDEO: https://stackoverflow.com/questions/42469024/how-do-i-create-a-looping-video-material-in-scenekit-on-ios-in-swift-3
        
        let planeNode = SCNNode()
        
        let vecOffsetVert = SCNVector3Make(0, offsetVert, 0)
        let vecOffsetHoriz = vecNormal.cross(vecOffsetVert).norm()*offsetHoriz
        
        planeNode.geometry = plane
        //planeNode.position = vecToCenter //CURRENT NORMAL VECTOR
        
        let vecRotation = vecToCenter.cross(vecNormal).norm()
        let angle = acos(vecToCenter.norm().dot(vecNormal.norm()))
        
        //planeNode.rotation = SCNVector4Make(vecRotation.x, vecRotation.y, vecRotation.z, angle)
        /*
        self.nodes.append(planeNode)
        self.sceneView.scene.rootNode.addChildNode(planeNode)*/
        self.addChildNode(planeNode)
    }
}
