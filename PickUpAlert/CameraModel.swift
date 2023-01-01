//
//  CameraModel.swift
//  PickUpAlert
//
//  Created by TZUCHE HUANG on 2023/1/11.
//

import SwiftUI
import AVFoundation
import Photos
import Vision


class CameraModel: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate, ObservableObject{
    
    
    @State private var showSettingsView: Bool = false
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    var totalFrameCount: Int32 = 0
    
    let session = AVCaptureSession()
    var isSessionRunning = false
    @Published var isEnabledScan = true
    @Published var scanButtonColor: Color = Color.yellow
    @Published var isSpeakTarget = false
    
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var setupResult: SessionSetupResult = .success
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    private var selectedMovieMode10BitDeviceFormat: AVCaptureDevice.Format?
    
    
    // MARK: Recording Movies
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    @Published var isRecordEnabled = false
    @Published var recordButtonColor = Color.gray
    @Published var recordButtonImage = "circle.fill"  //"record.circle"
    
    @Published var isCapturedEnabled = false

    
    
    var isTaken = true
    
    //var session = AVCaptureSession()
    
    var alert = false
    var output = AVCapturePhotoOutput()
    var preview = AVCaptureVideoPreviewLayer()
    
    
    // Add for Vision Track
    var videoDataOutput: AVCaptureVideoDataOutput?
    var videoDataOutputQueue: DispatchQueue?
    private var detectionRequests: [VNDetectFaceRectanglesRequest]?
    private var trackingRequests: [VNTrackObjectRequest]?
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    
    var audioPlayer: AVAudioPlayer?
    // Create an AVSpeechSynthesizer object
    let synthesizer = AVSpeechSynthesizer()
    
    // Yolov5 part
    private var yolovRequests = [VNRequest]()
    var targetFound: [String]? = []
    var targetNotClear: String = ""
    var targetCaptured: [String]? = ["Huamn Face", "motorcycle", "bird", "cat", "dog", "bear", "horse", "cow", "sheep"]
    
    var bufferSize: CGSize = .zero
    var rootLayer: CALayer! = nil
    //private var previewLayer: AVCaptureVideoPreviewLayer! = nil
    private var detectionOverlay: CALayer! = nil
    
    
    
    func tenBitVariantOfFormat(activeFormat: AVCaptureDevice.Format) -> AVCaptureDevice.Format? {
        let formats = self.videoDeviceInput.device.formats
        let formatIndex = formats.firstIndex(of: activeFormat)!
        
        let activeDimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        let activeMaxFrameRate = activeFormat.videoSupportedFrameRateRanges.last?.maxFrameRate
        let activePixelFormat = CMFormatDescriptionGetMediaSubType(activeFormat.formatDescription)
        
        /*
         AVCaptureDeviceFormats are sorted from smallest to largest in resolution and frame rate.
         For each resolution and max frame rate there's a cluster of formats that only differ in pixelFormatType.
         Here, we're looking for an 'x420' variant of the current activeFormat.
        */
        if activePixelFormat != kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
            // Current activeFormat is not a 10-bit HDR format, find its 10-bit HDR variant.
            for index in formatIndex + 1..<formats.count {
                let format = formats[index]
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let maxFrameRate = format.videoSupportedFrameRateRanges.last?.maxFrameRate
                let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
                
                // Don't advance beyond the current format cluster
                if activeMaxFrameRate != maxFrameRate || activeDimensions.width != dimensions.width || activeDimensions.height != dimensions.height {
                    break
                }
                
                if pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
                    return format
                }
            }
        } else {
            return activeFormat
        }
        
        return nil
    }
    
    func check() {
        UIApplication.shared.isIdleTimerDisabled = true
        /*
         Check the video authorization status. Video access is required and audio access is optional.
         */
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant
             video access. Suspend the session queue to delay session
             setup until the access request has completed.
             
             Note that audio access will be implicitly requested when we
             create an AVCaptureDeviceInput for audio during session setup.
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            self.alert.toggle()
            // The user has previously denied access.
            setupResult = .notAuthorized
        }
        
        sessionQueue.async {
            
            self.configureSession()
            
            // For Vision Track
            self.prepareVisionRequest()
        }
    }
    
    // Call this on the session queue.
    /// - Tag: ConfigureSession
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        session.beginConfiguration()
        
        /*
         Do not create an AVCaptureMovieFileOutput when setting up the session because
         Live Photo is not supported when AVCaptureMovieFileOutput is added to the session.
         */
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            // Choose the back dual camera, if available, otherwise default to a wide angle camera.
            
            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let dualWideCameraDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                // If a rear dual camera is not available, default to the rear dual wide camera.
                defaultVideoDevice = dualWideCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // If a rear dual wide camera is not available, default to the rear wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                // If the rear wide angle camera isn't available, default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            
            do {
                try  videoDevice.lockForConfiguration()
                //print(videoDevice.activeFormat.formatDescription)
                //let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice.activeFormat.formatDescription))
                //print("bufferSize.width = \(CGFloat(dimensions.width))")
                //print("bufferSize.height = \(CGFloat(dimensions.height))")
                //print("UIScreen.main.bounds.width - \(UIScreen.main.bounds.width)")
                //print("UIScreen.main.bounds.height - \(UIScreen.main.bounds.height)")
                bufferSize.width = UIScreen.main.bounds.width //CGFloat(dimensions.width) //667
                bufferSize.height = UIScreen.main.bounds.height //CGFloat(dimensions.height) //375
                videoDevice.unlockForConfiguration()
            } catch {
                print(error)
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add an audio input device.
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
            
            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }
        } catch {
            print("Could not create audio device input: \(error)")
        }
        
        //Changge to Video record Mode
        
        
        let movieFileOutput = AVCaptureMovieFileOutput()
        
        // Add for Vision Track
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        let videoDataOutputQueue = DispatchQueue(label: "com.VisionTrack")
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        
        
        if self.session.canAddOutput(movieFileOutput) {
            self.session.beginConfiguration()
            self.session.addOutput(movieFileOutput)
            
            // Add for Vision Track
            self.session.addOutput(videoDataOutput)
            
            
            self.session.sessionPreset = .high
            
            self.selectedMovieMode10BitDeviceFormat = self.tenBitVariantOfFormat(activeFormat: self.videoDeviceInput.device.activeFormat)
            
            if self.selectedMovieMode10BitDeviceFormat != nil {
    
            }
                
            if let connection = movieFileOutput.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            
            
            // Add for Vision Track
            videoDataOutput.connection(with: .video)?.isEnabled = true
            if let captureConnection = videoDataOutput.connection(with: AVMediaType.video) {
                if captureConnection.isCameraIntrinsicMatrixDeliverySupported {
                    captureConnection.isCameraIntrinsicMatrixDeliveryEnabled = true
                }
            }
            //self.videoDataOutput = videoDataOutput
            //self.videoDataOutputQueue = videoDataOutputQueue
            
            self.session.commitConfiguration()
                
                
            self.movieFileOutput = movieFileOutput
                
            DispatchQueue.main.async {
                self.isRecordEnabled = true
                self.recordButtonColor = Color.red
                    
            }
        }
            
            
        session.commitConfiguration()
        
    }
    
    func startResumeSession() {
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }

        if !movieFileOutput.isRecording && self.isEnabledScan {
            print("stop scan")
            self.isEnabledScan = false
            self.scanButtonColor = Color.gray
        } else {
            print("start scan")
            self.isEnabledScan = true
            self.scanButtonColor = Color.yellow
        }
    }
    
    func sessionStartRunning() {

        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session if setup succeeded.
                //self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "AVCam doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    
                    //self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
                    
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    
                    //self.present(alertController, animated: true, completion: nil)
                }
            }
        }
        
        DispatchQueue.main.async {
            
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { (Timer) in
                //Timer.invalidate()
                if self.targetFound?.count ?? 0 > 0 {
                    self.targetFound?.remove(at: 0)
                    print(self.targetFound as Any)
                }
                return
            }
        }
    }
    
    
}

extension CameraModel {
    func movieRecording() {
        print("movieRecording")
        guard let movieFileOutput = self.movieFileOutput else {
            return
        }
        
        self.isRecordEnabled = false
        self.recordButtonColor = Color.gray
        
        //let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        
        sessionQueue.async {
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                // Update the orientation on the movie file output video connection before recording.
                
                let movieFileOutputConnection = movieFileOutput.connection(with: .video)
                //movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation!
                
                let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
                
                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }
                
                // Start recording video to a temporary file.
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            } else {
                movieFileOutput.stopRecording()
            }
        }
    }
    
    
    /// - Tag: DidStartRecording
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {

        // Enable the Record button to let the user stop recording.
        DispatchQueue.main.async {
            self.isRecordEnabled = true
            self.recordButtonColor = Color.red
            self.recordButtonImage = "stop.fill"
            self.rootLayer.borderColor = UIColor.red.cgColor
            self.rootLayer.borderWidth = 10
        }
    }
    
    /// - Tag: DidFinishRecording
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {

        // Note: Because we use a unique file path for each recording, a new recording won't overwrite a recording mid-save.
        func cleanup() {
            let path = outputFileURL.path
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Could not remove file at url: \(outputFileURL)")
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
                
                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        
        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        
        if success {
            // Check the authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                        
                        // Specify the location the movie was recoreded
                        //creationRequest.location = self.locationManager.location
                    }, completionHandler: { success, error in
                        if !success {
                            print("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                        }
                        cleanup()
                    }
                    )
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }
        
        // Enable the Camera and Record buttons to let the user switch camera and start another recording.
        DispatchQueue.main.async {
         
            self.isRecordEnabled = true
            self.recordButtonColor = Color.red
            self.recordButtonImage = "circle.fill"
            //self.rootLayer.borderColor = UIColor.red.cgColor
            self.rootLayer.borderWidth = 0
        }
    }
}



// MARK: Performing Vision Requests
extension CameraModel {
    
    /// - Tag: WriteCompletionHandler
    fileprivate func prepareVisionRequest() {

        self.trackingRequests = []
        var requests = [VNTrackObjectRequest]()
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: { (request, error) in

            if error != nil {
                print("FaceDetection error: \(String(describing: error)).")
            }
            
            guard let faceDetectionRequest = request as? VNDetectFaceRectanglesRequest,
                  let results = faceDetectionRequest.results else {
                    return
            }
            
            if (results.count > 0) {
                print("Face Detected!! \(results.count)")
                //print(results)
                self.recordCapturedObject()
            }
            

            
            DispatchQueue.main.async {
                // Add the observations to the tracking list
                for observation in results {
                    let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                    requests.append(faceTrackingRequest)
                    self.trackingRequests = requests
                    
                    self.chkExistTargetFound("Human Face", observation.confidence)
                }

            }
        })
        
        // Start with detection.  Find face, then track it.
        self.detectionRequests = [faceDetectionRequest]
        
        self.sequenceRequestHandler = VNSequenceRequestHandler()
        
        //self.setupVisionDrawingLayers()
        
        // Yolov5 part
        //let error: NSError! = nil
        let mlmodelcName: String = "yolov5m"  //yolov5n //"YOLOv3"    ObjectDetector
        guard let modelURL = Bundle.main.url(forResource: mlmodelcName, withExtension: "mlmodelc") else {
            print("Model file is missing!")
            return
        }
        do {
            let visionModel = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                //DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        if results.count > 0 {
                            //print(results)
                            self.drawVisionRequestResults(results)
                        }
                    }
                //})
            })
            self.yolovRequests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
    }
    
    func recordCapturedObject() {
            // Add timer to record video for 5 seconds
            if self.isCapturedEnabled {
                if  (self.movieFileOutput == nil || self.movieFileOutput?.isRecording == false)   {
                    DispatchQueue.main.async {
                        if self.isRecordEnabled {
                            self.isRecordEnabled = false
                            self.movieRecording()
                            
                            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { (Timer) in
                                Timer.invalidate()
                                if self.movieFileOutput?.isRecording == true {
                                    self.movieRecording()
                                }
                                return
                            }
                            
                        }
                    }
                }
            }
    }

    func drawVisionRequestResults(_ results: [Any]) {
        /* for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            print(objectObservation.labels[0].identifier)
        } */
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        //CATransaction.setValue(Int(2), forKey: kCATransactionAnimationDuration)
        
        totalFrameCount += 1
        if totalFrameCount % 2 == 0{
            detectionOverlay.sublayers = nil // remove all the old recognized objects
        }
        if totalFrameCount > 1000000000 {totalFrameCount = 0}
        

        //detectionOverlay.frame = CGRect(x: -187.5, y: -333.5, width: 375, height: 667)
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            //print(objectObservation)
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
            
            if topLabelObservation.confidence > 0.85 {
                //print("first \(topLabelObservation.identifier) -- \(topLabelObservation.confidence)")
                if self.targetNotClear != topLabelObservation.identifier {
                    self.targetNotClear = topLabelObservation.identifier
                    break
                }
                chkExistTargetFound(topLabelObservation.identifier, topLabelObservation.confidence)


            } else {
                continue
            }
            //print(self.targetFound as Any)
            
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            //print("\(topLabelObservation.identifier), \(objectObservation.boundingBox)--\(objectBounds)")
            
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)
            
            let textLayer = self.createTextSubLayerInBounds(objectBounds,
                                                            identifier:topLabelObservation.identifier,
                                                            confidence: topLabelObservation.confidence)
            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
            if  targetCaptured?.contains(topLabelObservation.identifier) == true {
                self.recordCapturedObject()
            }
        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    func chkExistTargetFound(_ newlyFound: String, _ confience: Float) {

        if self.targetFound == nil || self.targetFound?.contains(newlyFound) == false {
            print("\(newlyFound) -- \(confience)")
            
            // Speak the detect result
            if self.isSpeakTarget {
                let utterance = AVSpeechUtterance(string: newlyFound)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                self.synthesizer.speak(utterance)
            }
            
        } else {
            if let index = self.targetFound?.firstIndex(of: newlyFound) {
                self.targetFound?.remove(at: index)
            }
        }
        self.targetFound?.append(newlyFound)
        if self.targetFound?.count ?? 0 > 10 {
            self.targetFound?.remove(at: 0 )
        }
    }
    
    // MARK: Helper Methods for Handling Device Orientation & EXIF
    
    fileprivate func radiansForDegrees(_ degrees: CGFloat) -> CGFloat {
        return CGFloat(Double(degrees) * Double.pi / 180.0)
    }
    
    
    func exifOrientationForDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {

        switch deviceOrientation {
            
        case .portraitUpsideDown:
            return .rightMirrored
            
        case .landscapeLeft:
            return .upMirrored
            
        case .landscapeRight:
            return .downMirrored
            
        default:
            return .leftMirrored
            
        }
    }
    
    
    func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
        //Fixed to portalitUp
        //print("UIDevice.current.orientation -- \(UIDevice.current.orientation)")
        return .leftMirrored //exifOrientationForDeviceOrientation(UIDevice.current.orientation)
    }
    

    
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    /// - Tag: PerformRequests
    // Handle delegate method callback on receiving a sample buffer.
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        //totalFrameCount += 1
        //if totalFrameCount % 2 != 0{ return }
        //if totalFrameCount > 1000000000 {totalFrameCount = 0}

        if self.isEnabledScan {
            var requestHandlerOptions: [VNImageOption: AnyObject] = [:]
            
            let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
            if cameraIntrinsicData != nil {
                requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
            }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                print("Failed to obtain a CVPixelBuffer for the current output frame.")
                return
            }
            
            
            let exifOrientation = self.exifOrientationForCurrentDeviceOrientation()

            //connection.videoOrientation = .landscapeRight
            //print("connection.videoOrientation - \(connection.videoOrientation)")
            //connection.videoOrientation = AVCaptureVideoOrientation.portrait
            
            guard let requests = self.trackingRequests, !requests.isEmpty else {
                // No tracking object detected, so perform initial detection
                let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                                orientation: exifOrientation,
                                                                options: requestHandlerOptions)
                
                do {
                    guard let detectRequests = self.detectionRequests else {
                        return
                    }
                    try imageRequestHandler.perform(detectRequests)
                    //Yolov5 part
                    try imageRequestHandler.perform(self.yolovRequests)
                } catch let error as NSError {
                    NSLog("Failed to perform FaceRectangleRequest: %@", error)
                }
                
                return
            }
            
            
            do {
                try self.sequenceRequestHandler.perform(requests,
                                                        on: pixelBuffer,
                                                        orientation: exifOrientation)
            } catch let error as NSError {
                NSLog("Failed to perform SequenceRequest: %@", error)
            } 
            
            // Setup the next round of tracking.
            var newTrackingRequests = [VNTrackObjectRequest]()
            for trackingRequest in requests {
                
                guard let results = trackingRequest.results else {
                    return
                }
                
                guard let observation = results[0] as? VNDetectedObjectObservation else {
                    return
                }
                
                if !trackingRequest.isLastFrame {
                    if observation.confidence > 0.2 {
                        trackingRequest.inputObservation = observation
                    } else {
                        trackingRequest.isLastFrame = true
                    }
                    newTrackingRequests.append(trackingRequest)
                }
            }
            self.trackingRequests = newTrackingRequests
            
            if newTrackingRequests.isEmpty {
                // Nothing to track, so abort.
                return
            }
            
            // Perform face landmark tracking on detected faces.
            var faceLandmarkRequests = [VNDetectFaceLandmarksRequest]()
            
            // Perform landmark detection on tracked faces.
            for trackingRequest in newTrackingRequests {
                
                let faceLandmarksRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request, error) in
                    
                    if error != nil {
                        print("FaceLandmarks error: \(String(describing: error)).")
                    }
                    
                    guard let landmarksRequest = request as? VNDetectFaceLandmarksRequest,
                          let results = landmarksRequest.results else {
                        return
                    }
                    
                    // Perform all UI updates (drawing) on the main queue, not the background queue on which this handler is being called.
                    DispatchQueue.main.async {
                        //self.drawFaceObservations(results)
                    }
                })
                
                guard let trackingResults = trackingRequest.results else {
                    return
                }
                
                guard let observation = trackingResults[0] as? VNDetectedObjectObservation else {
                    return
                }
                let faceObservation = VNFaceObservation(boundingBox: observation.boundingBox)
                faceLandmarksRequest.inputFaceObservations = [faceObservation]
                
                // Continue to track detected facial landmarks.
                faceLandmarkRequests.append(faceLandmarksRequest)
                
                let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                                orientation: exifOrientation,
                                                                options: requestHandlerOptions)
                
                do {
                    try imageRequestHandler.perform(faceLandmarkRequests)
                } catch let error as NSError {
                    NSLog("Failed to perform FaceLandmarkRequest: %@", error)
                }
            }
        } else {

            CATransaction.begin()
            self.detectionOverlay.sublayers = nil
            CATransaction.commit()
        }
    }
    
    func setupLayers() {

        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = rootLayer.frame

        detectionOverlay.masksToBounds = true
        //print("rootLayer.bounds.midX = \(rootLayer.bounds.midX)")
        //print("rootLayer.bounds.midY = \(rootLayer.bounds.midY)")

        //print("detectionOverlay.isHidden = \(detectionOverlay.isHidden)")
        //detectionOverlay.borderWidth = 5
        //detectionOverlay.borderColor = UIColor.blue.cgColor
        rootLayer.addSublayer(detectionOverlay)
        

    }
    
    func updateLayerGeometry() {
        
        let bounds = rootLayer.bounds
        var scale: CGFloat
        //preview.borderWidth = 3
        //preview.borderColor = CGColor(red: CGFloat.random(in: 0...1), green: 0, blue: 0, alpha: 1) //UIColor.green.cgColor
        
        let xScale: CGFloat = bounds.size.width / bufferSize.width
        let yScale: CGFloat = bounds.size.height / bufferSize.height
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        //detectionOverlay.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: -scale, y: scale))
        detectionOverlay.setAffineTransform(CGAffineTransform(scaleX: -scale, y: -scale))
        // center the layer
        detectionOverlay.position = CGPoint(x: bounds.midX , y: bounds.midY)
        
        
        CATransaction.commit()
    
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        //textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.bounds = CGRect(x: 0, y: 0, width: 120, height: 50)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        //textLayer.position = CGPoint(x: 0, y: 0)
        textLayer.shadowOpacity = 1
        textLayer.shadowRadius = 5
        textLayer.shadowOffset = CGSize(width: 4, height: 3)
        textLayer.shadowColor = UIColor.white.cgColor
        //textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.foregroundColor = UIColor.black.cgColor
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        let orientation = exifOrientationForDeviceOrientation(UIDevice.current.orientation)

        var rotateIndex: CGFloat
        switch orientation {
        case .rightMirrored:
            rotateIndex = 0.5
        case .downMirrored:
            rotateIndex = 2.0
        case .upMirrored:
            rotateIndex = -2.0
        default:
            rotateIndex = -1.0
        }
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / rotateIndex)).scaledBy(x: 1.0, y: 1.0))
        //textLayer.setAffineTransform(CGAffineTransform(scaleX: -1.0 , y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        //print("bounds -- \(bounds)")
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        //shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.2])
        shapeLayer.borderColor = UIColor.yellow.cgColor
        shapeLayer.borderWidth = 3
        shapeLayer.cornerRadius = 7


        return shapeLayer
    }
}


