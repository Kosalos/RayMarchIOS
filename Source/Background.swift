import UIKit

class Background: UIView {
    let xs = scrnLandscape ? scrnSz[scrnIndex].y : scrnSz[scrnIndex].x
    let ys = scrnLandscape ? scrnSz[scrnIndex].x : scrnSz[scrnIndex].y

//    override func draw(_ rect: CGRect) {
//        super.draw(rect)
//
//        let color = UIColor(red:0.2, green:0.2, blue:0.2, alpha: 1)
//        color.setFill()
//        UIBezierPath(rect:CGRect(x:0, y:0, width:xs, height:ys)).fill()
//    }

}
