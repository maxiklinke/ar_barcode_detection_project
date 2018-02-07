/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import ARKit
import Foundation
import SceneKit
import UIKit
import Photos

import Vision

class ViewController: UIViewController, ARSCNViewDelegate, UIPopoverPresentationControllerDelegate, VirtualObjectSelectionViewControllerDelegate, SCNSceneRendererDelegate {
	
    // MARK: - Main Setup & View Controller methods
    override func viewDidLoad() {
        super.viewDidLoad()

        Setting.registerDefaults()
        setupScene()
        setupDebug()
        setupUIControls()
		setupFocusSquare()
		updateSettings()
		resetVirtualObjectAll()
        
        self.prepareFirst()
    }

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
		// Prevent the screen from being dimmed after a while.
		UIApplication.shared.isIdleTimerDisabled = true
		
		// Start the ARSession.
		restartPlaneDetection()
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		session.pause()
	}
	
    // MARK: - ARKit / ARSCNView
    let session = ARSession()
    let sessionConfig = ARWorldTrackingConfiguration()
	/*var sessionConfig: ARSessionConfiguration = ARWorldTrackingSessionConfiguration()
	var use3DOFTracking = false {
		didSet {
			if use3DOFTracking {
				sessionConfig = ARSessionConfiguration()
			}
			sessionConfig.isLightEstimationEnabled = UserDefaults.standard.bool(for: .ambientLightEstimation)
			session.run(sessionConfig)
		}
	}*/
    
    
    
	var use3DOFTrackingFallback = false
    @IBOutlet var sceneView: ARSCNView!
	var screenCenter: CGPoint?
    
    func setupScene() {
        // set up sceneView
        sceneView.delegate = self
        sceneView.session = session
		sceneView.antialiasingMode = .multisampling4X
		sceneView.automaticallyUpdatesLighting = false
		
		sceneView.preferredFramesPerSecond = 60
		sceneView.contentScaleFactor = 1.3
		//sceneView.showsStatistics = true
		
		enableEnvironmentMapWithIntensity(25.0)
		
		DispatchQueue.main.async {
			self.screenCenter = self.sceneView.bounds.mid
		}
		
		if let camera = sceneView.pointOfView?.camera {
			camera.wantsHDR = true
			camera.wantsExposureAdaptation = true
			camera.exposureOffset = -1
			camera.minimumExposure = -1
		}
    }
	
	func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
		if sceneView.scene.lightingEnvironment.contents == nil {
			if let environmentMap = UIImage(named: "Models.scnassets/sharedImages/environment_blur.exr") {
				sceneView.scene.lightingEnvironment.contents = environmentMap
			}
		}
		sceneView.scene.lightingEnvironment.intensity = intensity
	}
	
    // MARK: - ARSCNViewDelegate
	
	func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
		refreshFeaturePoints()
		
		DispatchQueue.main.async {
			self.updateFocusSquare()
			self.hitTestVisualization?.render()
			
			// If light estimation is enabled, update the intensity of the model's lights and the environment map
			if let lightEstimate = self.session.currentFrame?.lightEstimate {
				self.enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 40)
			} else {
				self.enableEnvironmentMapWithIntensity(25)
			}
		}
	}
	
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
				self.addPlane(node: node, anchor: planeAnchor)
                self.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor)
            }
        }
    }
	
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.updatePlane(anchor: planeAnchor)
                self.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor)
            }
        }
    }
	
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.removePlane(anchor: planeAnchor)
            }
        }
    }
	
	var trackingFallbackTimer: Timer?

	func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        textManager.showTrackingQualityInfo(for: camera.trackingState, autoHide: !self.showDebugVisuals)

        switch camera.trackingState {
        case .notAvailable:
            textManager.escalateFeedback(for: camera.trackingState, inSeconds: 5.0)
        case .limited:
            if use3DOFTrackingFallback {
                // After 10 seconds of limited quality, fall back to 3DOF mode.
                trackingFallbackTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false, block: { _ in
                    //---------------------------------------------------------------------self.use3DOFTracking = true
                    self.trackingFallbackTimer?.invalidate()
                    self.trackingFallbackTimer = nil
                })
            } else {
                textManager.escalateFeedback(for: camera.trackingState, inSeconds: 10.0)
            }
        case .normal:
            textManager.cancelScheduledMessage(forType: .trackingStateEscalation)
            if use3DOFTrackingFallback && trackingFallbackTimer != nil {
                trackingFallbackTimer!.invalidate()
                trackingFallbackTimer = nil
            }
        }
	}
	
    func session(_ session: ARSession, didFailWithError error: Error) {

        guard let arError = error as? ARError else { return }

        let nsError = error as NSError
		var sessionErrorMsg = "\(nsError.localizedDescription) \(nsError.localizedFailureReason ?? "")"
		if let recoveryOptions = nsError.localizedRecoveryOptions {
			for option in recoveryOptions {
				sessionErrorMsg.append("\(option).")
			}
		}

        let isRecoverable = (arError.code == .worldTrackingFailed)
		if isRecoverable {
			sessionErrorMsg += "\nYou can try resetting the session or quit the application."
		} else {
			sessionErrorMsg += "\nThis is an unrecoverable error that requires to quit the application."
		}
		
		displayErrorMessage(title: "We're sorry!", message: sessionErrorMsg, allowRestart: isRecoverable)
	}
	
	func sessionWasInterrupted(_ session: ARSession) {
		textManager.blurBackground()
		textManager.showAlert(title: "Session Interrupted", message: "The session will be reset after the interruption has ended.")
	}
		
	func sessionInterruptionEnded(_ session: ARSession) {
		textManager.unblurBackground()
		session.run(sessionConfig, options: [.resetTracking, .removeExistingAnchors])
		restartExperience(self)
		textManager.showMessage("RESETTING SESSION")
	}
	
    // MARK: - Ambient Light Estimation
	
	func toggleAmbientLightEstimation(_ enabled: Bool) {
		
        if enabled {
			if !sessionConfig.isLightEstimationEnabled {
				// turn on light estimation
				sessionConfig.isLightEstimationEnabled = true
				session.run(sessionConfig)
			}
        } else {
			if sessionConfig.isLightEstimationEnabled {
				// turn off light estimation
				sessionConfig.isLightEstimationEnabled = false
				session.run(sessionConfig)
			}
        }
    }

    // MARK: - Gesture Recognizers
	
	var currentGesture: Gesture?
	
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		guard let object = virtualObjectToMove else {
			return
		}
        
		
		if currentGesture == nil {
			currentGesture = Gesture.startGestureFromTouches(touches, self.sceneView, object)
		} else {
			currentGesture = currentGesture!.updateGestureFromTouches(touches, .touchBegan)
		}
		
		displayVirtualObjectTransform()
	}
	
	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		if virtualObjectToMove == nil {
			return
		}
		currentGesture = currentGesture?.updateGestureFromTouches(touches, .touchMoved)
		displayVirtualObjectTransform()
	}
	
	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		if virtualObjectToMove == nil {
			//chooseObject(addObjectButton)
			return
		}
		
		currentGesture = currentGesture?.updateGestureFromTouches(touches, .touchEnded)
	}
	
	override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
		if virtualObjectToMove == nil {
			return
		}
		currentGesture = currentGesture?.updateGestureFromTouches(touches, .touchCancelled)
	}
	
	// MARK: - Virtual Object Manipulation
	
	func displayVirtualObjectTransform() {
		
		guard let object = virtualObjectToMove, let cameraTransform = session.currentFrame?.camera.transform else {
			return
		}
		
		// Output the current translation, rotation & scale of the virtual object as text.
		
		let cameraPos = SCNVector3.positionFromTransform(cameraTransform)
		let vectorToCamera = cameraPos - object.position
		
		let distanceToUser = vectorToCamera.length()
		
		var angleDegrees = Int(((object.eulerAngles.y) * 180) / Float.pi) % 360
		if angleDegrees < 0 {
			angleDegrees += 360
		}
		
		let distance = String(format: "%.2f", distanceToUser)
		let scale = String(format: "%.2f", object.scale.x)
		textManager.showDebugMessage("Distance: \(distance) m\nRotation: \(angleDegrees)°\nScale: \(scale)x")
	}
	
    
	func moveVirtualObjectToPosition(_ pos: SCNVector3?, _ instantly: Bool, _ filterPosition: Bool) {
		
		guard let newPosition = pos else {
			textManager.showMessage("CANNOT PLACE OBJECT\nTry moving left or right.")
			// Reset the content selection in the menu only if the content has not yet been initially placed.
			/*if virtualObjectToMove == nil {-------------------------------------------------------------------
                resetVirtualObject()
			}*/
			return
		}
		
		if instantly {
            setNewVirtualObjectPosition(newPosition, virtualObject: virtualObjects.last)
            
		} else {
			updateVirtualObjectPosition(newPosition, filterPosition)
		}
	}
	
	var dragOnInfinitePlanesEnabled = false
	
	func worldPositionFromScreenPosition(_ position: CGPoint,
	                                     objectPos: SCNVector3?,
	                                     infinitePlane: Bool = false) -> (position: SCNVector3?, planeAnchor: ARPlaneAnchor?, hitAPlane: Bool) {
		
		// -------------------------------------------------------------------------------
		// 1. Always do a hit test against exisiting plane anchors first.
		//    (If any such anchors exist & only within their extents.)
		
		let planeHitTestResults = sceneView.hitTest(position, types: .existingPlaneUsingExtent)
		if let result = planeHitTestResults.first {
			
			let planeHitTestPosition = SCNVector3.positionFromTransform(result.worldTransform)
			let planeAnchor = result.anchor
			
			// Return immediately - this is the best possible outcome.
			return (planeHitTestPosition, planeAnchor as? ARPlaneAnchor, true)
		}
		
		// -------------------------------------------------------------------------------
		// 2. Collect more information about the environment by hit testing against
		//    the feature point cloud, but do not return the result yet.
		
		var featureHitTestPosition: SCNVector3?
		var highQualityFeatureHitTestResult = false
		
		let highQualityfeatureHitTestResults = sceneView.hitTestWithFeatures(position, coneOpeningAngleInDegrees: 18, minDistance: 0.2, maxDistance: 2.0)
		
		if !highQualityfeatureHitTestResults.isEmpty {
			let result = highQualityfeatureHitTestResults[0]
			featureHitTestPosition = result.position
			highQualityFeatureHitTestResult = true
		}
		
		// -------------------------------------------------------------------------------
		// 3. If desired or necessary (no good feature hit test result): Hit test
		//    against an infinite, horizontal plane (ignoring the real world).
		
		if (infinitePlane && dragOnInfinitePlanesEnabled) || !highQualityFeatureHitTestResult {
			
			let pointOnPlane = objectPos ?? SCNVector3Zero
			
			let pointOnInfinitePlane = sceneView.hitTestWithInfiniteHorizontalPlane(position, pointOnPlane)
			if pointOnInfinitePlane != nil {
				return (pointOnInfinitePlane, nil, true)
			}
		}
		
		// -------------------------------------------------------------------------------
		// 4. If available, return the result of the hit test against high quality
		//    features if the hit tests against infinite planes were skipped or no
		//    infinite plane was hit.
		
		if highQualityFeatureHitTestResult {
			return (featureHitTestPosition, nil, false)
		}
		
		// -------------------------------------------------------------------------------
		// 5. As a last resort, perform a second, unfiltered hit test against features.
		//    If there are no features in the scene, the result returned here will be nil.
		
		let unfilteredFeatureHitTestResults = sceneView.hitTestWithFeatures(position)
		if !unfilteredFeatureHitTestResults.isEmpty {
			let result = unfilteredFeatureHitTestResults[0]
			return (result.position, nil, false)
		}
		
		return (nil, nil, false)
	}
	
	// Use average of recent virtual object distances to avoid rapid changes in object scale.
	var recentVirtualObjectDistances = [CGFloat]()
	
    func setNewVirtualObjectPosition(_ pos: SCNVector3, virtualObject: VirtualObject?) {
	
		guard let object = virtualObject, let cameraTransform = session.currentFrame?.camera.transform else {
			return
		}
		
		recentVirtualObjectDistances.removeAll()
		
		let cameraWorldPos = SCNVector3.positionFromTransform(cameraTransform)
		var cameraToPosition = pos - cameraWorldPos
		
		// Limit the distance of the object from the camera to a maximum of 10 meters.
		cameraToPosition.setMaximumLength(10)

		object.position = cameraWorldPos + cameraToPosition
		
		if object.parent == nil {
			sceneView.scene.rootNode.addChildNode(object)
		}
    }

    func resetVirtualObject(at: Int) {
        
        //ERROR: at is about the index of the Virtual object in the add-list and not about the virtual object in the list of current shown objects
        /*virtualObjects[at].unloadModel()
        virtualObjects[at].removeFromParentNode()
        virtualObjects.remove(at: at)*/
        virtualObjects.last?.unloadModel()
        virtualObjects.last?.removeFromParentNode()
        virtualObjects.removeLast()
        /*
		virtualObject?.unloadModel()
		virtualObject?.removeFromParentNode()
		virtualObject = nil
        */
		
		//addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
		//addObjectButton.setImage(#imageLiteral(resourceName: "addPressed"), for: [.highlighted])
		
		// Reset selected object id for row highlighting in object selection view controller.
		UserDefaults.standard.set(-1, for: .selectedObjectID)
	}
    
    func resetVirtualObjectAll() {
        for virtualObject in virtualObjects {
            virtualObject.unloadModel()
            virtualObject.removeFromParentNode()
        }
        
        virtualObjects.removeAll()
        
        //addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
        //addObjectButton.setImage(#imageLiteral(resourceName: "addPressed"), for: [.highlighted])
        
        // Reset selected object id for row highlighting in object selection view controller.
        UserDefaults.standard.set(-1, for: .selectedObjectID)
    }
	
	func updateVirtualObjectPosition(_ pos: SCNVector3, _ filterPosition: Bool) {
		guard let object = virtualObjectToMove else {
			return
		}
		
		guard let cameraTransform = session.currentFrame?.camera.transform else {
			return
		}
		
		let cameraWorldPos = SCNVector3.positionFromTransform(cameraTransform)
		var cameraToPosition = pos - cameraWorldPos
		
		// Limit the distance of the object from the camera to a maximum of 10 meters.
		cameraToPosition.setMaximumLength(10)
		
		// Compute the average distance of the object from the camera over the last ten
		// updates. If filterPosition is true, compute a new position for the object
		// with this average. Notice that the distance is applied to the vector from
		// the camera to the content, so it only affects the percieved distance of the
		// object - the averaging does _not_ make the content "lag".
		let hitTestResultDistance = CGFloat(cameraToPosition.length())

		recentVirtualObjectDistances.append(hitTestResultDistance)
		recentVirtualObjectDistances.keepLast(10)
		
		if filterPosition {
			let averageDistance = recentVirtualObjectDistances.average!
			
			cameraToPosition.setLength(Float(averageDistance))
			let averagedDistancePos = cameraWorldPos + cameraToPosition

			object.position = averagedDistancePos
		} else {
			object.position = cameraWorldPos + cameraToPosition
		}
    }
	
	func checkIfObjectShouldMoveOntoPlane(anchor: ARPlaneAnchor) {
		guard let object = virtualObjectToMove, let planeAnchorNode = sceneView.node(for: anchor) else {
			return
		}
		
		// Get the object's position in the plane's coordinate system.
		let objectPos = planeAnchorNode.convertPosition(object.position, from: object.parent)
		
		if objectPos.y == 0 {
			return; // The object is already on the plane - nothing to do here.
		}
		
		// Add 10% tolerance to the corners of the plane.
		let tolerance: Float = 0.1
		
		let minX: Float = anchor.center.x - anchor.extent.x / 2 - anchor.extent.x * tolerance
		let maxX: Float = anchor.center.x + anchor.extent.x / 2 + anchor.extent.x * tolerance
		let minZ: Float = anchor.center.z - anchor.extent.z / 2 - anchor.extent.z * tolerance
		let maxZ: Float = anchor.center.z + anchor.extent.z / 2 + anchor.extent.z * tolerance
		
		if objectPos.x < minX || objectPos.x > maxX || objectPos.z < minZ || objectPos.z > maxZ {
			return
		}
		
		// Drop the object onto the plane if it is near it.
		let verticalAllowance: Float = 0.03
		if objectPos.y > -verticalAllowance && objectPos.y < verticalAllowance {
			textManager.showDebugMessage("OBJECT MOVED\nSurface detected nearby")
			
			SCNTransaction.begin()
			SCNTransaction.animationDuration = 0.5
			SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
			object.position.y = anchor.transform.columns.3.y
			SCNTransaction.commit()
		}
	}
	
    // MARK: - Virtual Object Loading
	
    var virtualObjects: [VirtualObject] = []
    var virtualObjectToMove: VirtualObject?
    var virtualObjectToMoveIndex: Int = 0
	//var virtualObject: VirtualObject?
	var isLoadingObject: Bool = false {
		didSet {
			DispatchQueue.main.async {
				self.settingsButton.isEnabled = !self.isLoadingObject
				self.addObjectButton.isEnabled = !self.isLoadingObject
				self.screenshotButton.isEnabled = !self.isLoadingObject
				self.restartExperienceButton.isEnabled = !self.isLoadingObject
			}
		}
	}
	
	@IBOutlet weak var addObjectButton: UIButton!
	
	func loadVirtualObject(at index: Int) {
		//resetVirtualObject()------------------------------------------------------------------------
		
		// Show progress indicator
		let spinner = UIActivityIndicatorView()
		spinner.center = addObjectButton.center
		spinner.bounds.size = CGSize(width: addObjectButton.bounds.width - 5, height: addObjectButton.bounds.height - 5)
		//addObjectButton.setImage(#imageLiteral(resourceName: "buttonring"), for: [])
		sceneView.addSubview(spinner)
		spinner.startAnimating()
		
		// Load the content asynchronously.
		DispatchQueue.global().async {
			self.isLoadingObject = true
			let object = VirtualObject.availableObjects[index]
			object.viewController = self
			//self.virtualObject = object --------------------------------------------------------------
            self.virtualObjects.append(object)
			
			object.loadModel()
			
			DispatchQueue.main.async {
				// Immediately place the object in 3D space.
				if let lastFocusSquarePos = self.focusSquare?.lastPosition {
                    self.setNewVirtualObjectPosition(lastFocusSquarePos, virtualObject: object)
				} else {
                    self.setNewVirtualObjectPosition(SCNVector3Zero, virtualObject: object)
				}
				
				// Remove progress indicator
				spinner.removeFromSuperview()
				
				// Update the icon of the add object button
				let buttonImage = UIImage.composeButtonImage(from: object.thumbImage)
				let pressedButtonImage = UIImage.composeButtonImage(from: object.thumbImage, alpha: 0.3)
				//self.addObjectButton.setImage(buttonImage, for: [])
				//self.addObjectButton.setImage(pressedButtonImage, for: [.highlighted])
				self.isLoadingObject = false
			}
		}
    }
	
	@IBAction func chooseObject(_ button: UIButton) {
		// Abort if we are about to load another object to avoid concurrent modifications of the scene.
        if self.currentButton == addObjectButton {
            self.dropdownMenue(button)
        }else{
            self.prepareSecond()
        }
        
		
    }
	
    func dropdownMenue(_ button: UIButton){
        if isLoadingObject { return }
        
        textManager.cancelScheduledMessage(forType: .contentPlacement)
        
        let rowHeight = 45
        let popoverSize = CGSize(width: 250, height: rowHeight * VirtualObject.availableObjects.count)
        
        let objectViewController = VirtualObjectSelectionViewController(size: popoverSize)
        objectViewController.delegate = self
        objectViewController.modalPresentationStyle = .popover
        objectViewController.popoverPresentationController?.delegate = self
        self.present(objectViewController, animated: true, completion: nil)
        
        objectViewController.popoverPresentationController?.sourceView = button
        objectViewController.popoverPresentationController?.sourceRect = button.bounds
    }
    
	// MARK: - VirtualObjectSelectionViewControllerDelegate
	
	func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didSelectObjectAt index: Int) {
		loadVirtualObject(at: index)
	}
	
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didDeselectObjectAt index: Int) {
        resetVirtualObject(at: index)
    }
	
    // MARK: - Planes
	
	var planes = [ARPlaneAnchor: Plane]()
	
    func addPlane(node: SCNNode, anchor: ARPlaneAnchor) {
		
		let pos = SCNVector3.positionFromTransform(anchor.transform)
		textManager.showDebugMessage("NEW SURFACE DETECTED AT \(pos.friendlyString())")
        
		let plane = Plane(anchor, showDebugVisuals)
		
		planes[anchor] = plane
		node.addChildNode(plane)
		
		textManager.cancelScheduledMessage(forType: .planeEstimation)
		textManager.showMessage("SURFACE DETECTED")
		/*if virtualObject == nil { ----------------------------------------------------------------------------------------------------
			textManager.scheduleMessage("TAP + TO PLACE AN OBJECT", inSeconds: 7.5, messageType: .contentPlacement)
		}*/
	}
		
    func updatePlane(anchor: ARPlaneAnchor) {
        if let plane = planes[anchor] {
			plane.update(anchor)
		}
	}
			
    func removePlane(anchor: ARPlaneAnchor) {
		if let plane = planes.removeValue(forKey: anchor) {
			plane.removeFromParentNode()
        }
    }
	
	func restartPlaneDetection() {
		
		// configure session
        if let worldSessionConfig = sessionConfig as? ARWorldTrackingConfiguration{//ARWorldTrackingSessionConfiguration{
			worldSessionConfig.planeDetection = .horizontal
			session.run(worldSessionConfig, options: [.resetTracking, .removeExistingAnchors])
		}
		
		// reset timer
		if trackingFallbackTimer != nil {
			trackingFallbackTimer!.invalidate()
			trackingFallbackTimer = nil
		}
		
		textManager.scheduleMessage("FIND A SURFACE TO PLACE AN OBJECT",
		                            inSeconds: 7.5,
		                            messageType: .planeEstimation)
	}

    // MARK: - Focus Square
    var focusSquare: FocusSquare?
	
    func setupFocusSquare() {
		focusSquare?.isHidden = true
		focusSquare?.removeFromParentNode()
		focusSquare = FocusSquare()
		sceneView.scene.rootNode.addChildNode(focusSquare!)
		
		textManager.scheduleMessage("TRY MOVING LEFT OR RIGHT", inSeconds: 5.0, messageType: .focusSquare)
    }
	
	func updateFocusSquare() {
		guard let screenCenter = screenCenter else { return }
		
        var planeHasObject = false
        for virtualObject in self.virtualObjects {
            if sceneView.isNode(virtualObject, insideFrustumOf: sceneView.pointOfView!) {
                planeHasObject = true
            }
        }
        
		if !self.virtualObjects.isEmpty && planeHasObject {
			focusSquare?.hide()
		} else {
			focusSquare?.unhide()
		}
		let (worldPos, planeAnchor, _) = worldPositionFromScreenPosition(screenCenter, objectPos: focusSquare?.position)
		if let worldPos = worldPos {
			focusSquare?.update(for: worldPos, planeAnchor: planeAnchor, camera: self.session.currentFrame?.camera)
			textManager.cancelScheduledMessage(forType: .focusSquare)
		}
	}
	
	// MARK: - Hit Test Visualization
	
	var hitTestVisualization: HitTestVisualization?
	
	var showHitTestAPIVisualization = UserDefaults.standard.bool(for: .showHitTestAPI) {
		didSet {
			UserDefaults.standard.set(showHitTestAPIVisualization, for: .showHitTestAPI)
			if showHitTestAPIVisualization {
				hitTestVisualization = HitTestVisualization(sceneView: sceneView)
			} else {
				hitTestVisualization = nil
			}
		}
	}
	
    // MARK: - Debug Visualizations
	
	@IBOutlet var featurePointCountLabel: UILabel!
	
	func refreshFeaturePoints() {
		guard showDebugVisuals else {
			return
		}
		
		// retrieve cloud
		guard let cloud = session.currentFrame?.rawFeaturePoints else {
			return
		}
		
		/*DispatchQueue.main.async {
			self.featurePointCountLabel.text = "Features: \(cloud.count)".uppercased()--------------------------------
		}*/
	}
	
    var showDebugVisuals: Bool = UserDefaults.standard.bool(for: .debugMode) {
        didSet {
			featurePointCountLabel.isHidden = !showDebugVisuals
			debugMessageLabel.isHidden = !showDebugVisuals
			messagePanel.isHidden = !showDebugVisuals
			planes.values.forEach { $0.showDebugVisualization(showDebugVisuals) }
			
			if showDebugVisuals {
				sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
			} else {
				sceneView.debugOptions = []
			}
			
            // save pref
            UserDefaults.standard.set(showDebugVisuals, for: .debugMode)
        }
    }
    
    func setupDebug() {
		// Set appearance of debug output panel
		messagePanel.layer.cornerRadius = 3.0
		messagePanel.clipsToBounds = true
    }
    
    // MARK: - UI Elements and Actions
	
	@IBOutlet weak var messagePanel: UIView!
	@IBOutlet weak var messageLabel: UILabel!
	@IBOutlet weak var debugMessageLabel: UILabel!
	
	var textManager: TextManager!
	
    func setupUIControls() {
		textManager = TextManager(viewController: self)
		
        // hide debug message view
		debugMessageLabel.isHidden = true
		
		featurePointCountLabel.text = ""
		debugMessageLabel.text = ""
		messageLabel.text = ""
        
    }
	
	@IBOutlet weak var restartExperienceButton: UIButton!
	var restartExperienceButtonIsEnabled = true
	
	@IBAction func restartExperience(_ sender: Any) {
		
		guard restartExperienceButtonIsEnabled, !isLoadingObject else {
			return
		}
		
		DispatchQueue.main.async {
			self.restartExperienceButtonIsEnabled = false
			
			self.textManager.cancelAllScheduledMessages()
			self.textManager.dismissPresentedAlert()
			self.textManager.showMessage("STARTING A NEW SESSION")
			//self.use3DOFTracking = false--------------------------------------------
			
			self.setupFocusSquare()
			self.resetVirtualObjectAll()
			self.restartPlaneDetection()
			
			self.restartExperienceButton.setImage(#imageLiteral(resourceName: "restart"), for: [])
			
			// Disable Restart button for five seconds in order to give the session enough time to restart.
			DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: {
				self.restartExperienceButtonIsEnabled = true
			})
		}
	}
	
	@IBOutlet weak var screenshotButton: UIButton!
	
	@IBAction func takeScreenshot() {
		guard screenshotButton.isEnabled else {
			return
		}
		
		let takeScreenshotBlock = {
			UIImageWriteToSavedPhotosAlbum(self.sceneView.snapshot(), nil, nil, nil)
			DispatchQueue.main.async {
				// Briefly flash the screen.
				let flashOverlay = UIView(frame: self.sceneView.frame)
				flashOverlay.backgroundColor = UIColor.white
				self.sceneView.addSubview(flashOverlay)
				UIView.animate(withDuration: 0.25, animations: {
					flashOverlay.alpha = 0.0
				}, completion: { _ in
					flashOverlay.removeFromSuperview()
				})
			}
		}
		
		switch PHPhotoLibrary.authorizationStatus() {
		case .authorized:
			takeScreenshotBlock()
		case .restricted, .denied:
			let title = "Photos access denied"
			let message = "Please enable Photos access for this application in Settings > Privacy to allow saving screenshots."
			textManager.showAlert(title: title, message: message)
		case .notDetermined:
			PHPhotoLibrary.requestAuthorization({ (authorizationStatus) in
				if authorizationStatus == .authorized {
					takeScreenshotBlock()
				}
			})
		}
	}
    
    
    func showVideo(){
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let settingsViewController = storyboard.instantiateViewController(withIdentifier: "VideoViewController") as? VideoViewController else {
            return
        }
        
        let barButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSettings))
        settingsViewController.navigationItem.rightBarButtonItem = barButtonItem
        settingsViewController.title = "Telecom Sport"
        
        let navigationController = UINavigationController(rootViewController: settingsViewController)
        navigationController.modalPresentationStyle = .popover
        navigationController.popoverPresentationController?.delegate = self
        navigationController.preferredContentSize = CGSize(width: sceneView.bounds.size.width - 20, height: sceneView.bounds.size.height - 50)
        self.present(navigationController, animated: true, completion: nil)
        
        navigationController.popoverPresentationController?.sourceView = buttonRectangleDetection
        navigationController.popoverPresentationController?.sourceRect = buttonRectangleDetection.bounds
    }
		
	// MARK: - Settings
	
	@IBOutlet weak var settingsButton: UIButton!
	
	@IBAction func showSettings(_ button: UIButton) {
        showVideo()
		/*let storyboard = UIStoryboard(name: "Main", bundle: nil)
		guard let settingsViewController = storyboard.instantiateViewController(withIdentifier: "settingsViewController") as? SettingsViewController else {
			return
		}
		
		let barButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSettings))
		settingsViewController.navigationItem.rightBarButtonItem = barButtonItem
		settingsViewController.title = "Options"
		
		let navigationController = UINavigationController(rootViewController: settingsViewController)
		navigationController.modalPresentationStyle = .popover
		navigationController.popoverPresentationController?.delegate = self
		navigationController.preferredContentSize = CGSize(width: sceneView.bounds.size.width - 20, height: sceneView.bounds.size.height - 50)
		self.present(navigationController, animated: true, completion: nil)
		
		navigationController.popoverPresentationController?.sourceView = settingsButton
		navigationController.popoverPresentationController?.sourceRect = settingsButton.bounds*/
	}
	
    @objc
    func dismissSettings() {
		self.dismiss(animated: true, completion: nil)
		updateSettings()
	}
	
	private func updateSettings() {
		let defaults = UserDefaults.standard
		
		showDebugVisuals = defaults.bool(for: .debugMode)
		toggleAmbientLightEstimation(defaults.bool(for: .ambientLightEstimation))
		dragOnInfinitePlanesEnabled = defaults.bool(for: .dragOnInfinitePlanes)
		showHitTestAPIVisualization = defaults.bool(for: .showHitTestAPI)
		//use3DOFTracking	= defaults.bool(for: .use3DOFTracking)-------------------------------------
		use3DOFTrackingFallback = defaults.bool(for: .use3DOFFallback)
		for (_, plane) in planes {
			plane.updateOcclusionSetting()
		}
	}

	// MARK: - Error handling
	
	func displayErrorMessage(title: String, message: String, allowRestart: Bool = false) {
		// Blur the background.
		textManager.blurBackground()
		
		if allowRestart {
			// Present an alert informing about the error that has occurred.
			let restartAction = UIAlertAction(title: "Reset", style: .default) { _ in
				self.textManager.unblurBackground()
				self.restartExperience(self)
			}
			textManager.showAlert(title: title, message: message, actions: [restartAction])
		} else {
			textManager.showAlert(title: title, message: message, actions: [])
		}
	}
	
	// MARK: - UIPopoverPresentationControllerDelegate
	func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
		return .none
	}
	
	func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
		updateSettings()
	}
    
    
    // ---------------------------------------- TO FORCE LANDSCAPE MODE -----------------------------------------
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return UIInterfaceOrientation.landscapeRight
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.landscapeRight
    }
    
    override var shouldAutorotate: Bool {
        return false
    }
    
    
    
    
    // ---------------------------------------- XXXXXXXXXXXXXXXXXXXXXXXXX -----------------------------------------
    // ------------------------------- HERE IS THE MERGE WITH THE OTHER PROJECT -----------------------------------------
    // ---------------------------------------- XXXXXXXXXXXXXXXXXXXXXXXXX -----------------------------------------
    
    //------------------------- CONSTANTS -------------------------
    let mWidthOf2DScreen = CGFloat(0.5)//0.4
    let mHeightOf2DScreen = CGFloat(0.281)//0.225
    let debugRect = true
    
    //------------------------------------ HERE THE REAL STUFF IS DONE ------------------------------------------------------
    
    
    // ------------------------------------ THIS IS ALL ABOUT DETECTION RECTANGLES IN THE AIR ------------------------------------------------------
    
    
    func initRectangleDetectionRequest(frame: ARFrame) -> VNDetectRectanglesRequest{
        
        
        let rectangleDetectionRequest = VNDetectRectanglesRequest(completionHandler: {(request: VNRequest, error: Error?) in
            
            //------------------ HANDLE TEXT RECTANGLE REQUEST -----------------------
            print("InitRectangleDetectionRequest HANDLER")
            
            guard let observations = request.results else {
                print("no result")
                return
            }
            
            if (request.results?.isEmpty)! {
                print("Requests are empty")
            }
            
            let result = observations.map({$0 as? VNRectangleObservation})
            
            for observation in result {
                if let observation = observation {
                    let hitResultTopLeftArray = frame.hitTest(observation.topLeft.invert(), types: [.featurePoint])
                    let hitResultTopRightArray = frame.hitTest(observation.topRight.invert(), types: [.featurePoint])
                    let hitResultBottomLeftArray = frame.hitTest(observation.bottomLeft.invert(), types: [.featurePoint])
                    let hitResultBottomRightArray = frame.hitTest(observation.bottomRight.invert(), types: [.featurePoint])
                    guard let hitResultTopLeft = hitResultTopLeftArray.first else {
                        continue
                    }
                    guard let hitResultTopRight = hitResultTopRightArray.first else {
                        continue
                    }
                    guard let hitResultBottomLeft = hitResultBottomLeftArray.first else {
                        continue
                    }
                    guard let hitResultBottomRight = hitResultBottomRightArray.first else {
                        continue
                    }
                    
                    let topLeftVector = SCNVector3Make(hitResultTopLeft.worldTransform.columns.3.x, hitResultTopLeft.worldTransform.columns.3.y, hitResultTopLeft.worldTransform.columns.3.z)
                    let topRightVector = SCNVector3Make(hitResultTopRight.worldTransform.columns.3.x, hitResultTopRight.worldTransform.columns.3.y, hitResultTopRight.worldTransform.columns.3.z)
                    let bottomLeftVector = SCNVector3Make(hitResultBottomLeft.worldTransform.columns.3.x, hitResultBottomLeft.worldTransform.columns.3.y, hitResultBottomLeft.worldTransform.columns.3.z)
                    let bottomRightVector = SCNVector3Make(hitResultBottomRight.worldTransform.columns.3.x, hitResultBottomRight.worldTransform.columns.3.y, hitResultBottomRight.worldTransform.columns.3.z)
                    
                    let vectorHorizontal = topRightVector-topLeftVector
                    let vectorVertical = bottomLeftVector-topLeftVector
                    let vectorNormal = vectorHorizontal.cross(vectorVertical)
                    let vectorToPlaneCenter = bottomRightVector+(topLeftVector-bottomRightVector)*0.5
                    
                    // SET VARIABLES
                    self.vecHalfRight = vectorHorizontal*0.5
                    self.vecHalfUp = vectorVertical*0.5
                    self.vecToRectCenter = vectorToPlaneCenter
                    self.vecNormal = vectorNormal
                    
                    
                    
                    // ------------ SOME DEBUGGING STUFF -------------------
                    if self.debugRect {
                    let lineLeft = SCNNode(geometry: SCNGeometry.lineForm(vector1: topLeftVector, vector2: bottomLeftVector))
                    lineLeft.geometry?.firstMaterial?.diffuse.contents = UIColor.red
                    let lineRight = SCNNode(geometry: SCNGeometry.lineForm(vector1: topRightVector, vector2: bottomRightVector))
                    lineRight.geometry?.firstMaterial?.diffuse.contents = UIColor.green
                    let lineTop = SCNNode(geometry: SCNGeometry.lineForm(vector1: topLeftVector, vector2: topRightVector))
                    lineTop.geometry?.firstMaterial?.diffuse.contents = UIColor.purple
                    let lineBottom = SCNNode(geometry: SCNGeometry.lineForm(vector1: bottomLeftVector, vector2: bottomRightVector))
                    self.sceneView.scene.rootNode.addChildNode(lineLeft)
                    self.sceneView.scene.rootNode.addChildNode(lineRight)
                    self.sceneView.scene.rootNode.addChildNode(lineTop)
                    self.sceneView.scene.rootNode.addChildNode(lineBottom)
                        
                    }
                    
                    
                    self.prepareSecond()
                }
            }
            
            //------------------ HANDLE TEXT RECTANGLE REQUEST -----------------------
            
        })
        
        
        return rectangleDetectionRequest
    }
    
    

    func doRectangleDetection(){
        if let arFrame = sceneView.session.currentFrame {
            let pixelBuffer = arFrame.capturedImage
            
            let requestOptions:[VNImageOption : Any] = [:]
            
            
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation(rawValue: 6)!, options: requestOptions)
            
            do {
                try imageRequestHandler.perform([self.initRectangleDetectionRequest(frame: arFrame)])
            } catch {
                print(error)
            }
            
        }
    }
    
    
    
    
    func doQRCodeDetection(){
        if let arFrame = sceneView.session.currentFrame {
            let pixelBuffer = arFrame.capturedImage
            
            let requestOptions:[VNImageOption : Any] = [:]
            
            
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation(rawValue: 6)!, options: requestOptions)
            
            do {
                try imageRequestHandler.perform([self.initQRCodeDetectionRequest(frame: arFrame)])
            } catch {
                print(error)
            }
            
        }
    }
    
    
    func initQRCodeDetectionRequest(frame: ARFrame) -> VNDetectBarcodesRequest{
        
        
        let qrCodeDetectionRequest = VNDetectBarcodesRequest(completionHandler: {(request: VNRequest, error: Error?) in
            
            //------------------ HANDLE TEXT RECTANGLE REQUEST -----------------------
            print("InitQRDetectionRequest QR HANDLER")
            
            guard let observations = request.results else {
                print("no result")
                return
            }
            
            if (request.results?.isEmpty)! {
                print("Requests are empty")
            }
            
            let result = observations.map({$0 as? VNBarcodeObservation})
            
            for observation in result {
                if let observation = observation {
                    let hitResultTopLeftArray = frame.hitTest(observation.topLeft.invert(), types: [.featurePoint])
                    let hitResultTopRightArray = frame.hitTest(observation.topRight.invert(), types: [.featurePoint])
                    let hitResultBottomLeftArray = frame.hitTest(observation.bottomLeft.invert(), types: [.featurePoint])
                    let hitResultBottomRightArray = frame.hitTest(observation.bottomRight.invert(), types: [.featurePoint])
                    guard let hitResultTopLeft = hitResultTopLeftArray.first else {
                        continue
                    }
                    guard let hitResultTopRight = hitResultTopRightArray.first else {
                        continue
                    }
                    guard let hitResultBottomLeft = hitResultBottomLeftArray.first else {
                        continue
                    }
                    guard let hitResultBottomRight = hitResultBottomRightArray.first else {
                        continue
                    }
                    
                    let topLeftVector = SCNVector3Make(hitResultTopLeft.worldTransform.columns.3.x, hitResultTopLeft.worldTransform.columns.3.y, hitResultTopLeft.worldTransform.columns.3.z)
                    let topRightVector = SCNVector3Make(hitResultTopRight.worldTransform.columns.3.x, hitResultTopRight.worldTransform.columns.3.y, hitResultTopRight.worldTransform.columns.3.z)
                    let bottomLeftVector = SCNVector3Make(hitResultBottomLeft.worldTransform.columns.3.x, hitResultBottomLeft.worldTransform.columns.3.y, hitResultBottomLeft.worldTransform.columns.3.z)
                    let bottomRightVector = SCNVector3Make(hitResultBottomRight.worldTransform.columns.3.x, hitResultBottomRight.worldTransform.columns.3.y, hitResultBottomRight.worldTransform.columns.3.z)
                    
                    let vectorHorizontal = topRightVector-topLeftVector
                    let vectorVertical = bottomLeftVector-topLeftVector
                    let vectorNormal = vectorHorizontal.cross(vectorVertical)
                    let vectorToPlaneCenter = bottomRightVector+(topLeftVector-bottomRightVector)*0.5
                    
                    // SET VARIABLES
                    self.vecHalfRight = vectorHorizontal*0.5
                    self.vecHalfUp = vectorVertical*0.5
                    self.vecToRectCenter = vectorToPlaneCenter
                    self.vecNormal = vectorNormal
                    
                    
                    
                    // ------------ SOME DEBUGGING STUFF -------------------
                    if self.debugRect {
                        let lineLeft = SCNNode(geometry: SCNGeometry.lineForm(vector1: topLeftVector, vector2: bottomLeftVector))
                        lineLeft.geometry?.firstMaterial?.diffuse.contents = UIColor.red
                        let lineRight = SCNNode(geometry: SCNGeometry.lineForm(vector1: topRightVector, vector2: bottomRightVector))
                        lineRight.geometry?.firstMaterial?.diffuse.contents = UIColor.green
                        let lineTop = SCNNode(geometry: SCNGeometry.lineForm(vector1: topLeftVector, vector2: topRightVector))
                        lineTop.geometry?.firstMaterial?.diffuse.contents = UIColor.purple
                        let lineBottom = SCNNode(geometry: SCNGeometry.lineForm(vector1: bottomLeftVector, vector2: bottomRightVector))
                        self.sceneView.scene.rootNode.addChildNode(lineLeft)
                        self.sceneView.scene.rootNode.addChildNode(lineRight)
                        self.sceneView.scene.rootNode.addChildNode(lineTop)
                        self.sceneView.scene.rootNode.addChildNode(lineBottom)
                        
                    }
                    
                    
                    self.prepareSecond()
                }
            }
            
            //------------------ HANDLE TEXT RECTANGLE REQUEST -----------------------
            
        })
        
        
        return qrCodeDetectionRequest
    }
    
    
    

    //---------------------------------------------- STUFF TO PLACE A 2D OBJECT ----------------------------------------------
    
    func place2DObject(width: CGFloat, height: CGFloat, vecNormal: SCNVector3, vecToCenter: SCNVector3, offsetHoriz: Float, offsetVert: Float) {
        
        let plane = SCNPlane(width: width, height: height)
        plane.firstMaterial?.diffuse.contents = UIColor.white
        // HOW TO PLACE AN VIDEO: https://stackoverflow.com/questions/42469024/how-do-i-create-a-looping-video-material-in-scenekit-on-ios-in-swift-3
        
        let planeNode = SCNNode()
        
        let vecOffsetVert = SCNVector3Make(0, offsetVert, 0)
        let vecOffsetHoriz = vecNormal.cross(vecOffsetVert).norm()*offsetHoriz
        
        planeNode.geometry = plane
        planeNode.position = vecToCenter+vecOffsetVert+vecOffsetHoriz //CURRENT NORMAL VECTOR
        
        let vecRotation = vecToCenter.cross(vecNormal).norm()
        let angle = acos(vecToCenter.norm().dot(vecNormal.norm()))
        
        //planeNode.rotation = SCNVector4Make(vecRotation.x, vecRotation.y, vecRotation.z, angle)
        
        self.sceneView.scene.rootNode.addChildNode(planeNode)
    }
    
    func place3DText(width: CGFloat, height: CGFloat, vecNormal: SCNVector3, vecToCenter: SCNVector3, offsetHoriz: Float, offsetVert: Float) {
        
        
        
        let vecOffsetVert = SCNVector3Make(0, offsetVert, 0)
        let vecOffsetHoriz = vecNormal.cross(vecOffsetVert).norm()*offsetHoriz
        
        
        let vecRotation = vecToCenter.cross(vecNormal).norm()
        let angle = acos(vecToCenter.norm().dot(vecNormal.norm()))
        
        //planeNode.rotation = SCNVector4Make(vecRotation.x, vecRotation.y, vecRotation.z, angle)
        
        let text = SCNText(string: "Arjen Robben (10)", extrusionDepth:1)
        let material = SCNMaterial();
        material.diffuse.contents = UIColor.red
        text.materials = [material]
        
        let node = SCNNode()
        node.position =  vecToCenter+vecOffsetVert+vecOffsetHoriz
        node.scale =  SCNVector3(x:0.1, y:0.01, z:0.01)
        node.geometry = text
        
        self.nodes.append(node)
        self.sceneView.scene.rootNode.addChildNode(node)
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
        planeNode.position = vecToCenter+vecOffsetVert+vecOffsetHoriz //CURRENT NORMAL VECTOR
        
        let vecRotation = vecToCenter.cross(vecNormal).norm()
        let angle = acos(vecToCenter.norm().dot(vecNormal.norm()))
        
        //planeNode.rotation = SCNVector4Make(vecRotation.x, vecRotation.y, vecRotation.z, angle)
        
        self.nodes.append(planeNode)
        self.sceneView.scene.rootNode.addChildNode(planeNode)
    }
    
    func place2DVideo(width: CGFloat, height: CGFloat, vecNormal: SCNVector3, vecToCenter: SCNVector3, offsetHoriz: Float, offsetVert: Float) {
        
        // A SpriteKit scene to contain the SpriteKit video node
        let spriteKitScene = SKScene(size: CGSize(width: sceneView.frame.width, height: sceneView.frame.height)) //width, height: height))
        spriteKitScene.scaleMode = .aspectFit
        
        // Create a video player, which will be responsible for the playback of the video material
        //let videoUrl = URL(string: "http://dl.mnac-s-000000136.c.nmdn.net/mnac-s-000000136/20180120/0/0_21ptf6zo_0_tkgz11l3_2.mp4")!
        //Bundle.main.url(forResource: "videos/video", withExtension: "mp4")!
        let videoUrl = Bundle.main.url(forResource: "video", withExtension: "mp4")
        let videoPlayer = AVPlayer(url: videoUrl!)
        
        // To make the video loop
        videoPlayer.actionAtItemEnd = .none
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.playerItemDidReachEnd),
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: videoPlayer.currentItem)
        
        // Create the SpriteKit video node, containing the video player
        let videoSpriteKitNode = SKVideoNode(avPlayer: videoPlayer)
        videoSpriteKitNode.position = CGPoint(x: spriteKitScene.size.width / 2.0, y: spriteKitScene.size.height / 2.0)
        videoSpriteKitNode.size = spriteKitScene.size
        videoSpriteKitNode.yScale = -1.0
        videoSpriteKitNode.play()
        spriteKitScene.addChild(videoSpriteKitNode)
        
        
        /*// Create the SceneKit scene
        let scene = SCNScene()
        sceneView.scene = scene
        sceneView.delegate = self
        sceneView.isPlaying = true*/
        
        // Create a SceneKit plane and add the SpriteKit scene as its material
        let background = SCNPlane(width: width, height: height)
        background.firstMaterial?.diffuse.contents = spriteKitScene
        let backgroundNode = SCNNode(geometry: background)
        //scene.rootNode.addChildNode(backgroundNode)
        
        
        
        
        
        
        
        /*
        let plane = SCNPlane(width: width, height: height)
        plane.firstMaterial?.diffuse.contents = UIColor.white
        // HOW TO PLACE AN VIDEO: https://stackoverflow.com/questions/42469024/how-do-i-create-a-looping-video-material-in-scenekit-on-ios-in-swift-3
        
        let planeNode = SCNNode()
        */
        
        let vecOffsetVert = SCNVector3Make(0, offsetVert, 0)
        let vecOffsetHoriz = vecNormal.cross(vecOffsetVert).norm()*offsetHoriz
        
        //planeNode.geometry = plane
        backgroundNode.position = vecToCenter+vecOffsetVert+vecOffsetHoriz //CURRENT NORMAL VECTOR
        
        let vecRotation = vecToCenter.cross(vecNormal).norm()
        let angle = acos(vecToCenter.norm().dot(vecNormal.norm()))
        
        //planeNode.rotation = SCNVector4Make(vecRotation.x, vecRotation.y, vecRotation.z, angle)
        
        
        //self.sceneView.scene.isPaused = false
        self.nodes.append(backgroundNode)
        self.sceneView.scene.rootNode.addChildNode(backgroundNode)
    }

    //---------------------------------- MY BUTTONS ----------------------------
    var currentButton: UIButton?
    
    @IBOutlet var labelInstruction: UILabel!
    
    
    @IBOutlet var buttonRectangleDetection: UIButton!
    
    @IBOutlet var buttonOne: UIButton!
    
    @IBOutlet var viewConnect: UIView!
    
    
    @IBAction func touchInRectangleButton(_ button: UIButton) {
        if currentButton == buttonRectangleDetection{
            //DROPDOWN MENUE
            self.dropdownMenue(button)
            
        }else{
            prepareThird()
        }
    }
    
    @IBAction func onOneButtonClicked(_ sender: Any) {
        if currentButton == buttonOne {
            //doRectangleDetection()
            doQRCodeDetection()
        }
    }
    
    
    
    
    
    // ------------------------------- VIDEO STREAM -------------------------------
    // This callback will restart the video when it has reach its end
    @objc func playerItemDidReachEnd(notification: NSNotification) {
        if let playerItem: AVPlayerItem = notification.object as? AVPlayerItem {
            playerItem.seek(to: kCMTimeZero)
        }
    }
    
    
    
    // ---------------------------- USER JOURNEY -------------------------
    var vecToRectCenter: SCNVector3?
    var vecNormal: SCNVector3?
    var vecHalfUp: SCNVector3?
    var vecHalfRight: SCNVector3?
    
    var nodes: [SCNNode] = []
    
    func prepareFirst(){
        addObjectButton.setBackgroundImage(#imageLiteral(resourceName: "circles_gray"), for: .disabled)
        buttonRectangleDetection.setBackgroundImage(#imageLiteral(resourceName: "circles_gray"), for: .disabled)
        buttonOne.setBackgroundImage(#imageLiteral(resourceName: "circles_gray"), for: .disabled)
        addObjectButton.setBackgroundImage(#imageLiteral(resourceName: "circles_white"), for: .normal)
        buttonRectangleDetection.setBackgroundImage(#imageLiteral(resourceName: "circles_white"), for: .normal)
        buttonOne.setBackgroundImage(#imageLiteral(resourceName: "circles_white"), for: .normal)
        
        buttonOne.setBackgroundImage(#imageLiteral(resourceName: "circle_on_"), for: .normal)
        
        addObjectButton.isEnabled = false
        buttonRectangleDetection.isEnabled = false
        buttonOne.isEnabled = true
        self.labelInstruction.isHidden = false
        
        self.currentButton = buttonOne
        
        self.first()
    }
    
    func first(){
        //TEXT
    }
    
    func prepareSecond(){
        addObjectButton.isEnabled = true
        buttonRectangleDetection.isEnabled = true
        buttonOne.isEnabled = false
        self.labelInstruction.isHidden = true
        addObjectButton.setBackgroundImage(#imageLiteral(resourceName: "circle_on_"), for: .normal)
        buttonOne.setBackgroundImage(#imageLiteral(resourceName: "circles_white"), for: .normal)
        buttonRectangleDetection.setBackgroundImage(#imageLiteral(resourceName: "circles_white"), for: .normal)
        
        self.currentButton = addObjectButton
        
        self.removeAllChilds()
        
        self.second()
    }
    
    func second(){
        if vecToRectCenter != nil && vecNormal != nil && vecHalfUp != nil && vecHalfRight != nil {
        /*self.place2DVideo(width: self.mWidthOf2DScreen, height: self.mHeightOf2DScreen, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.3), offsetVert: Float(0.3)) //(Positive, Positive) -> topRight
        
        self.place2DImage(width: self.mWidthOf2DScreen, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(-0.1), offsetVert: Float(0.2), image: #imageLiteral(resourceName: "top_info_left")) //(Positive, Positive) -> topRight
        self.place2DImage(width: self.mWidthOf2DScreen, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.1), offsetVert: Float(0.2), image: #imageLiteral(resourceName: "top_info_right")) //(Positive, Positive) -> topRight
        self.place3DText(width: self.mWidthOf2DScreen, height: self.mHeightOf2DScreen, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.0), offsetVert: Float(-0.2)) //(Positive, Positive) -> topRight
            */
            
            
            /*
            self.place2DImage(width: 1.0, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.0), offsetVert: Float(0.35), image: #imageLiteral(resourceName: "top_widgets-15"))
            self.place2DImage(width: 0.20, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0), offsetVert: Float(-0.35), image: #imageLiteral(resourceName: "widgets-2"))
            
            self.place2DVideo(width: self.mWidthOf2DScreen, height: self.mHeightOf2DScreen, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(-0.7), offsetVert: Float(0.1)) //(Positive, Positive) -> topRight
            
            self.place2DImage(width: 0.20, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(-0.7), offsetVert: Float(-0.35), image: #imageLiteral(resourceName: "widgets-5"))
            self.place2DImage(width: 0.40, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.6), offsetVert: Float(0.1), image: #imageLiteral(resourceName: "widgets-12"))
            self.place2DImage(width: 0.2, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.7), offsetVert: Float(-0.35), image: #imageLiteral(resourceName: "widgets-4"))
 
 */
            
        }
    }
    
    func prepareThird(){
        addObjectButton.isEnabled = true
        buttonRectangleDetection.isEnabled = true
        buttonOne.isEnabled = false
        self.labelInstruction.isHidden = true
        
        buttonRectangleDetection.setBackgroundImage(#imageLiteral(resourceName: "circle_on_"), for: .normal)
        buttonOne.setBackgroundImage(#imageLiteral(resourceName: "circles_white"), for: .normal)
        addObjectButton.setBackgroundImage(#imageLiteral(resourceName: "circles_white"), for: .normal)
        
        self.currentButton = buttonRectangleDetection
        
        self.removeAllChilds()
        
        self.third()
    }
    
    func third(){
        if vecToRectCenter != nil && vecNormal != nil && vecHalfUp != nil && vecHalfRight != nil {
        
            /*self.place2DImage(width: 0.55, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(-0.4), offsetVert: Float(0.5), image: #imageLiteral(resourceName: "top_info_left")) //(Positive, Positive) -> topRight
            self.place2DImage(width: 0.55, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.4), offsetVert: Float(0.5), image: #imageLiteral(resourceName: "top_info_right")) //(Positive, Positive) -> topRight
            self.place2DImage(width: 0.27, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.0), offsetVert: Float(0.5), image: #imageLiteral(resourceName: "top_info_score")) //(Positive, Positive) -> topRight*/
            
            /*
            self.place2DImage(width: 1.00, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.0), offsetVert: Float(0.35), image: #imageLiteral(resourceName: "top_widgets-15"))
            self.place2DImage(width: 0.20, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0), offsetVert: Float(-0.35), image: #imageLiteral(resourceName: "widgets-2"))
            
            
            self.place2DImage(width: 0.25, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(-0.5), offsetVert: Float(-0.35), image: #imageLiteral(resourceName: "widgets-6"))
            self.place2DImage(width: 0.3, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(-0.6), offsetVert: Float(0.05), image: #imageLiteral(resourceName: "widgets-9"))
            self.place2DImage(width: 0.4, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.6), offsetVert: Float(0.15), image: #imageLiteral(resourceName: "widgets-10"))
            self.place2DImage(width: 0.4, vecNormal: vecNormal!, vecToCenter: vecToRectCenter!, offsetHoriz: Float(0.6), offsetVert: Float(-0.35), image: #imageLiteral(resourceName: "widgets-11"))*/
            
        }
    }
    
    func removeAllChilds(){
        //self.sceneView.scene.rootNode.childNodes.removeAll()
        for node in self.nodes{
            node.removeFromParentNode()
        }
    }
    
}
