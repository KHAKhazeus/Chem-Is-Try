/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import ARKit
import SceneKit
import UIKit

class ViewController: UIViewController {
    
    // MARK: IBOutlets
    
    @IBOutlet var sceneView: VirtualObjectARView!
    
    @IBOutlet weak var addObjectButton: UIButton!
    
    @IBOutlet weak var blurView: UIVisualEffectView!
    
    @IBOutlet weak var spinner: UIActivityIndicatorView!

    // MARK: - UI Elements
    
    var aimode: Int = 0;
    
    var focusSquare = FocusSquare()
    
    /// The view controller that displays the status and "restart experience" UI.
    lazy var statusViewController: StatusViewController = {
        return childViewControllers.lazy.compactMap({ $0 as? StatusViewController }).first!
    }()
    
    /// The view controller that displays the virtual object selection menu.
    var objectsViewController: VirtualObjectSelectionViewController?
    
    // MARK: - ARKit Configuration Properties
    
    /// A type which manages gesture manipulation of virtual content in the scene.
    lazy var virtualObjectInteraction = VirtualObjectInteraction(sceneView: sceneView)
    
    /// Coordinates the loading and unloading of reference nodes for virtual objects.
    let virtualObjectLoader = VirtualObjectLoader()
    
    /// Marks if the AR experience is available for restart.
    var isRestartAvailable = true
    
    /// A serial queue used to coordinate adding or removing nodes from the scene.
    let updateQueue = DispatchQueue(label: "com.example.apple-samplecode.arkitexample.serialSceneKitQueue")
    
    var screenCenter: CGPoint {
        let bounds = sceneView.bounds
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
    
    /// Convenience accessor for the session owned by ARSCNView.
    var session: ARSession {
        return sceneView.session
    }
    
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.session.delegate = self

        if(aimode == 0){
            // Set up scene content.
            setupCamera()
            sceneView.scene.rootNode.addChildNode(focusSquare)
            
            sceneView.setupDirectionalLighting(queue: updateQueue)
            
            // Hook up status view controller callback(s).
            statusViewController.restartExperienceHandler = { [unowned self] in
                self.restartExperience()
            }
            
            statusViewController.changeExperienceHandler = {
                [unowned self] in
                self.changeExperience()
            }
            
            
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showVirtualObjectSelectionViewController))
            // Set the delegate to ensure this gesture is only used when there are no virtual objects in the scene.
            tapGesture.delegate = self
            sceneView.addGestureRecognizer(tapGesture)
        }
        else{
            sceneView.showsStatistics = true
            
            // Hook up status view controller callback(s).
            statusViewController.restartExperienceHandler = { [unowned self] in
                self.restartExperience()
            }
            statusViewController.changeExperienceHandler = {
                [unowned self] in
                self.changeExperience()
            }
            addObjectButton.isHidden = true
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Prevent the screen from being dimmed to avoid interuppting the AR experience.
        if(aimode == 0){
            UIApplication.shared.isIdleTimerDisabled = true
            
            // Start the `ARSession`.
            resetTracking()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        session.pause()
    }

    // MARK: - Scene content setup

    func setupCamera() {
        guard let camera = sceneView.pointOfView?.camera else {
            fatalError("Expected a valid `pointOfView` from the scene.")
        }

        /*
         Enable HDR camera settings for the most realistic appearance
         with environmental lighting and physically based materials.
         */
        camera.wantsHDR = true
        camera.exposureOffset = -1
        camera.minimumExposure = -1
        camera.maximumExposure = 3
    }

    // MARK: - Session management
    
    /// Creates a new AR configuration to run on the `session`.
    func resetTracking() {
        virtualObjectInteraction.selectedObject = nil
        
        if(aimode == 0){
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            if #available(iOS 12.0, *) {
                configuration.environmentTexturing = .automatic
            }
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            
            statusViewController.scheduleMessage("FIND A SURFACE TO PLACE AN OBJECT", inSeconds: 7.5, messageType: .planeEstimation)
        }
        else{
            guard let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
                fatalError("Missing expected asset catalog resources.")
            }
            
            let configuration = ARImageTrackingConfiguration()
            configuration.trackingImages = referenceImages
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            
            statusViewController.scheduleMessage("Look around to detect images", inSeconds: 7.5, messageType: .contentPlacement)
            focusSquare.hide()
            addObjectButton.isHidden = true
        }
    }

    // MARK: - Focus Square

    func updateFocusSquare(isObjectVisible: Bool) {
        if isObjectVisible {
            focusSquare.hide()
        } else {
            focusSquare.unhide()
            statusViewController.scheduleMessage("TRY MOVING LEFT OR RIGHT", inSeconds: 5.0, messageType: .focusSquare)
        }
        
        // Perform hit testing only when ARKit tracking is in a good state.
        if let camera = session.currentFrame?.camera, case .normal = camera.trackingState,
            let result = self.sceneView.smartHitTest(screenCenter) {
            updateQueue.async {
                self.sceneView.scene.rootNode.addChildNode(self.focusSquare)
                self.focusSquare.state = .detecting(hitTestResult: result, camera: camera)
            }
            addObjectButton.isHidden = false
            statusViewController.cancelScheduledMessage(for: .focusSquare)
        } else {
            updateQueue.async {
                self.focusSquare.state = .initializing
                self.sceneView.pointOfView?.addChildNode(self.focusSquare)
            }
            addObjectButton.isHidden = true
        }
    }
    
    // MARK: - Error handling
    
    func displayErrorMessage(title: String, message: String) {
        // Blur the background.
        blurView.isHidden = false
        
        // Present an alert informing about the error that has occurred.
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.blurView.isHidden = true
            self.resetTracking()
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }
    
    let fadeDuration: TimeInterval = 0.3
    let rotateDuration: TimeInterval = 3
    let waitDuration: TimeInterval = 0.5
    
    lazy var SpinAction: SCNAction = {
        return .sequence([
            .fadeIn(duration: fadeDuration),
            .rotateBy(x: 0, y: 0, z: CGFloat.pi * 360 / 180, duration: rotateDuration),
            .wait(duration: waitDuration)
            ])
    }()
    
    lazy var beakerNode: SCNNode = {
        guard let scene = SCNScene(named: "烧杯.scn", inDirectory: "Models.scnassets/烧杯", options: nil),
            let node = scene.rootNode.childNode(withName: "烧杯", recursively: false) else { return SCNNode() }
        let scaleFactor = 0.2
        node.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)
        node.eulerAngles.x = 0
        return node
    }()

}
