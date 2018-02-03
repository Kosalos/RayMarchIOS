import UIKit
import Metal

let scrnSz:[CGPoint] = [ CGPoint(x:768,y:1024), CGPoint(x:834,y:1112), CGPoint(x:1024,y:1366) ] // portrait
let scrnIndex = 0
let scrnLandscape:Bool = false

class ViewController: UIViewController {
    var control = Control()
    var cBuffer:MTLBuffer! = nil
    
    var timer = Timer()
    var outTexture: MTLTexture!
    let bytesPerPixel: Int = 4
    var pipeline1: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Queue")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    var circleMove:Bool = false

    let SIZE:Int = 800

    let threadGroupCount = MTLSizeMake(20,20, 1)   // integer factor of image size (800,800)
    lazy var threadGroups: MTLSize = { MTLSizeMake(SIZE / threadGroupCount.width, SIZE / threadGroupCount.height, 1) }()

    @IBOutlet var dCameraXY: DeltaView!
    @IBOutlet var sCameraZ: SliderView!
    @IBOutlet var dFocusXY: DeltaView!
    @IBOutlet var sFocusZ: SliderView!
    @IBOutlet var sZoom: SliderView!
    @IBOutlet var sPower: SliderView!
    @IBOutlet var sDist: SliderView!
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var resetButton: UIButton!
    @IBOutlet var formulaSeg: UISegmentedControl!
    @IBOutlet var circleButton: UIButton!

    @IBAction func resetButtonPressed(_ sender: UIButton) { reset() }
    @IBAction func formulaChanged(_ sender: UISegmentedControl) {  control.formula = Int32(sender.selectedSegmentIndex) }
    
    var cameraX:Float = 0.0
    var cameraY:Float = 0.0
    var cameraZ:Float = 0.0
    var focusX:Float = 0.0
    var focusY:Float = 0.0
    var focusZ:Float = 0.0
    var dist1000:Float = 0.0

    var sList:[SliderView]! = nil
    var dList:[DeltaView]! = nil

    override var prefersStatusBarHidden: Bool { return true }
    
    //MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
            let defaultLibrary:MTLLibrary! = self.device.makeDefaultLibrary()
            guard let kf1 = defaultLibrary.makeFunction(name: "rayMarchShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
        }
        catch { fatalError("error creating pipelines") }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: SIZE,
            height: SIZE,
            mipmapped: false)
        outTexture = self.device.makeTexture(descriptor: textureDescriptor)!
        
        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.rotated), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
        rotated()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        sList = [ sCameraZ,sFocusZ,sZoom,sPower,sDist ]
        dList = [ dCameraXY,dFocusXY ]

        let cameraMin:Float = -5
        let cameraMax:Float = 5
        let focusMin:Float = -10
        let focusMax:Float = 10
        let zoomMin:Float = 0.001
        let zoomMax:Float = 1
        let powerMin:Float = 1.5
        let powerMax:Float = 20
        let distMin:Float = 0.00001 * 1000
        let distMax:Float = 0.03 * 1000

        dCameraXY.initializeFloat1(&cameraX, cameraMin, cameraMax, 1, "Cam XY")
        dCameraXY.initializeFloat2(&cameraY)
        sCameraZ.initializeFloat(&cameraZ, .delta, cameraMin, cameraMax, 1, "Cam Z")
        dFocusXY.initializeFloat1(&focusX, focusMin,focusMax, 1, "Foc XY")
        dFocusXY.initializeFloat2(&focusY)
        sFocusZ.initializeFloat(&focusZ, .delta, focusMin, focusMax, 1, "Foc Z")
        sZoom.initializeFloat(&control.zoom, .delta, zoomMin, zoomMax, 2, "Zoom")
        sPower.initializeFloat(&control.power, .delta, powerMin, powerMax, 1, "Power")
        sDist.initializeFloat(&dist1000, .direct, distMin, distMax, 1, "Dist1000")

        reset()
        timer = Timer.scheduledTimer(timeInterval: 1.0/30.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
    }
    
    //MARK: -
    
    var oldXS:CGFloat = 0
    
    @objc func rotated() {
        let xs:CGFloat = view.bounds.width
        let ys:CGFloat = view.bounds.height
//        let xs = scrnLandscape ? scrnSz[scrnIndex].y : scrnSz[scrnIndex].x
//        let ys = scrnLandscape ? scrnSz[scrnIndex].x : scrnSz[scrnIndex].y

        if xs == oldXS { return }
        oldXS = xs
        
        let bys:CGFloat = 35    // slider height
        let gap:CGFloat = 10

        if ys > xs {    // portrait
            let left:CGFloat = xs / 6
            let sz = xs - 10
            imageView.frame = CGRect(x:5, y:5, width:sz, height:sz)
            
            let by:CGFloat = sz + 30  // top of widgets
            var x:CGFloat = left
            
            let cxs:CGFloat = xs / 5
            dCameraXY.frame = CGRect(x:x, y:by, width:cxs, height:cxs)
            sCameraZ.frame  = CGRect(x:x, y:by+cxs+5, width:cxs, height:bys)
            x += cxs + gap
            dFocusXY.frame = CGRect(x:x, y:by, width:cxs, height:cxs)
            sFocusZ.frame  = CGRect(x:x, y:by+cxs+5, width:cxs, height:bys)
            
            x += cxs + 20
            var y = by
            sZoom.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            sPower.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            sDist.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            formulaSeg.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            circleButton.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            resetButton.frame = CGRect(x:x, y:y, width:80, height:bys)
        }
        else {          // landscape
            let sz = ys - 10
            let x:CGFloat = sz + 30
            var y:CGFloat = 50

            imageView.frame = CGRect(x:5, y:5, width:sz, height:sz)
            
            let cxs:CGFloat = 150 * xs / 1024
            dCameraXY.frame = CGRect(x:x, y:y, width:cxs, height:cxs); y += cxs+5
            sCameraZ.frame  = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + 30
            dFocusXY.frame = CGRect(x:x, y:y, width:cxs, height:cxs); y += cxs+5
            sFocusZ.frame  = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + 30
            sZoom.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            sPower.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            sDist.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            formulaSeg.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            circleButton.frame = CGRect(x:x, y:y, width:cxs, height:bys); y += bys + gap
            resetButton.frame = CGRect(x:x, y:y, width:80, height:bys)
        }
    }
    
    func reset() {
        control.camera = vector_float3(1.59,3.89,0.75)
        control.focus = vector_float3(-0.52,-1.22,-0.31)
        control.zoom = 0.6141
        control.size = Int32(SIZE)     // image size
        control.bailout = 2
        control.iterations = 100
        control.maxRaySteps = 70
        control.power = 8
        control.minimumStepDistance = 0.003
        dist1000 = control.minimumStepDistance * 1000.0

        unWrapFloat3()

        for s in sList { s.setNeedsDisplay() }
        for d in dList { d.setNeedsDisplay() }
    }
    
    //MARK: -
    
    func unWrapFloat3() {
        cameraX = control.camera.x
        cameraY = control.camera.y
        cameraZ = control.camera.z
        focusX = control.focus.x
        focusY = control.focus.y
        focusZ = control.focus.z
    }
    
    func wrapFloat3() {
        control.camera.x = cameraX
        control.camera.y = cameraY
        control.camera.z = cameraZ
        control.focus.x = focusX
        control.focus.y = focusY
        control.focus.z = focusZ
        control.minimumStepDistance = dist1000 / 1000.0
    }
    
    //MARK: -

    let bColors:[UIColor] = [ UIColor(red:0.5, green:0.5, blue:0.5, alpha:1),  UIColor(red:1, green:0, blue:0.0, alpha:1) ]
    func updateCircleButton() { circleButton.setTitleColor(bColors[Int(circleMove ? 1 : 0)], for:[]) }

    var circleDistance = Float()
    var circleAngle = Float()
    
    @IBAction func circleButtonPressed(_ sender: UIButton) {
        circleMove = !circleMove
        updateCircleButton()
        
        if circleMove {
            circleDistance = sqrtf(control.camera.x * control.camera.x + control.camera.z * control.camera.z)
            circleAngle = Float.pi + atan2f(control.focus.z - control.camera.z, control.focus.x - control.camera.x)
            unWrapFloat3()
        }
    }
    
    //MARK: -
    var angle:Float = 0

    @objc func timerHandler() {
        
        if circleMove {
            control.camera.x = cosf(circleAngle) * circleDistance
            control.camera.z = sinf(circleAngle) * circleDistance
            unWrapFloat3()
            circleAngle += 0.01
            dCameraXY.setNeedsDisplay()
        }
        
        for s in sList { _ = s.update() }
        for d in dList { _ = d.update() }

        // update light position
        control.light.x = sinf(angle) * 5
        control.light.y = sinf(angle/3) * 5
        control.light.z = -12 + sinf(angle/2) * 5
        angle += 0.05
        updateImage()
    }
    
    func updateImage() {
        queue.async {
            self.calcRayMarch()
            DispatchQueue.main.async { self.imageView.image = self.image(from: self.outTexture) }
        }
    }
    
    //MARK: -

    func calcRayMarch() {
        wrapFloat3()
        control.minimumStepDistance = dist1000 / 1000.0
        
        cBuffer.contents().copyBytes(from: &control, count:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline1)
        commandEncoder.setTexture(outTexture, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    //MARK: -
    // edit Scheme, Options, Metal API Validation : Disabled
    //the fix is to turn off Metal API validation under Product -> Scheme -> Options
    
//    func texture(from image: UIImage) -> MTLTexture {
//        guard let cgImage = image.cgImage else { fatalError("Can't open image \(image)") }
//
//        let textureLoader = MTKTextureLoader(device: self.device)
//        do {
//            let textureOut = try textureLoader.newTexture(cgImage:cgImage)
//
//
//
//
//            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
//                pixelFormat: .bgra8Unorm_srgb, // textureOut.pixelFormat,
//                width: 2000, //textureOut.width,
//                height: 2000, //textureOut.height,
//                mipmapped: false)
//            let t:MTLTexture = self.device.makeTexture(descriptor: textureDescriptor)!
//            return t // extureOut
//        }
//        catch {
//            fatalError("Can't load texture")
//        }
//    }
    
    func image(from texture: MTLTexture) -> UIImage {
        let imageByteCount = texture.width * texture.height * bytesPerPixel
        let bytesPerRow = texture.width * bytesPerPixel
        var src = [UInt8](repeating: 0, count: Int(imageByteCount))
        
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.getBytes(&src, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let bitmapInfo = CGBitmapInfo(rawValue: (CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let context = CGContext(data: &src,
                                width: texture.width,
                                height: texture.height,
                                bitsPerComponent: bitsPerComponent,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo.rawValue)
        
        let dstImageFilter = context?.makeImage()
        
        return UIImage(cgImage: dstImageFilter!, scale: 0.0, orientation: UIImageOrientation.up)
    }
}

