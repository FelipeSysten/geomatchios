import WebKit

/// Proxy fraco para WKScriptMessageHandler — evita retain cycle entre WKUserContentController e o VC.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: (AnyObject & WKScriptMessageHandler)?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate as AnyObject & WKScriptMessageHandler
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
