// Overview: Transfer screen for receiving the session (Wi-Fi / QR).
import UIKit
import Security
import QuartzCore
import CoreText
import ImageIO
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import SystemConfiguration


@_silgen_name("mgx_start") private func mgx_start(_ docs: UnsafePointer<CChar>, _ out: UnsafeMutablePointer<CChar>, _ cap: Int) -> Int32
@_silgen_name("mgx_stop") private func mgx_stop()
@_silgen_name("mgx_state") private func mgx_state() -> Int32
@_silgen_name("mgx_sas") private func mgx_sas() -> UInt32
@_silgen_name("mgx_decide") private func mgx_decide(_ accept: Int32)
@_silgen_name("mgx_message") private func mgx_message(_ out: UnsafeMutablePointer<CChar>, _ cap: Int)
@_silgen_name("mgx_qr") private func mgx_qr(_ payload: UnsafePointer<CChar>, _ out: UnsafeMutablePointer<UInt8>, _ cap: Int) -> Int32

final class MagnistraTransferLanding: UIView {
    weak var host: UIViewController?
    private let wifi = UIButton(type: .custom)
    private let qr = UIButton(type: .custom)
    private let wifiName = UILabel(frame: CGRect.zero)
    private let qrName = UILabel(frame: CGRect.zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.white
        for (button,code,selector) in [(wifi,false,#selector(wifiTapped)),(qr,true,#selector(qrTapped))] {

            button.backgroundColor = UIColor(white: 0.85, alpha: 1.0)
            button.layer.cornerRadius = 29.0
            button.layer.borderWidth = 0.0
            button.clipsToBounds = true
            button.setImage(UIImage(named: code ? "MGTransferQRCode" : "MGTransferWiFi"), for: .normal)
            button.adjustsImageWhenHighlighted = false
            button.imageView?.contentMode = .center
            button.addTarget(self, action: selector, for: .touchUpInside)
            addSubview(button)
        }
        for (label,value) in [(wifiName,"Wi-Fi"),(qrName,"QR Code")] {
            label.text = value
            label.font = UIFont.systemFont(ofSize: 14)
            label.textColor = UIColor(white: 0.22, alpha: 1)
            label.textAlignment = .center
            addSubview(label)
        }

    }
    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let center = w / 2
        let offset: CGFloat = 69
        wifi.frame = CGRect(x: center - offset - 29, y: 28, width: 58, height: 58)
        qr.frame = CGRect(x: center + offset - 29, y: 28, width: 58, height: 58)
        wifiName.frame = CGRect(x: wifi.frame.midX - 44, y: 97, width: 88, height: 22)
        qrName.frame = CGRect(x: qr.frame.midX - 44, y: 97, width: 88, height: 22)
    }
    @objc private func wifiTapped() { open(false) }
    @objc private func qrTapped() { open(true) }
    private func open(_ showQR:Bool) {
        guard let root=host else { return }

        let receiver = MagnistraTransferReceiverViewController(showQR:showQR)
        receiver.modalPresentationStyle = .fullScreen
        root.present(receiver,animated:true,completion:nil)
    }
}

private final class MagnistraTransferReceiverViewController: UIViewController, UIAlertViewDelegate {
    private let showQR: Bool
    private let status=UILabel(frame:CGRect.zero)
    private let detail=UILabel(frame:CGRect.zero)
    private let qrView=UIImageView(frame:CGRect.zero)
    private let topBar=UIView(frame:CGRect.zero)
    private let topTitle=UILabel(frame:CGRect.zero)
    private let closeButton=UIButton(type:.custom)
    private var timer:Timer?
    private var service:NetService?
    private var prompting=false
    private var currentState:Int32 = -99
    private var active=false

    private var mgxLegacyIOS56: Bool {
        let major = (UIDevice.current.systemVersion as NSString).integerValue
        return major == 5 || major == 6
    }
    init(showQR:Bool) {
        self.showQR=showQR
        super.init(nibName:nil,bundle:nil)

        if mgxLegacyIOS56 {
            let selector = NSSelectorFromString("setWantsFullScreenLayout:")
            if responds(to: selector) {
                setValue(NSNumber(value: true),forKey:"wantsFullScreenLayout")
            }
        }
    }
    required init?(coder:NSCoder) { return nil }
    override func viewDidLoad() {
        super.viewDidLoad()
        title=showQR ? "QR Code" : "Wi-Fi Transfer"
        view.backgroundColor=UIColor.white
        topBar.backgroundColor=UIColor(red:10.0/255.0,green:93.0/255.0,blue:144.0/255.0,alpha:1)
        view.addSubview(topBar)
        topTitle.text=title
        topTitle.textColor=UIColor.white
        topTitle.font=UIFont.boldSystemFont(ofSize:17)
        topTitle.textAlignment = .center
        topBar.addSubview(topTitle)

        closeButton.setImage(magnistraBackChevronImage(),for:.normal)
        closeButton.imageView?.contentMode = .scaleAspectFit
        closeButton.accessibilityLabel = "Back"
        closeButton.addTarget(self,action:#selector(close),for:.touchUpInside)
        topBar.addSubview(closeButton)
        status.font=UIFont.boldSystemFont(ofSize:16)
        status.textAlignment = .center
        status.numberOfLines=2
        detail.font=UIFont.systemFont(ofSize:12)
        detail.textColor = UIColor.darkGray
        detail.textAlignment = .center
        detail.numberOfLines=4
        qrView.contentMode = .scaleAspectFit
        view.addSubview(status)
        view.addSubview(detail)
        view.addSubview(qrView)

        title = showQR ? "QR Code" : "Wi-Fi"
        topTitle.text = title
        topTitle.backgroundColor = UIColor.clear
        topTitle.isOpaque = false
        closeButton.backgroundColor = UIColor.clear
        closeButton.contentHorizontalAlignment = .center
        status.backgroundColor = UIColor.clear
        status.isOpaque = false
        status.textColor = UIColor(white:0.17,alpha:1)
        status.font = UIFont.boldSystemFont(ofSize:18)
        detail.backgroundColor = UIColor.clear
        detail.isOpaque = false
        detail.font = UIFont.systemFont(ofSize:13)
        detail.textColor = UIColor(white:0.40,alpha:1)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        let h = view.bounds.height

        topBar.frame = CGRect(x:0,y:0,width:w,height:64)
        topTitle.frame = CGRect(x:78,y:20,width:max(0,w-156),height:44)

        closeButton.frame = CGRect(x:13,y:20,width:36,height:44)
        if showQR {
            let usable = max(CGFloat(120), h-263)
            let size = min(CGFloat(235), max(CGFloat(0),w-52),usable)
            status.frame = CGRect(x:18,y:88,width:max(0,w-36),height:32)
            qrView.frame = CGRect(x:(w-size)/2,y:132,width:size,height:size)
            detail.frame = CGRect(x:22,y:144+size,width:max(0,w-44),height:68)
        } else {
            qrView.frame = CGRect.zero
            status.frame = CGRect(x:18,y:144,width:max(0,w-36),height:36)
            detail.frame = CGRect(x:25,y:199,width:max(0,w-50),height:92)
        }
    }
    override func viewDidAppear(_ animated:Bool) {
        super.viewDidAppear(animated)
        if mgxLegacyIOS56 {

            MagnistraLegacyClearStatusBarRenderer.shared.apply(on: view)
        }
        if !active { start() }
    }
    override func viewWillDisappear(_ animated:Bool) {
        super.viewWillDisappear(animated)
        shutdown()
    }
    deinit { shutdown() }
    @objc private func close() { dismiss(animated:true,completion:nil) }
    private func start() {
        guard let path=NSSearchPathForDirectoriesInDomains(.documentDirectory,.userDomainMask,true).first else {
            status.text="Documents unavailable";return
        }
        var out=[CChar](repeating:0,count:192)
        let result=path.withCString { ptr in
            out.withUnsafeMutableBufferPointer { b in mgx_start(ptr,b.baseAddress!,b.count) }
        }
        if result<=0 {
            status.text="Unable to start transfer"
            detail.text=result == -4 ? "Connect both devices to the same Wi-Fi network." : "Close any other transfer and try again. (\(result))"
            return
        }
        active=true
        let payload=String(cString:out)
        status.text="Ready to receive"
        if showQR {
            qrView.image=renderQRCode(payload)
            detail.text="Scan with LegacyRelay on the same Wi-Fi.\nExpires after 60 seconds."
        } else {

            let advert=NetService(domain:"local.",type:"_mgtransfer._tcp.",name:"Magnistra",port:Int32(result))

            guard advert.setTXTRecord(NetService.data(fromTXTRecord:["qr":Data(payload.utf8)])) else {
                mgx_stop();active=false
                status.text="Wi-Fi discovery unavailable"
                detail.text="Use QR Code pairing instead."
                return
            }
            advert.publish();service=advert
            detail.text="On LegacyRelay choose Send to Device → Wi-Fi.\nAccept only when the six-digit codes match.\nExpires after 60 seconds."
        }
        timer=Timer.scheduledTimer(timeInterval:0.25,target:self,selector:#selector(check),userInfo:nil,repeats:true)
    }
    private func renderQRCode(_ payload:String)->UIImage? {
        var grid=[UInt8](repeating:0,count:49*49)
        let size=payload.withCString { str in
            grid.withUnsafeMutableBufferPointer { b in mgx_qr(str,b.baseAddress!,b.count) }
        }
        guard size==49 else{return nil}
        let pixel=CGFloat(5),quiet=CGFloat(4),n=CGFloat(size)
        let dim=(n+quiet*2)*pixel
        UIGraphicsBeginImageContextWithOptions(CGSize(width:dim,height:dim),true,1.0)
        defer { UIGraphicsEndImageContext() }
        UIColor.white.setFill()
        UIRectFill(CGRect(x:0,y:0,width:dim,height:dim))
        UIColor.black.setFill()
        for y in 0..<Int(size) {
            for x in 0..<Int(size) where grid[y*49+x] != 0 {
                UIRectFill(CGRect(x:(CGFloat(x)+quiet)*pixel,y:(CGFloat(y)+quiet)*pixel,width:pixel,height:pixel))
            }
        }
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    @objc private func check() {
        let state=mgx_state()
        if state==currentState { return }
        currentState=state
        switch state {
        case 2:
            if !prompting {
                prompting=true
                let code=String(format:"%06u",mgx_sas())
                let alert=UIAlertView(title:"Verify Device",message:"Check that LegacyRelay shows the SAME six-digit code:\n\n\(code)\n\nOnly accept a transfer you initiated.",delegate:self,cancelButtonTitle:"Reject")
                alert.addButton(withTitle:"Accept")
                alert.show()
            }
        case 3:
            status.text="Receiving securely..."
            detail.text="Keep Magnistra open until the transfer completes."
        case 4:
            var s=[CChar](repeating:0,count:128)
            s.withUnsafeMutableBufferPointer { mgx_message($0.baseAddress!,$0.count) }
            status.text="File received"
            detail.text="Saved to Documents as \(String(cString:s))."
            service?.stop();service=nil;timer?.invalidate();timer=nil
        case 5,-1:
            status.text=state == 5 ? "Pairing expired" : "Transfer stopped"
            var s=[CChar](repeating:0,count:128)
            s.withUnsafeMutableBufferPointer { mgx_message($0.baseAddress!,$0.count) }
            detail.text=String(cString:s)
            service?.stop();service=nil;timer?.invalidate();timer=nil
        default:break
        }
    }
    func alertView(_ alertView:UIAlertView,clickedButtonAt buttonIndex:Int) {
        mgx_decide(buttonIndex==1 ? 1 : 0)
    }
    private func shutdown() {
        timer?.invalidate();timer=nil
        service?.stop();service=nil
        if active { mgx_stop();active=false }
    }
}

