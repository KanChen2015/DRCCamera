//
//  DRCCustomImagePickerController.swift
//  testSBR
//
//  Created by Kan Chen on 9/24/15.
//  Copyright © 2015 Kan Chen. All rights reserved.
//

import UIKit

@objc public protocol DRCCustomImagePickerControllerDelegate{
    func customImagePickerDidFinishPickingImage(rectImage: UIImage, detectedRectImage: UIImage?)
}

public class DRCCustomImagePickerController: UIImagePickerController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, CameraOverlayDelegate {
    var imagePicker = UIImagePickerController()
    var photoRatio : RectangleRatio?
    var detectRatio: RectangleRatio?
    public var enableImageDetecting:Bool = false
    public var customDelegate: DRCCustomImagePickerControllerDelegate?
    var parentVC: UIViewController?
//    var method = 0
    override public func viewDidLoad() {
        super.viewDidLoad()
    }
    
    public func showImagePicker(inViewController parent: UIViewController){
        if !UIImagePickerController.isCameraDeviceAvailable(UIImagePickerControllerCameraDevice.Rear){
            return
        }
        let sourceType = UIImagePickerControllerSourceType.Camera
        imagePicker.sourceType = sourceType
        
        var availableSource = UIImagePickerController.availableMediaTypesForSourceType(sourceType)
        availableSource?.removeLast()
        imagePicker.mediaTypes = availableSource!
        
        imagePicker.delegate = self
        imagePicker.showsCameraControls = false
        let bundle = NSBundle(forClass: DRCCustomImagePickerController.classForCoder())
        let xibs = bundle.loadNibNamed("CameraOverlay", owner: nil, options: nil)
        
//        let xibs = NSBundle.mainBundle().loadNibNamed("CameraOverlay", owner: nil, options: nil)
        let overlayView = xibs.first as? CameraOverlay
        overlayView?.frame = imagePicker.cameraOverlayView!.frame
        imagePicker.cameraOverlayView = overlayView
        overlayView?.delegate = self
//        overlayView?.method = self.method
        setCameraCenter()
        
        self.parentVC = parent
        parentVC!.presentViewController(imagePicker, animated: true, completion: nil)
    }
    
    private func setCameraCenter(){
        if UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.Phone{
            var transform = self.imagePicker.cameraViewTransform
            let y = (UIScreen.mainScreen().bounds.height - (UIScreen.mainScreen().bounds.width * 4 / 3)) / 2
            transform.ty = y
            self.imagePicker.cameraViewTransform = transform
        }

    }
    
    public func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]) {
        let image = info[UIImagePickerControllerOriginalImage] as! UIImage

        NSNotificationCenter.defaultCenter().postNotificationName("startProcessing", object: nil)
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0)) { () -> Void in
            print(image.imageOrientation.rawValue)
            let rotatedPhoto: UIImage = ImageHandler.scaleAndRotateImage(image)
            
            //                let imageRef3 = CGImageCreateWithImageInRect(rotatedPhoto.CGImage, CGRectMake(image.size.width * self.photoRatio!.x, image.size.height * self.photoRatio!.y, image.size.width * self.photoRatio!.wp, image.size.height * self.photoRatio!.hp))
            
            let rect = CGRectMake(rotatedPhoto.size.width * self.photoRatio!.x, rotatedPhoto.size.height * self.photoRatio!.y, rotatedPhoto.size.width * self.photoRatio!.wp, rotatedPhoto.size.height * self.photoRatio!.hp)
            let imageRef3 = CGImageCreateWithImageInRect(rotatedPhoto.CGImage, rect)
            let rectImage = UIImage(CGImage: imageRef3!)
            let detectedRect : UIImage?
            if let detectRatio = self.detectRatio{
                let detectRect = CGRectMake(rotatedPhoto.size.width * detectRatio.x,
                    rotatedPhoto.size.height * detectRatio.y,
                    rotatedPhoto.size.width * detectRatio.wp,
                    rotatedPhoto.size.height * detectRatio.hp)
                let detectedImageRef = CGImageCreateWithImageInRect(rotatedPhoto.CGImage, detectRect)
                let detectedImage = UIImage(CGImage: detectedImageRef!)
                detectedRect = self.detect(detectedImage)
            }else{
                detectedRect = self.detect(rectImage)
            }
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.parentVC?.dismissViewControllerAnimated(true, completion: { () -> Void in
                    self.customDelegate?.customImagePickerDidFinishPickingImage(rectImage, detectedRectImage: detectedRect)
                })
            })
        }

    }
    
    //MARK: - OverlayDelegate
    func cancelFromImagePicker() {
        self.parentVC!.dismissViewControllerAnimated(true, completion: nil)
    }
    func saveInImagePicker(ratio: RectangleRatio, detectRatio: RectangleRatio?) {
        imagePicker.takePicture()
        self.photoRatio = ratio
        self.detectRatio = detectRatio
    }
    
    func detect(image: UIImage) -> UIImage?{
        if !enableImageDetecting {
            return nil
        }
        let detector = CIDetector(ofType: CIDetectorTypeRectangle, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorMinFeatureSize: 0.2])
        
        let imageCI = CIImage(image: image)!
        let opts = [CIDetectorAspectRatio: 1.6]
        let features = detector.featuresInImage(imageCI, options: opts) as! [CIRectangleFeature]
        if features.count == 0 {
            return nil
        }
        if features.count > 1{
            print("we found \(features.count) features")
        }
        //rotate it
        let f = features[0]
        var x = (f.topRight.x - f.topLeft.x)
        var y = (f.topRight.y - f.topLeft.y)
        var w = sqrt( x*x + y*y)
        var slopeTop =  y/x
        
        x = (f.bottomRight.x - f.bottomLeft.x)
        y = (f.bottomRight.y - f.bottomLeft.y)
        let bottomSlope = y/x
        slopeTop = (slopeTop + bottomSlope)/2
        let wBottom = sqrt( x*x + y*y)
        
        let degree = 180*(atan(Double(bottomSlope)) / M_PI )
        
        x = (f.topLeft.x - f.bottomLeft.x)
        y = (f.topLeft.y - f.bottomLeft.y)
        var h = sqrt( x*x + y*y)
        x = (f.topRight.x - f.bottomRight.x)
        y = (f.topRight.y - f.bottomRight.y)
        let hRight = sqrt( x*x + y*y)

//        h = (h + hRight)/2
//        w = (w + wBottom)/2
        h = max(h, hRight)
        w = max(w, wBottom)
        let cardCI = cropCardByFeature(imageCI, feature: features[0])
        let context = CIContext(options: nil)
        let cgImage: CGImageRef = context.createCGImage(cardCI, fromRect: cardCI.extent)
        var card:UIImage = UIImage(CGImage: cgImage)
    
       
        card = card.imageRotatedByDegrees(CGFloat(degree), flip: false)
//        let cardRotatedCI = CIImage(image: card)!
        let centerX = card.size.width / 2
        let centerY = card.size.height / 2
        let cardRef = CGImageCreateWithImageInRect(card.CGImage, CGRectMake(centerX - w/2 , centerY - h/2, w , h ))
        let card2 = UIImage(CGImage: cardRef!)
//        let newF = detector.featuresInImage(cardRotatedCI, options: opts) as! [CIRectangleFeature]
//        
//        let aa = cropCardByFeature(cardRotatedCI, feature: newF[0])
//        let context2 = CIContext(options: nil)
//        let aaImage: CGImageRef = context2.createCGImage(aa, fromRect: aa.extent)
//        let card2:UIImage = UIImage(CGImage: aaImage)
        
        
        self.testImage = card2
        
        let resultImage = detectImage(image, features: features)
        let resultOverlay = detectImageWithOverlay(imageCI, features: features)
        self.overlay = resultOverlay
//        return resultImage
//        return card2
//        for f:CIRectangleFeature in features{
//            var overlay = CIImage(color: CIColor(color: UIColor(red: 1, green: 0, blue: 0, alpha: 0.6)))
//            overlay = overlay.imageByCroppingToRect(image.extent)
//            overlay = overlay.imageByApplyingFilter("CIPerspectiveTransformWithExtent", withInputParameters: ["inputExtent": CIVector(x: 0, y: 0, z: 1, w: 1),
//                "inputTopLeft": CIVector(CGPoint: f.topLeft), "inputTopRight": CIVector(CGPoint: f.topRight), "inputBottomLeft": CIVector(CGPoint: f.bottomLeft),"inputBottomRight": CIVector(CGPoint: f.bottomRight)])
//            result = overlay.imageByCompositingOverImage(result)
//
//        }
        return ImageHandler.getImageCorrectedPerspectiv(imageCI, feature: f)
//        let result2 = image
//        var overlay = CIImage(color: CIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.7))
//        overlay = overlay.imageByCroppingToRect(features[0].bounds)
//        
//        let ciimagewithoverlay = overlay.imageByCompositingOverImage(result2)
//        resultImage.image = UIImage(CIImage:ciimagewithoverlay)
        

    }
    public var overlay: UIImage?
    public var testImage: UIImage?
    
    func detectImageWithOverlay(ciImage:CIImage,features: [CIRectangleFeature]) -> UIImage{
        let f = features[0]
        var overlay = CIImage(color: CIColor(color: UIColor(red: 1, green: 0, blue: 0, alpha: 0.6)))
        overlay = overlay.imageByCroppingToRect(ciImage.extent)
        
        overlay = overlay.imageByApplyingFilter("CIPerspectiveTransformWithExtent",
            withInputParameters: ["inputExtent": CIVector(CGRect: ciImage.extent),
                "inputTopLeft": CIVector(CGPoint: f.topLeft),
                "inputTopRight": CIVector(CGPoint: f.topRight),
                "inputBottomLeft": CIVector(CGPoint: f.bottomLeft),
                "inputBottomRight": CIVector(CGPoint: f.bottomRight)]
        )
        
        let result = UIImage(CIImage:overlay.imageByCompositingOverImage(ciImage))
        return result
    }
//    var degree:Double?
    func detectImage(image:UIImage ,features: [CIRectangleFeature]) -> UIImage{
        let featuresRect = features[0].bounds
        let imageRef = CGImageCreateWithImageInRect(image.CGImage, featuresRect)
        let resultImage = UIImage(CGImage: imageRef!)
        return resultImage
    }
    
    private func cropCardByFeature(image: CIImage, feature: CIRectangleFeature) -> CIImage{
        var card: CIImage
        card = image.imageByApplyingFilter("CIPerspectiveTransformWithExtent",
            withInputParameters: ["inputExtent": CIVector(CGRect: image.extent),
                "inputTopLeft": CIVector(CGPoint: feature.topLeft),
                "inputTopRight": CIVector(CGPoint: feature.topRight),
                "inputBottomLeft": CIVector(CGPoint: feature.bottomLeft),
                "inputBottomRight": CIVector(CGPoint: feature.bottomRight)]
        )
        card = image.imageByCroppingToRect(card.extent)
        return card
    }
}
