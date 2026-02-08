import AVFoundation
import Security
import UIKit
import WebKit

private let jpScanBarcodeHandlerName = "jpScanBarcode"
private let jpLocalStorageChangedHandlerName = "jpLocalStorageChanged"
private let jpNativeScanEventName = "jp-native-scan-result"
private let jpAnalyticsSidKeychainAccount = "jp.analytics.sid"
private let jpAnalyticsHsidKeychainAccount = "jp.analytics.hsid"
private let jpAnalyticsCookieLifetime: TimeInterval = 315360000
private let jpLocalStorageKeychainAccount = "jp.localstorage"
private let jpLocalStorageAllowedKeys = ["jelposkupiloFavoritesId", "jelposkupiloFavoritesNygma"]

fileprivate protocol BarcodeScannerViewControllerDelegate: AnyObject {
    func barcodeScannerViewController(_ controller: BarcodeScannerViewController, didScan barCode: String, requestId: String)
    func barcodeScannerViewControllerDidCancel(_ controller: BarcodeScannerViewController, requestId: String)
    func barcodeScannerViewController(_ controller: BarcodeScannerViewController, didFailWithMessage message: String, requestId: String)
}

fileprivate final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let requestId: String
    private weak var delegate: BarcodeScannerViewControllerDelegate?
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didFinish = false
    private var pendingDismissCompletion: (() -> Void)?
    private let closeButton = UIButton(type: .system)

    init(requestId: String, delegate: BarcodeScannerViewControllerDelegate) {
        self.requestId = requestId
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCloseButton()
        setupScanner()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let completion = pendingDismissCompletion {
            pendingDismissCompletion = nil
            dismiss(animated: true, completion: completion)
            return
        }

        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
        closeButton.layer.cornerRadius = 22
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    private func setupScanner() {
        guard let captureDevice = AVCaptureDevice.default(for: .video) else {
            finishWithError("Kamera nije dostupna.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: captureDevice)

            guard captureSession.canAddInput(input) else {
                finishWithError("Nije moguće pristupiti kameri.")
                return
            }
            captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard captureSession.canAddOutput(output) else {
                finishWithError("Nije moguće čitati barkod.")
                return
            }
            captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.ean13]

            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.insertSublayer(previewLayer, at: 0)
            self.previewLayer = previewLayer
        } catch {
            finishWithError("Nije moguće inicijalizirati kameru.")
        }
    }

    @objc
    private func closeTapped() {
        if didFinish {
            finishAndDismiss {}
            return
        }

        didFinish = true
        finishAndDismiss { [weak self] in
            guard let self else {
                return
            }

            self.delegate?.barcodeScannerViewControllerDidCancel(self, requestId: self.requestId)
        }
    }

    private func finishWithError(_ message: String) {
        guard !didFinish else {
            return
        }

        didFinish = true
        finishAndDismiss { [weak self] in
            guard let self else {
                return
            }

            self.delegate?.barcodeScannerViewController(self, didFailWithMessage: message, requestId: self.requestId)
        }
    }

    private func finishAndDismiss(_ completion: @escaping () -> Void) {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }

        if presentingViewController == nil || view.window == nil {
            pendingDismissCompletion = completion
            return
        }

        dismiss(animated: true, completion: completion)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didFinish else {
            return
        }

        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .ean13,
              let code = object.stringValue,
              !code.isEmpty else {
            return
        }

        didFinish = true
        finishAndDismiss { [weak self] in
            guard let self else {
                return
            }

            self.delegate?.barcodeScannerViewController(self, didScan: code, requestId: self.requestId)
        }
    }
}

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, BarcodeScannerViewControllerDelegate {
    private let allowedHosts = ["jelposkupilo.eu", "www.jelposkupilo.eu"]
    private let webLightBackground = UIColor.white
    private let webDarkBackground = UIColor(red: 19.0 / 255.0, green: 19.0 / 255.0, blue: 24.0 / 255.0, alpha: 1.0)
    private var webView: WKWebView!
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let safeAreaBackgroundView = UIView()
    private var activeScanRequestId: String?
    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(reloadPage), for: .valueChanged)
        return control
    }()

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: jpScanBarcodeHandlerName)
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: jpLocalStorageChangedHandlerName)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureBackground()
        configureWebView()
        configureLoadingState()
        loadInitialURL()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else {
            return
        }

        applyBackgroundColors()
    }

    private func configureBackground() {
        safeAreaBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(safeAreaBackgroundView)

        NSLayoutConstraint.activate([
            safeAreaBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            safeAreaBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            safeAreaBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            safeAreaBackgroundView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        ])

        applyBackgroundColors()
    }

    private func applyBackgroundColors() {
        let backgroundColor = traitCollection.userInterfaceStyle == .dark ? webDarkBackground : webLightBackground
        view.backgroundColor = backgroundColor
        safeAreaBackgroundView.backgroundColor = backgroundColor
        webView?.scrollView.backgroundColor = backgroundColor
    }

    private func configureWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        configuration.applicationNameForUserAgent = "JelPoskupiloApp/\(marketingVersion) JelPoskupiloBuild/\(buildNumber)"

        let userContentController = WKUserContentController()
        userContentController.add(self, name: jpScanBarcodeHandlerName)
        userContentController.add(self, name: jpLocalStorageChangedHandlerName)

        let persisted = readPersistedLocalStorage()
        if !persisted.isEmpty {
            var lines: [String] = []
            for key in jpLocalStorageAllowedKeys {
                guard let value = persisted[key] else { continue }
                let escapedKey = key.replacingOccurrences(of: "'", with: "\\'")
                let escapedValue = value.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                lines.append("try { localStorage.setItem('\(escapedKey)', '\(escapedValue)'); } catch(e) {}")
            }
            if !lines.isEmpty {
                let script = WKUserScript(
                    source: lines.joined(separator: "\n"),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
                userContentController.addUserScript(script)
            }
        }

        configuration.userContentController = userContentController

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.refreshControl = refreshControl
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear

        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applyBackgroundColors()
    }

    private func configureLoadingState() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadInitialURL() {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "BaseURL") as? String,
              let url = URL(string: urlString) else {
            return
        }

        guard let sid = readPersistentAnalyticsSid(), !sid.isEmpty else {
            webView.load(URLRequest(url: url))
            return
        }

        setAnalyticsCookies(sid: sid, hsid: readPersistentAnalyticsHsid() ?? sid, for: url) { [weak self] in
            guard let self else {
                return
            }

            self.webView.load(URLRequest(url: url))
        }
    }

    @objc
    private func reloadPage() {
        activityIndicator.stopAnimating()
        webView.reload()
    }

    private func canLoadInWebView(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }

        if allowedHosts.contains(host) {
            return true
        }

        #if DEBUG
        return host == "localhost" || host == "127.0.0.1"
        #else
        return false
        #endif
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func setAnalyticsCookies(sid: String, hsid: String, for baseURL: URL, completion: @escaping () -> Void) {
        guard let scheme = baseURL.scheme?.lowercased(),
              let baseHost = baseURL.host?.lowercased(),
              ["http", "https"].contains(scheme) else {
            completion()
            return
        }

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let expires = Date(timeIntervalSinceNow: jpAnalyticsCookieLifetime)
        let hosts = Set(allowedHosts + [baseHost])
        let cookieValues = ["sid": sid, "hsid": hsid]

        let cookies = hosts.flatMap { host in
            cookieValues.compactMap { name, value -> HTTPCookie? in
                var properties: [HTTPCookiePropertyKey: Any] = [
                    .name: name,
                    .value: value,
                    .domain: host,
                    .path: "/",
                    .expires: expires
                ]

                if scheme == "https" {
                    properties[.secure] = "TRUE"
                }

                return HTTPCookie(properties: properties)
            }
        }

        guard !cookies.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()

        cookies.forEach { cookie in
            HTTPCookieStorage.shared.setCookie(cookie)
            group.enter()
            cookieStore.setCookie(cookie) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    private func readPersistentAnalyticsSid() -> String? {
        return readPersistentAnalyticsValue(account: jpAnalyticsSidKeychainAccount)
    }

    private func readPersistentAnalyticsHsid() -> String? {
        return readPersistentAnalyticsValue(account: jpAnalyticsHsidKeychainAccount)
    }

    private func readPersistentAnalyticsValue(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: analyticsSidService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    private func storePersistentAnalyticsSid(_ sid: String) {
        storePersistentAnalyticsValue(sid, account: jpAnalyticsSidKeychainAccount)
    }

    private func storePersistentAnalyticsHsid(_ hsid: String) {
        storePersistentAnalyticsValue(hsid, account: jpAnalyticsHsidKeychainAccount)
    }

    private func storePersistentAnalyticsValue(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: analyticsSidService,
            kSecAttrAccount as String: account
        ]
        let valueData = Data(value.utf8)

        var addQuery = query
        addQuery[kSecValueData as String] = valueData

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus == errSecDuplicateItem {
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: valueData
            ]
            SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        }
    }

    private var analyticsSidService: String {
        Bundle.main.bundleIdentifier ?? "eu.jelposkupilo.app"
    }

    private func readPersistedLocalStorage() -> [String: String] {
        guard let json = readPersistentAnalyticsValue(account: jpLocalStorageKeychainAccount),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }

    private func storePersistedLocalStorage(_ values: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        storePersistentAnalyticsValue(json, account: jpLocalStorageKeychainAccount)
    }

    private func sendNativeScanResult(
        requestId: String,
        status: String,
        barCode: String? = nil,
        message: String? = nil
    ) {
        var payload: [String: Any] = [
            "requestId": requestId,
            "status": status
        ]

        if let barCode {
            payload["barCode"] = barCode
        }

        if let message {
            payload["message"] = message
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return
        }

        let javascript = "window.dispatchEvent(new CustomEvent('\(jpNativeScanEventName)', { detail: \(json) }));"
        webView.evaluateJavaScript(javascript, completionHandler: nil)
    }

    private func isTrustedBridgeMessage(_ message: WKScriptMessage) -> Bool {
        if let requestURL = message.frameInfo.request.url {
            return canLoadInWebView(requestURL)
        }

        if let currentURL = webView.url {
            return canLoadInWebView(currentURL)
        }

        return false
    }

    private func startNativeBarcodeScan(requestId: String) {
        guard AVCaptureDevice.default(for: .video) != nil else {
            sendNativeScanResult(
                requestId: requestId,
                status: "error",
                message: "Kamera nije dostupna na ovom uređaju."
            )
            return
        }

        activeScanRequestId = requestId

        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            presentScanner(requestId: requestId)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }

                    if granted {
                        self.presentScanner(requestId: requestId)
                    } else {
                        self.activeScanRequestId = nil
                        self.sendNativeScanResult(
                            requestId: requestId,
                            status: "error",
                            message: "Dozvola za kameru odbijena."
                        )
                    }
                }
            }
        case .denied, .restricted:
            activeScanRequestId = nil
            sendNativeScanResult(
                requestId: requestId,
                status: "error",
                message: "Dozvola za kameru odbijena."
            )
        @unknown default:
            activeScanRequestId = nil
            sendNativeScanResult(
                requestId: requestId,
                status: "error",
                message: "Dozvola za kameru nije dostupna."
            )
        }
    }

    private func presentScanner(requestId: String) {
        let scanner = BarcodeScannerViewController(requestId: requestId, delegate: self)
        scanner.modalPresentationStyle = .fullScreen
        present(scanner, animated: true)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if refreshControl.isRefreshing {
            return
        }

        activityIndicator.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
        persistAnalyticsCookiesIfNeeded(from: webView)
    }

    private func persistAnalyticsCookiesIfNeeded(from webView: WKWebView) {
        let sidStored = readPersistentAnalyticsSid()
        let hsidStored = readPersistentAnalyticsHsid()

        if sidStored != nil && hsidStored != nil {
            return
        }

        guard let currentHost = webView.url?.host?.lowercased() else {
            return
        }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else {
                return
            }

            if sidStored == nil,
               let sid = cookies.first(where: { $0.name == "sid" && self.cookieDomainMatches($0.domain, host: currentHost) })?.value,
               !sid.isEmpty {
                self.storePersistentAnalyticsSid(sid)
            }

            if hsidStored == nil,
               let hsid = cookies.first(where: { $0.name == "hsid" && self.cookieDomainMatches($0.domain, host: currentHost) })?.value,
               !hsid.isEmpty {
                self.storePersistentAnalyticsHsid(hsid)
            }
        }
    }

    private func cookieDomainMatches(_ cookieDomain: String, host: String) -> Bool {
        let normalizedDomain = cookieDomain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalizedDomain == host || allowedHosts.contains(normalizedDomain)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""

        if ["http", "https"].contains(scheme) {
            guard let host = url.host, !host.isEmpty else {
                decisionHandler(.cancel)
                return
            }

            if canLoadInWebView(url) {
                decisionHandler(.allow)
            } else {
                if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                    openExternally(url)
                }
                decisionHandler(.cancel)
            }
            return
        }

        if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
            openExternally(url)
        }
        decisionHandler(.cancel)
    }

    @available(iOS 15.0, *)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        guard let originURL = URL(string: "\(origin.protocol)://\(origin.host)") else {
            decisionHandler(.deny)
            return
        }

        decisionHandler(canLoadInWebView(originURL) ? .grant : .deny)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == jpLocalStorageChangedHandlerName {
            handleLocalStorageChanged(message)
            return
        }

        guard message.name == jpScanBarcodeHandlerName else {
            return
        }

        guard let payload = message.body as? [String: Any],
              let requestId = payload["requestId"] as? String,
              !requestId.isEmpty else {
            return
        }

        guard isTrustedBridgeMessage(message) else {
            sendNativeScanResult(
                requestId: requestId,
                status: "error",
                message: "Nepouzdani izvor."
            )
            return
        }

        guard activeScanRequestId == nil else {
            sendNativeScanResult(
                requestId: requestId,
                status: "error",
                message: "Skeniranje je već aktivno."
            )
            return
        }

        startNativeBarcodeScan(requestId: requestId)
    }

    private func handleLocalStorageChanged(_ message: WKScriptMessage) {
        guard isTrustedBridgeMessage(message) else { return }

        guard let payload = message.body as? [String: Any],
              let key = payload["key"] as? String,
              jpLocalStorageAllowedKeys.contains(key) else {
            return
        }

        var stored = readPersistedLocalStorage()
        let value = payload["value"] as? String

        if let value {
            stored[key] = value
        } else {
            stored.removeValue(forKey: key)
        }

        storePersistedLocalStorage(stored)
    }

    fileprivate func barcodeScannerViewController(_ controller: BarcodeScannerViewController, didScan barCode: String, requestId: String) {
        activeScanRequestId = nil
        sendNativeScanResult(requestId: requestId, status: "success", barCode: barCode)
    }

    fileprivate func barcodeScannerViewControllerDidCancel(_ controller: BarcodeScannerViewController, requestId: String) {
        activeScanRequestId = nil
        sendNativeScanResult(requestId: requestId, status: "cancelled")
    }

    fileprivate func barcodeScannerViewController(_ controller: BarcodeScannerViewController, didFailWithMessage message: String, requestId: String) {
        activeScanRequestId = nil
        sendNativeScanResult(requestId: requestId, status: "error", message: message)
    }
}
