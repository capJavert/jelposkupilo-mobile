import UIKit
import WebKit

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let allowedHosts = ["jelposkupilo.eu", "www.jelposkupilo.eu"]
    private let webLightBackground = UIColor.white
    private let webDarkBackground = UIColor(red: 19.0 / 255.0, green: 19.0 / 255.0, blue: 24.0 / 255.0, alpha: 1.0)
    private var webView: WKWebView!
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let safeAreaBackgroundView = UIView()
    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(reloadPage), for: .valueChanged)
        return control
    }()

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

        webView.load(URLRequest(url: url))
    }

    @objc
    private func reloadPage() {
        webView.reload()
    }

    private func canLoadInWebView(_ url: URL) -> Bool {
        guard let host = url.host else {
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

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activityIndicator.startAnimating()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        activityIndicator.stopAnimating()
        refreshControl.endRefreshing()
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
            // Ignore malformed http(s) URLs like "http:" with no host.
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
}
