import UIKit

enum ValueType { case int32,float }
enum SliderType { case delta,direct,loop }

class SliderView: UIView {
    var context : CGContext?
    var scenter:Float = 0
    var swidth:Float = 0
    var ident:Int = 0
    var active = true
    
    var valuePointer:UnsafeMutableRawPointer! = nil
    var valuetype:ValueType = .float
    var slidertype:SliderType = .delta
    var deltaValue:Float = 0
    var name:String = "name"

    var mRange = float2(0,256)
    let percentList:[CGFloat] = [ 0.20,0.22,0.25,0.28,0.32,0.37,0.43,0.48,0.52,0.55,0.57 ]
    
    func address<T>(of: UnsafePointer<T>) -> UInt { return UInt(bitPattern: of) }
    
    func initializeInt32(_ v: inout Int32, _ sType:SliderType, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String) {
        let valueAddress = address(of:&v)
        valuePointer = UnsafeMutableRawPointer(bitPattern:valueAddress)!
        valuetype = .int32
        slidertype = sType
        mRange.x = min
        mRange.y = max
        deltaValue = delta
        name = iname
        swidth = Float(bounds.width)
        scenter = swidth / 2
        setNeedsDisplay()
    }

    func initializeFloat(_ v: inout Float, _ sType:SliderType, _ min:Float, _ max:Float,  _ delta:Float, _ iname:String) {
        let valueAddress = address(of:&v)
        valuePointer = UnsafeMutableRawPointer(bitPattern:valueAddress)!
        valuetype = .float
        slidertype = sType
        mRange.x = min
        mRange.y = max
        deltaValue = delta
        name = iname        
        swidth = Float(bounds.width)
        scenter = swidth / 2
        setNeedsDisplay()
    }

    func setActive(_ v:Bool) {
        active = v
        setNeedsDisplay()
    }
    
    func percentX(_ percent:CGFloat) -> CGFloat { return CGFloat(bounds.size.width) * percent }
    
    //MARK: ==================================

    override func draw(_ rect: CGRect) {
        context = UIGraphicsGetCurrentContext()
        
        if !active {
            let G:CGFloat = 0.13        // color Lead
            UIColor(red:G, green:G, blue:G, alpha: 1).set()
            UIBezierPath(rect:bounds).fill()
            return
        }
        
        let limColor = UIColor(red:0.3, green:0.2, blue:0.2, alpha: 1)
        let nrmColor = UIColor(red:0.2, green:0.2, blue:0.2, alpha: 1)

        nrmColor.set()
        UIBezierPath(rect:bounds).fill()
        
        if isMinValue() {
            limColor.set()
            var r = bounds
            r.size.width /= 2
            UIBezierPath(rect:r).fill()
        }
        else if isMaxValue() { 
            limColor.set()
            var r = bounds
            r.origin.x += bounds.width/2
            r.size.width /= 2
            UIBezierPath(rect:r).fill()
        }
        
        // edge, cursor -------------------------------------------------
        let ctx = context!
        ctx.saveGState()
        ctx.setStrokeColor(UIColor.black.cgColor)

        let path = UIBezierPath(rect:bounds)
        let x = valueRatio() * bounds.width
        ctx.setLineWidth(4)
        path.removeAllPoints()
        path.move(to: CGPoint(x:x, y:0))
        path.addLine(to: CGPoint(x:x, y:bounds.height))
        ctx.addPath(path.cgPath)
        ctx.strokePath()

        let path2 = UIBezierPath(rect:bounds)
        ctx.setLineWidth(2)
        ctx.addPath(path2.cgPath)
        ctx.strokePath()
        
        ctx.restoreGState()
        
        // value ------------------------------------------
        func formatted(_ v:Float) -> String { return String(format:"%6.4f",v) }
        func formatted2(_ v:Float) -> String { return String(format:"%7.5f",v) }
        func formatted3(_ v:Float) -> String { return String(format:"%d",Int(v)) }
        func formatted4(_ v:Float) -> String { return String(format:"%5.2f",v) }

        let vx = percentX(0.60)
        
        func valueColor(_ v:Float) -> UIColor {
            var c = UIColor.gray
            if v < 0 { c = UIColor.red } else if v > 0 { c = UIColor.green }
            return c
        }
        
        func coloredValue(_ v:Float) { drawText(vx,8,valueColor(v),16, formatted(v)) }
        
        if valuePointer != nil {
            drawText(10,8,.white,16,name)
            
            switch valuetype {
            case .int32 :
                let v:Int32 = valuePointer.load(as: Int32.self)
                drawText(percentX(0.75),8,.gray,16, v.description)
            case .float :
                let v:Float = valuePointer.load(as: Float.self)
                
                if v > 100 {
                    drawText(vx,8,.gray,16, formatted3(v))
                }
                else {
                    coloredValue(v)
                }
            }
            
            return
        }
    }
    
    func fClamp2(_ v:Float, _ range:float2) -> Float {
        if v < range.x { return range.x }
        if v > range.y { return range.y }
        return v
    }
    
    var delta:Float = 0
    var touched = false

    //MARK: ==================================

    func getValue() -> Float {
        if valuePointer == nil { return 0 }
        var value:Float = 0
        
        switch valuetype {
        case .int32 : value = Float(valuePointer.load(as: Int32.self))
        case .float : value = valuePointer.load(as: Float.self)
        }

        return value
    }
    
    func isMinValue() -> Bool {
        if valuePointer == nil { return false }
        if slidertype == .loop { return false }

        return getValue() == mRange.x
    }
    
    func isMaxValue() -> Bool {
        if valuePointer == nil { return false }
        if slidertype == .loop { return false }
        
        return getValue() == mRange.y
    }
    
    func valueRatio() -> CGFloat {
        let den = mRange.y - mRange.x
        if den == 0 { return CGFloat(0) }
        return CGFloat((getValue() - mRange.x) / den )
    }
    
    //MARK: ==================================
    
    func update() -> Bool {
        if valuePointer == nil || !active || !touched { return false }

        var value = getValue()

        if slidertype == .loop {
            value += delta * deltaValue
            if value < mRange.x { value += (mRange.y - mRange.x) } else
                if value > mRange.y { value -= (mRange.y - mRange.x) }
        }
        else {
            value = fClamp2(value + delta * deltaValue, mRange)
        }
        
        switch valuetype {
        case .int32 : valuePointer.storeBytes(of:Int32(value), as:Int32.self)
        case .float : valuePointer.storeBytes(of:value, as:Float.self)
        }
        
        setNeedsDisplay()
        return true
    }
    
    //MARK: ==================================

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if valuePointer == nil || !active { return }
        
        for t in touches {
            let pt = t.location(in: self)
            
            touched = true
            
            if slidertype == .direct {
                let value = fClamp(mRange.x + (mRange.y - mRange.x) * Float(pt.x) / swidth, mRange)

                switch valuetype {
                case .int32 : valuePointer.storeBytes(of:Int32(value), as:Int32.self)
                case .float : valuePointer.storeBytes(of:value, as:Float.self)
                }
            }
            else {
                delta = (Float(pt.x) - scenter) / swidth / 10
            }
            
            setNeedsDisplay()
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { touchesBegan(touches, with:event) }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touched = false }
    
    func drawLine(_ p1:CGPoint, _ p2:CGPoint) {
        context?.beginPath()
        context?.move(to:p1)
        context?.addLine(to:p2)
        context?.strokePath()
    }
    
    func drawVLine(_ x:CGFloat, _ y1:CGFloat, _ y2:CGFloat) { drawLine(CGPoint(x:x,y:y1),CGPoint(x:x,y:y2)) }
    func drawHLine(_ x1:CGFloat, _ x2:CGFloat, _ y:CGFloat) { drawLine(CGPoint(x:x1, y:y),CGPoint(x: x2, y:y)) }
    
    func drawText(_ x:CGFloat, _ y:CGFloat, _ color:UIColor, _ sz:CGFloat, _ str:String) {
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = NSTextAlignment.left
        
        let font = UIFont.init(name: "Helvetica", size:sz)!
        
        let textFontAttributes = [
            NSAttributedStringKey.font: font,
            NSAttributedStringKey.foregroundColor: color,
            NSAttributedStringKey.paragraphStyle: paraStyle,
            ]
        
        str.draw(in: CGRect(x:x, y:y, width:800, height:100), withAttributes: textFontAttributes)
    }
    
    func drawText(_ pt:CGPoint, _ color:UIColor, _ sz:CGFloat, _ str:String) { drawText(pt.x,pt.y,color,sz,str) }
}

func fClamp(_ v:Float, _ range:float2) -> Float {
    if v < range.x { return range.x }
    if v > range.y { return range.y }
    return v
}
