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
    let base64StringRegex = NSRegularExpression("^([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{2}==)?$")
    
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
    
    // Convert utf8 string to a base64 string
    public func convertStringToBase64(data: String) -> String {
        let utf8str = data.data(using: .utf8)
        return (utf8str?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)))!
    }
    
    // Generates a secure random base64 string base on provided byte length
    public func generateRandomBase64String(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            byteCount,
            &bytes
        )
        // A status of errSecSuccess indicates success
        if status != errSecSuccess {
          return "Error"
        }
        let data = Data(bytes)
        return data.base64EncodedString()
    }

    // Encrypts data using CWI.encrypt
    @available(iOS 15.0, *)
    public func encrypt(plaintext: String, protocolID: String, keyID: String) async -> String {
        
        // Convert the string to a base64 string
        let base64Encoded = convertStringToBase64(data: plaintext)
        
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"encrypt",
            "params": [
                "plaintext": convertToJSONString(param: base64Encoded),
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
    
    @available(iOS 15.0, *)
    public func generateCryptoKey() async -> String {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"generateCryptoKey",
            "params": []
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        let cryptoKey:String = (responseObject.objectValue?["result"]?.stringValue)!
        return cryptoKey
    }
    
    @available(iOS 15.0, *)
    public func encryptUsingCryptoKey(plaintext: String, base64CryptoKey: String, returnType: String? = "base64") async -> String {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"encryptUsingCryptoKey",
            "params": [
                "plaintext": convertToJSONString(param: plaintext),
                "base64CryptoKey": convertToJSONString(param: base64CryptoKey),
                "returnType": convertToJSONString(param: returnType ?? "base64")
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        // TODO: Support buffer return type
        if (returnType == "base64") {
            return (responseObject.objectValue?["result"]?.stringValue)!
        }
        return "Error: Unsupported type!"
    }
    
    @available(iOS 15.0, *)
    public func decryptUsingCryptoKey(ciphertext: String, base64CryptoKey: String, returnType: String? = "base64") async -> String {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"decryptUsingCryptoKey",
            "params": [
                "ciphertext": convertToJSONString(param: ciphertext),
                "base64CryptoKey": convertToJSONString(param: base64CryptoKey),
                "returnType": convertToJSONString(param: returnType ?? "base64")
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        // TODO: Support buffer return type
        if (returnType == "base64") {
            return (responseObject.objectValue?["result"]?.stringValue)!
        }
        return "Error: Unsupported type!"
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
        
        return responseObject
    }
    
    // Creates an Hmac using CWI.createHmac
    @available(iOS 15.0, *)
    public func createHmac(data: String, protocolID: String, keyID: String, description: String? = nil, counterparty: String? = "self", privileged: Bool? = nil) async -> String {
        // Construct the expected command to send with default values for nil params
        var cmd:JSON = [
            "type":"CWI",
            "call":"createHmac",
            "params": [
                "data": convertToJSONString(param: convertStringToBase64(data: data)),
                "protocolID": convertToJSONString(param: protocolID),
                "keyID": convertToJSONString(param: keyID),
                "description": try! JSON(description ?? ""),
                "counterparty": try! JSON(counterparty ?? ""),
                "privileged": try! JSON(privileged ?? false)
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        let decryptedText:String = (responseObject.objectValue?["result"]?.stringValue)!
        return decryptedText
    }
    @available(iOS 15.0, *)
    public func verifyHmac(data: String, hmac: String, protocolID: String, keyID: String, description: String? = nil, counterparty: String? = nil, privileged: Bool? = nil) async -> Bool {
        // Make sure data and hmac are base64 strings
        var data = data
        var hmac = hmac
        if (!base64StringRegex.matches(hmac)) {
            hmac = convertStringToBase64(data: hmac)
        }
        if (!base64StringRegex.matches(data)) {
            data = convertStringToBase64(data: data)
        }
        
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"verifyHmac",
            "params": [
                "data": convertToJSONString(param: data),
                "hmac": convertToJSONString(param: hmac),
                "protocolID": convertToJSONString(param: protocolID),
                "keyID": convertToJSONString(param: keyID),
                "description": try! JSON(description ?? ""),
                "counterparty": try! JSON(counterparty ?? ""),
                "privileged": try! JSON(privileged ?? false)
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result boolean
        let verified:Bool = (responseObject.objectValue?["result"]?.boolValue)!
        return verified
    }
    
    @available(iOS 15.0, *)
    public func createSignature(data: String, protocolID: String, keyID: String, description: String? = nil, counterparty: String? = nil, privileged: String? = nil) async -> String {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"createSignature",
            "params": [
                "data": convertToJSONString(param: convertStringToBase64(data: data)),
                "protocolID": convertToJSONString(param: protocolID),
                "keyID": convertToJSONString(param: keyID),
                "description": try! JSON(description ?? ""),
                "counterparty": try! JSON(counterparty ?? ""),
                "privileged": try! JSON(privileged ?? false)
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        let signature:String = (responseObject.objectValue?["result"]?.stringValue)!
        return signature
    }
    
    @available(iOS 15.0, *)
    public func verifySignature(data: String, signature: String, protocolID: String, keyID: String, description: String? = nil, counterparty: String? = nil, privileged: String? = nil, reason: String? = nil) async -> Bool{
        // Make sure data and signature are base64 strings
        var data = data
        var signature = signature
        if (!base64StringRegex.matches(data)) {
            data = convertStringToBase64(data: data)
        }
        if (!base64StringRegex.matches(signature)) {
            signature = convertStringToBase64(data: signature)
        }
        
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"verifySignature",
            "params": [
                "data": convertToJSONString(param: data),
                "signature": convertToJSONString(param: signature),
                "protocolID": convertToJSONString(param: protocolID),
                "keyID": convertToJSONString(param: keyID),
                "description": try! JSON(description ?? ""),
                "counterparty": try! JSON(counterparty ?? ""),
                "privileged": try! JSON(privileged ?? false),
                "reason": try! JSON(reason ?? "")
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result boolean
        let verified:Bool = (responseObject.objectValue?["result"]?.boolValue)!
        return verified
    }
    
    @available(iOS 15.0, *)
    public func createCertificate(certificateType: String, fieldObject: JSON, certifierUrl: String, certifierPublicKey: String) async -> JSON {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"createCertificate",
            "params": [
                "certificateType": convertToJSONString(param: certificateType),
                "fieldObject": fieldObject,
                "certifierUrl": convertToJSONString(param: certifierUrl),
                "certifierPublicKey": convertToJSONString(param: certifierPublicKey)
            ]
        ]
        
        // Run the command and get the response JSON object
        let signedCertificate = await runCommand(cmd: &cmd).value
        return signedCertificate
    }
    
    @available(iOS 15.0, *)
    public func getCertificates(certifiers: JSON, types: JSON) async -> JSON {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"ninja.findCertificates",
            "params": [
                "certifiers": certifiers,
                "types": types
            ]
        ]
        
        // Run the command and get the response JSON object
        let certificates = await runCommand(cmd: &cmd).value
        return certificates
    }
    
    @available(iOS 15.0, *)
    public func proveCertificate(certificate: JSON, fieldsToReveal: JSON? = nil, verifierPublicIdentityKey: String) async -> JSON {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"proveCertificate",
            "params": [
                "certificate": certificate,
                "fieldsToReveal": fieldsToReveal ?? nil,
                "verifierPublicIdentityKey": convertToJSONString(param: verifierPublicIdentityKey)
            ]
        ]
        
        
        // Run the command and get the response JSON object
        let provableCertificate = await runCommand(cmd: &cmd).value
        return provableCertificate
    }
    
    @available(iOS 15.0, *)
    public func submitDirectTransaction(protocolID: String, transaction: JSON, senderIdentityKey: String, note: String, amount: Int, derivationPrefix: String? = nil) async -> JSON {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"ninja.submitDirectTransaction",
            "params": [
                "protocol": convertToJSONString(param: protocolID),
                "transaction": transaction,
                "senderIdentityKey": convertToJSONString(param: senderIdentityKey),
                "note": convertToJSONString(param: note),
                "amount": try! JSON(amount),
                "derivationPrefix": try! JSON(derivationPrefix ?? "")
            ]
        ]
        
        // Run the command and get the response JSON object
        let provableCertificate = await runCommand(cmd: &cmd).value
        return provableCertificate
    }
    
    @available(iOS 15.0, *)
    public func getPublicKey(protocolID: JSON?, keyID: String? = nil, priviliged: Bool? = nil, identityKey: Bool? = nil, reason: String? = nil, counterparty: String? = "self", description: String? = nil) async -> String {
        // Construct the expected command to send
        // Added default values for dealing with nil params
        var cmd:JSON = [
            "type":"CWI",
            "call":"getPublicKey",
            "params": [
                "protocolID": protocolID ?? "",
                "keyID": try! JSON(keyID!),
                "priviliged": try! JSON(priviliged ?? false),
                "identityKey": try! JSON(identityKey ?? false),
                "reason": try! JSON(reason ?? ""),
                "counterparty": try! JSON(counterparty ?? ""),
                "description": try! JSON(description ?? "")
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        let publicKey:String = (responseObject.objectValue?["result"]?.stringValue)!
        return publicKey
    }
    
    @available(iOS 15.0, *)
    public func getVersion() async -> String {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"getVersion",
            "params": []
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        
        // Pull out the expect result string
        let version:String = (responseObject.objectValue?["result"]?.stringValue)!
        return version
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
    
    @available(iOS 15.0, *)
    public func createPushDropScript(fields: JSON, protocolID: String, keyID: String) async -> String {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"pushdrop.create",
            "params": [
                "fields": fields,
                "protocolID": convertToJSONString(param: protocolID),
                "keyID": convertToJSONString(param: keyID)
            ]
        ]
        
        // Run the command and get the response JSON object
        let responseObject = await runCommand(cmd: &cmd).value
        let script:String = (responseObject.objectValue?["result"]?.stringValue)!
        return script
    }
    
    @available(iOS 15.0, *)
    public func parapetRequest(resolvers: JSON, bridge: String, type: String, query: JSON) async -> JSON {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"parapet",
            "params": [
                "resolvers": resolvers,
                "bridge": convertToJSONString(param: bridge),
                "type": convertToJSONString(param: type),
                "query": query
              ]
            ]
        
        // Run the command and get the response JSON object
        let result = await runCommand(cmd: &cmd).value
        return result
    }
    
    @available(iOS 15.0, *)
    public func downloadUHRPFile(URL: String, bridgeportResolvers: JSON) async -> Data? {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"downloadFile",
            "params": [
                "URL": convertToJSONString(param: URL),
                "bridgeportResolvers": bridgeportResolvers
            ]
        ]
        
        // TODO: Determine return type and best way to transfer large bytes of data.
        // Run the command and get the response JSON object
        let result = await runCommand(cmd: &cmd).value
        
        // Convert the array of JSON objects to an Array of UInt8s and then to a Data object
        // TODO: Optimize further
        if let arrayOfJSONObjects = result.objectValue?["result"]?.objectValue?["data"]?.objectValue?["data"]?.arrayValue {
            let byteArray:[UInt8] = arrayOfJSONObjects.map { UInt8($0.doubleValue!)}
            return Data(byteArray)
        }
        return nil
    }
    
    @available(iOS 15.0, *)
    public func newAuthriteRequest(params: JSON, requestUrl: String, fetchConfig: JSON) async -> JSON {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"newAuthriteRequest",
            "params": [
                "params": params,
                "requestUrl": convertToJSONString(param: requestUrl),
                "fetchConfig": fetchConfig
            ]
        ]
        
        // TODO: Determine return type and best way to transfer large bytes of data.
        // Run the command and get the response JSON object
        let result = await runCommand(cmd: &cmd).value
        return result
    }
    
    @available(iOS 15.0, *)
    public func createOutputScriptFromPubKey(derivedPublicKey: String) async -> String {
        // Construct the expected command to send
        var cmd:JSON = [
            "type":"CWI",
            "call":"createOutputScriptFromPubKey",
            "params": [
                "derivedPublicKey": convertToJSONString(param: derivedPublicKey)
            ]
        ]

        // Run the command and get the response as a string
        let responseObject = await runCommand(cmd: &cmd).value
        return (responseObject.objectValue?["result"]?.stringValue)!
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
            
                self.callbackIDMap.removeValue(forKey: id)
                // Convert the JSON string into a JSON swift object
                let jsonResponse = try! JSONDecoder().decode(JSON.self, from: response.data(using: .utf8)!)
                promise(Result.success(jsonResponse))
            }

            self.callbackIDMap[id] = callback
//            print(self.callbackIDMap)
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


// Reference -> https://www.hackingwithswift.com/forums/swift/base64-decoded-content-is-nil/7763
extension NSRegularExpression {
    convenience init(_ pattern: String) {
        do {
            try self.init(pattern: pattern)
        } catch {
            preconditionFailure("Illegal regular expression: \(pattern).")
        }
    }
}

extension NSRegularExpression {
    func matches(_ string: String) -> Bool {
        let range = NSRange(location: 0, length: string.utf16.count)
        return firstMatch(in: string, options: [], range: range) != nil
    }
}
