/*
See LICENSE folder for this sample’s licensing information.

Abstract:
ARSCNViewDelegate interactions for `ViewController`.
*/

import ARKit

extension ViewController: ARSCNViewDelegate, ARSessionDelegate {
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        
        if(aimode == 0){
            let isAnyObjectInView = virtualObjectLoader.loadedObjects.contains { object in
                return sceneView.isNode(object, insideFrustumOf: sceneView.pointOfView!)
            }
            
            DispatchQueue.main.async {
                self.virtualObjectInteraction.updateObjectToCurrentTrackingPosition()
                self.updateFocusSquare(isObjectVisible: isAnyObjectInView)
            }
            
            // If the object selection menu is open, update availability of items
            if objectsViewController != nil {
                let planeAnchor = focusSquare.currentPlaneAnchor
                objectsViewController?.updateObjectAvailability(for: planeAnchor)
            }
            
            // If light estimation is enabled, update the intensity of the directional lights
            if let lightEstimate = session.currentFrame?.lightEstimate {
                sceneView.updateDirectionalLighting(intensity: lightEstimate.ambientIntensity, queue: updateQueue)
            } else {
                sceneView.updateDirectionalLighting(intensity: 1000, queue: updateQueue)
            }
        }
        else{
            addObjectButton.isHidden = true
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    
        if(aimode == 0){
            guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
            DispatchQueue.main.async {
                self.statusViewController.cancelScheduledMessage(for: .planeEstimation)
                self.statusViewController.showMessage("SURFACE DETECTED")
                if self.virtualObjectLoader.loadedObjects.isEmpty {
                    self.statusViewController.scheduleMessage("TAP + TO PLACE AN OBJECT", inSeconds: 7.5, messageType: .contentPlacement)
                }
            }
            updateQueue.async {
                for object in self.virtualObjectLoader.loadedObjects {
                    object.adjustOntoPlaneAnchor(planeAnchor, using: node)
                }
            }
        }
        else{
            addObjectButton.isHidden = true
            
            if anchor.isKind(of: ARImageAnchor.self){
                guard let imageAnchor = anchor as? ARImageAnchor else { return }
                let referenceImage = imageAnchor.referenceImage
                updateQueue.async {
                    
                    // Create a plane to visualize the initial position of the detected image.
                    let plane = SCNPlane(width: referenceImage.physicalSize.width,
                                         height: referenceImage.physicalSize.height)
                    let planeNode = SCNNode(geometry: plane)
                    planeNode.opacity = 0.25
                    
                    /*
                     `SCNPlane` is vertically oriented in its local coordinate space, but
                     `ARImageAnchor` assumes the image is horizontal in its local space, so
                     rotate the plane to match.
                     */
                    planeNode.eulerAngles.x = -.pi / 2
                    
                    /*
                     Image anchors are not tracked after initial detection, so create an
                     animation that limits the duration for which the plane visualization appears.
                     */
                    planeNode.runAction(self.imageHighlightAction)
                    
                    // Add the plane visualization to the scene.
                    node.addChildNode(planeNode)
                    
                    let overlayNode = self.getNode(withImageName: referenceImage.name!)
                    //                let secondNode = self.getNode(withImageName: referenceImage.name!)
                    overlayNode.opacity = 1
                    overlayNode.position.y = 0
                    
                    //                secondNode.opacity = 1
                    //                secondNode.position.x = 0.5
                    //                secondNode.eulerAngles.x = -.pi/2
                    
                    node.addChildNode(overlayNode)
                    //                node.addChildNode(secondNode)
                }
                
                DispatchQueue.main.async {
                    let imageName = referenceImage.name ?? ""
                    self.statusViewController.cancelAllScheduledMessages()
                    self.statusViewController.showMessage("Detected image “\(imageName)”")
                }
            }
        }
    }
    
    var imageHighlightAction: SCNAction {
        return .sequence([
            .wait(duration: 0.25),
            .fadeOpacity(to: 0.85, duration: 0.25),
            .fadeOpacity(to: 0.15, duration: 0.25),
            .fadeOpacity(to: 0.85, duration: 0.25),
            .fadeOut(duration: 0.5),
            .removeFromParentNode()
            ])
    }
    
    
    func getNode(withImageName name: String) -> SCNNode {
        var node = SCNNode()
        switch name {
        case "beaker":
            node = self.beakerNode.clone()
            node.scale = SCNVector3(0.0002, 0.0002, 0.0002)
            //        case "Snow Mountain":
            //            node = mountainNode
            //        case "Trees In the Dark":
        //            node = treeNode
        default:
            break
        }
        return node
    }
    
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        
        if(aimode == 0){
            updateQueue.async {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    for object in self.virtualObjectLoader.loadedObjects {
                        object.adjustOntoPlaneAnchor(planeAnchor, using: node)
                    }
                } else {
                    if let objectAtAnchor = self.virtualObjectLoader.loadedObjects.first(where: { $0.anchor == anchor }) {
                        objectAtAnchor.simdPosition = anchor.transform.translation
                        objectAtAnchor.anchor = anchor
                    }
                }
            }
        }
        else{
            addObjectButton.isHidden = true
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        statusViewController.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)
        
        switch camera.trackingState {
        case .notAvailable, .limited:
            statusViewController.escalateFeedback(for: camera.trackingState, inSeconds: 3.0)
        case .normal:
            statusViewController.cancelScheduledMessage(for: .trackingStateEscalation)
            
            // Unhide content after successful relocalization.
            virtualObjectLoader.loadedObjects.forEach { $0.isHidden = false }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR session failed.", message: errorMessage)
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Hide content before going into the background.
        virtualObjectLoader.loadedObjects.forEach { $0.isHidden = true }
    }
    
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        /*
         Allow the session to attempt to resume after an interruption.
         This process may not succeed, so the app must be prepared
         to reset the session if the relocalizing status continues
         for a long time -- see `escalateFeedback` in `StatusViewController`.
         */
        return true
    }
}
