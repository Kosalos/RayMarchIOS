import UIKit
import Metal
import MetalKit

class ViewController: UIViewController {
    var control = Control()
    var cBuffer:MTLBuffer! = nil
    
    let cameraMin:Float = -5
    let cameraMax:Float = 5
    let focusMin:Float = -10
    let focusMax:Float = 10
    let zoomMin:Float = -1
    let zoomMax:Float = 5
    let powerMin:Float = 2
    let powerMax:Float = 12

    var cameraDelta = float3()
    var focusDelta = float3()
    var zoomDelta = Float()
    var powerDelta = Float()

    var reDelta:Float = 0
    var imDelta:Float = 0
    var multDelta:Float = 0
    var isScrolling:Bool = false
    var timer = Timer()
    var outTexture: MTLTexture!
    let bytesPerPixel: Int = 4
    var pipeline1: MTLComputePipelineState!
    var pipeline2: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Queue")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var defaultLibrary: MTLLibrary! = { self.device.makeDefaultLibrary() }()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    
    let SIZE:Int = 800

    let threadGroupCount = MTLSizeMake(20,20, 1)   // integer factor of image size (800,800)
    lazy var threadGroups: MTLSize = { MTLSizeMake(SIZE / threadGroupCount.width, SIZE / threadGroupCount.height, 1) }()
    
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var labelcx: UILabel!
    @IBOutlet var labelcy: UILabel!
    @IBOutlet var labelcz: UILabel!
    @IBOutlet var labelfx: UILabel!
    @IBOutlet var labelfy: UILabel!
    @IBOutlet var labelfz: UILabel!
    @IBOutlet var labelz:  UILabel!
    @IBOutlet var labelp:  UILabel!

    @IBOutlet var slidercx: UISlider!
    @IBOutlet var slidercy: UISlider!
    @IBOutlet var slidercz: UISlider!
    @IBOutlet var sliderfx: UISlider!
    @IBOutlet var sliderfy: UISlider!
    @IBOutlet var sliderfz: UISlider!
    @IBOutlet var sliderz: UISlider!
    @IBOutlet var sliderp: UISlider!

    let qcdx:Float  = 0.05  
    let zdx:Float  = 0.001
    let pdx:Float  = 0.01

    @IBAction func cxMinus(_ sender: UIButton)  { clearDeltas(); cameraDelta.x = -qcdx * control.zoom;  isScrolling = true  }
    @IBAction func cxPlus(_ sender: UIButton)   { clearDeltas(); cameraDelta.x = +qcdx * control.zoom;  isScrolling = true  }
    @IBAction func cyMinus(_ sender: UIButton)  { clearDeltas(); cameraDelta.y = -qcdx * control.zoom;  isScrolling = true  }
    @IBAction func cyPlus(_ sender: UIButton)   { clearDeltas(); cameraDelta.y = +qcdx * control.zoom;  isScrolling = true  }
    @IBAction func czMinus(_ sender: UIButton)  { clearDeltas(); cameraDelta.z = -qcdx * control.zoom;  isScrolling = true  }
    @IBAction func czPlus(_ sender: UIButton)   { clearDeltas(); cameraDelta.z = +qcdx * control.zoom;  isScrolling = true  }
    @IBAction func fxMinus(_ sender: UIButton)  { clearDeltas(); focusDelta.x = -qcdx * control.zoom;  isScrolling = true  }
    @IBAction func fxPlus(_ sender: UIButton)   { clearDeltas(); focusDelta.x = +qcdx * control.zoom;  isScrolling = true  }
    @IBAction func fyMinus(_ sender: UIButton)  { clearDeltas(); focusDelta.y = -qcdx * control.zoom;  isScrolling = true  }
    @IBAction func fyPlus(_ sender: UIButton)   { clearDeltas(); focusDelta.y = +qcdx * control.zoom;  isScrolling = true  }
    @IBAction func fzMinus(_ sender: UIButton)  { clearDeltas(); focusDelta.z = -qcdx * control.zoom;  isScrolling = true  }
    @IBAction func fzPlus(_ sender: UIButton)   { clearDeltas(); focusDelta.z = +qcdx * control.zoom;  isScrolling = true  }
    @IBAction func zMinus(_ sender: UIButton)   { clearDeltas(); zoomDelta = -zdx;  isScrolling = true  }
    @IBAction func zPlus(_ sender: UIButton)    { clearDeltas(); zoomDelta = +zdx;  isScrolling = true  }
    @IBAction func pMinus(_ sender: UIButton)   { clearDeltas(); powerDelta = -pdx;  isScrolling = true  }
    @IBAction func pPlus(_ sender: UIButton)    { clearDeltas(); powerDelta = +pdx;  isScrolling = true  }

    
    @IBAction func scrollRelease(_ sender: UIButton) { isScrolling = false}
    @IBAction func resetButtonPressed(_ sender: UIButton) { reset() }

    override var prefersStatusBarHidden: Bool { return true }
    
    func clearDeltas() {
        cameraDelta = float3()
        focusDelta = float3()
        zoomDelta = 0
        powerDelta = 0
    }

    //MARK: -

    override func viewDidLoad() {
        super.viewDidLoad()
        
        do {
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
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reset()
        timer = Timer.scheduledTimer(timeInterval: 1.0/30.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
    }
    
    func reset() {
        control.camera = vector_float3(1.59,3.89,0.75)
        control.focus = vector_float3(-0.52,-1.22,-0.31)
        control.zoom = 0.6141
        control.size = Int32(SIZE)     // image size
        control.colors = 5
        control.bailout = 2
        control.iterations = 100
        control.maxRaySteps = 70
        control.power = 8
        control.minimumStepDistance = 0.0005
        
        updateLabels()
        updateSliders()
    }
    
    func fClamp(_ v:Float, _ min:Float, _ max:Float) -> Float {
        if v < min { return min }
        if v > max { return max }
        return v
    }
    
    //MARK: -
    
    var angle:Float = 0

    @objc func timerHandler() {
        if isScrolling {
            control.camera.x = fClamp(control.camera.x + cameraDelta.x, cameraMin, cameraMax)
            control.camera.y = fClamp(control.camera.y + cameraDelta.y, cameraMin, cameraMax)
            control.camera.z = fClamp(control.camera.z + cameraDelta.z, cameraMin, cameraMax)
            control.focus.x = fClamp(control.focus.x + focusDelta.x, focusMin, focusMax)
            control.focus.y = fClamp(control.focus.y + focusDelta.y, focusMin, focusMax)
            control.focus.z = fClamp(control.focus.z + focusDelta.z, focusMin, focusMax)
            control.zoom    = fClamp(control.zoom + zoomDelta, zoomMin, zoomMax)
            control.power   = fClamp(control.power + powerDelta, powerMin, powerMax)

            updateSliders()
            updateLabels()
        }

        // update light position
        control.light.x = sinf(angle) * 5
        control.light.y = sinf(angle/3) * 5
        control.light.z = -12 + sinf(angle/2) * 5
        angle += 0.05
        updateImage()
    }
    
    @IBAction func sliderPressed(_ sender: UISlider) {
        switch sender {
        case slidercx : control.camera.x = cameraMin + (cameraMax - cameraMin) * sender.value
        case slidercy : control.camera.y = cameraMin + (cameraMax - cameraMin) * sender.value
        case slidercz : control.camera.z = cameraMin + (cameraMax - cameraMin) * sender.value
        case sliderfx : control.focus.x = focusMin + (focusMax - focusMin) * sender.value
        case sliderfy : control.focus.y = focusMin + (focusMax - focusMin) * sender.value
        case sliderfz : control.focus.z = focusMin + (focusMax - focusMin) * sender.value
        case sliderz  : control.zoom = zoomMin + (zoomMax - zoomMin) * sender.value
        case sliderp  : control.power = powerMin + (powerMax - powerMin) * sender.value
        default : break
        }

        updateLabels()
    }
    
    func updateLabels() {
        labelcx.text = String(format:"%+6.4f",control.camera.x)
        labelcy.text = String(format:"%+6.4f",control.camera.y)
        labelcz.text = String(format:"%+6.4f",control.camera.z)
        labelfx.text = String(format:"%+6.4f",control.focus.x)
        labelfy.text = String(format:"%+6.4f",control.focus.y)
        labelfz.text = String(format:"%+6.4f",control.focus.z)
        labelz.text  = String(format:"%+6.4f",control.zoom)
        labelp.text  = String(format:"%+6.4f",control.power)
    }
    
    func updateSliders() {
        slidercx.value = (control.camera.x - cameraMin) / (cameraMax - cameraMin)
        slidercy.value = (control.camera.y - cameraMin) / (cameraMax - cameraMin)
        slidercz.value = (control.camera.z - cameraMin) / (cameraMax - cameraMin)
        sliderfx.value = (control.focus.x - focusMin) / (focusMax - focusMin)
        sliderfy.value = (control.focus.y - focusMin) / (focusMax - focusMin)
        sliderfz.value = (control.focus.z - focusMin) / (focusMax - focusMin)
        sliderz.value = (control.zoom - zoomMin) / (zoomMax - zoomMin)
        sliderp.value = (control.power - powerMin) / (powerMax - powerMin)
    }

    func updateImage() {
        queue.async {
            self.calcRayMarch()
            DispatchQueue.main.async { self.imageView.image = self.image(from: self.outTexture) }
        }
    }
    
    //MARK: -

    func calcRayMarch() {
        if cBuffer == nil {
            cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
        }
        else {
            cBuffer.contents().copyBytes(from: &control, count:MemoryLayout<Control>.stride)
        }
        
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

