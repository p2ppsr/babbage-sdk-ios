import Foundation
import WebKit
import Combine
import GenericJSON

@available(iOS 13.0, *)
public class BabbageSDK: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    
    var webView: WKWebView!
    public typealias Callback = (String) -> Void
    public var callbackIDMap: [String : Callback] = [:]

    var webviewStartURL:String = ""
    
    public func setParent(parent: UIViewController) {
        parent.addChild(self)
        parent.view.addSubview(self.view)
        self.didMove(toParent: parent)
    }
    
    public required init(webviewStartURL: String = "https://staging-mobile-portal.babbage.systems") {
        
        // We aren't using a nib or storyboard for the UI
        super.init(nibName: nil, bundle: nil)
        
        // Set the hades webviewStart URL
        self.webviewStartURL = webviewStartURL
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    public override func loadView() {
        // Create the webview and set it to the view
        webView = WKWebView()
        webView.frame  = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        self.view = webView
        self.view.isHidden = true

        // Do any additional setup after loading the view.
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = "babbage-webview-inlay"
        webView.configuration.userContentController.add(self, name: "openBabbage")
        webView.configuration.userContentController.add(self, name: "closeBabbage")

        // Disable zooming on webview
        let source: String = "var meta = document.createElement('meta');" +
            "meta.name = 'viewport';" +
            "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';" +
            "var head = document.getElementsByTagName('head')[0];" +
            "head.appendChild(meta);"
        let script: WKUserScript = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        
        // Load the request url for hades server
        let request = NSURLRequest(url: URL(string: webviewStartURL)!)
        webView.load(request as URLRequest)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    // Show / Hide the BabbageViewController
    public func showView() {
        self.view.fadeIn(0.3, onCompletion: {})
    }
    public func hideView() {
        self.view.fadeOut(0.3, onCompletion: {})
    }

    // Handle javascript alerts with native swift alerts
    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
        
        alertController.addAction(UIAlertAction(title: "Confirm", style: .destructive, handler: { (action) in
            completionHandler(true)
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { (action) in
            completionHandler(false)
        }))

        present(alertController, animated: true, completion: nil)
    }

    // Callback recieved from webkit.messageHandler.postMessage
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        //This function handles the events coming from javascript.
        guard let response = message.body as? String else { return }
        
        if (message.name == "closeBabbage") {
            hideView()
        } else if (message.name == "openBabbage") {
            showView()
        } else {
            callbackIDMap[message.name]!(response)
        }
    }
    
    // Webview call back for when the view loads
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      // This function is called when the webview finishes navigating to the webpage.
      // We use this to send data to the webview when it's loaded.
        Task.init {
            if #available(iOS 15.0, *) {
                let isAuthenticated:Bool? = await isAuthenticated()

                // Show/Hide the view
                if (isAuthenticated!) {
                    hideView()
                } else {
                    showView()
                    _ = await waitForAuthentication()
                    hideView()
                }
            } else {
                // Fallback on earlier versions
            }
        }
    }
    
    // Helper function which returns a JSON type string
    func convertToJSONString(param: String) -> JSON {
        return try! JSON(param)
    }

    // Encrypts data using CWI.encrypt
    @available(iOS 15.0, *)
    public func encrypt(plaintext: String, protocolID: String, keyID: String) async -> String {
        
        // Convert the string to a base64 string
        let utf8str = plaintext.data(using: .utf8)
        let base64Encoded = utf8str?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0))
        
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"encrypt",
            "params": [
                "plaintext": convertToJSONString(param: base64Encoded!),
                "protocolID": convertToJSONString(param: protocolID),
                "keyID": convertToJSONString(param: keyID),
                "returnType": "string"
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        let encryptedText:String = (responseObject.objectValue?["result"]?.stringValue)!
        return encryptedText
    }

    // Encrypts data using CWI.decrypt
    @available(iOS 15.0, *)
    public func decrypt(ciphertext: String, protocolID: String, keyID: String) async -> String {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"decrypt",
            "params": [
                "ciphertext": convertToJSONString(param: ciphertext),
                "protocolID": convertToJSONString(param: protocolID),
                "keyID": convertToJSONString(param: keyID),
                "returnType": "string"
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        let decryptedText:String = (responseObject.objectValue?["result"]?.stringValue)!
        return decryptedText
    }
    
    // Returns a JSON object with non-null values
    func getValidJSON(params: [String: JSON]) -> JSON {
        var paramsAsJSON:JSON = []
        for param in params {
            if (param.value != nil) {
                paramsAsJSON = paramsAsJSON.merging(with: [param.key: param.value])
            }
        }
        return paramsAsJSON
    }
    
    // Creates a new action using CWI.createAction
    @available(iOS 15.0, *)
    public func createAction(inputs: JSON? = nil, outputs: JSON, description: String, bridges: JSON? = nil, labels: JSON? = nil) async -> JSON {
        
        let params:[String:JSON] = [
            "inputs": inputs ?? nil,
            "outputs": outputs,
            "description": convertToJSONString(param: description),
            "bridges": bridges ?? nil,
            "labels": labels ?? nil
        ]
        let paramsAsJSON:JSON = getValidJSON(params: params)
        
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"createAction",
            "params": paramsAsJSON
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // TODO: Decide on return type
        return responseObject
    }
    
    @available(iOS 15.0, *)
    public func isAuthenticated() async -> Bool {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"isAuthenticated",
            "params": []
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        let str:String = try! String(data: JSONEncoder().encode(responseObject.result), encoding: .utf8)!
        // Convert string to boolean and return
        let result =  (str as NSString).boolValue
        return result
    }
    
    @available(iOS 15.0, *)
    public func waitForAuthentication() async -> Bool {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"waitForAuthentication",
            "params": []
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        let str:String = try! String(data: JSONEncoder().encode(responseObject.result), encoding: .utf8)!
        // Convert string to boolean and return
        let result =  (str as NSString).boolValue
        return result
    }

    // Execute the BabbageCommand
    public func runCommand(cmd: inout JSON)-> Combine.Future <JSON, Never> {
        // Generate a callbackID
        let id:String = NSUUID().uuidString
        webView.configuration.userContentController.add(self, name: id)
        
        let callbackID:JSON = [
            "id":  try! JSON(id)
        ]
        // Update the cmd to contain the new callback id
        cmd = cmd.merging(with: callbackID)

        let result = Future<JSON, Never>() { promise in
            let callback: Callback = { response in
            
                print(response)
                self.callbackIDMap.removeValue(forKey: id)
                // Convert the JSON string into a JSON swift object
                let jsonResponse = try! JSONDecoder().decode(JSON.self, from: response.data(using: .utf8)!)
                promise(Result.success(jsonResponse))
            }

            self.callbackIDMap[id] = callback
            print(self.callbackIDMap)
        }
        do {
            let jsonData = try JSONEncoder().encode(cmd)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript("window.postMessage(\(jsonString))")
            }
        } catch {
            // TODO
        }
        return result
    }
}

// Animate views in and out --> https://stackoverflow.com/questions/44198487/animating-uiview-ishidden-subviews
extension UIView {
    func fadeIn(_ duration: TimeInterval? = 0.2, onCompletion: (() -> Void)? = nil) {
        self.alpha = 0
        self.isHidden = false
        UIView.animate(withDuration: duration!,
                       animations: { self.alpha = 1 },
                       completion: { (value: Bool) in
            if let complete = onCompletion { complete() }
        }
        )
    }
    
    func fadeOut(_ duration: TimeInterval? = 0.2, onCompletion: (() -> Void)? = nil) {
        UIView.animate(withDuration: duration!,
                       animations: { self.alpha = 0 },
                       completion: { (value: Bool) in
            self.isHidden = true
            if let complete = onCompletion { complete() }
        }
        )
    }
    
}
