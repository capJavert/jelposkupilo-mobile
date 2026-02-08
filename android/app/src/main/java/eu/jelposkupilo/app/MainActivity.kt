package eu.jelposkupilo.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.updatePadding
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import org.json.JSONObject

private const val JP_NATIVE_SCAN_EVENT = "jp-native-scan-result"
private const val JP_ANALYTICS_PREFS = "jp_analytics"
private const val JP_ANALYTICS_SID_KEY = "jp_analytics_sid"
private const val JP_ANALYTICS_HSID_KEY = "jp_analytics_hsid"
private const val JP_ANALYTICS_COOKIE_MAX_AGE_SECONDS = 315360000L

class MainActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private lateinit var swipeRefreshLayout: SwipeRefreshLayout
    private lateinit var contentContainer: FrameLayout
    private lateinit var loadingView: View

    private val allowedHosts = setOf("jelposkupilo.eu", "www.jelposkupilo.eu")
    private var activeScanRequestId: String? = null
    private var pendingCameraPermissionRequestId: String? = null

    private val barcodeScanner: GmsBarcodeScanner by lazy {
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_EAN_13)
            .enableAutoZoom()
            .build()
        GmsBarcodeScanning.getClient(this, options)
    }

    private val cameraPermissionLauncher = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val requestId = pendingCameraPermissionRequestId
        pendingCameraPermissionRequestId = null

        if (requestId.isNullOrBlank()) {
            return@registerForActivityResult
        }

        if (granted) {
            launchNativeScanner(requestId)
        } else {
            activeScanRequestId = null
            dispatchNativeScanResult(requestId, "error", message = "Dozvola za kameru je odbijena.")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        setContentView(R.layout.activity_main)

        webView = findViewById(R.id.webView)
        swipeRefreshLayout = findViewById(R.id.swipeRefreshLayout)
        contentContainer = findViewById(R.id.contentContainer)
        loadingView = findViewById(R.id.loadingView)

        configureSystemInsets()
        applySurfaceColors()
        configureWebView()
        configureRefresh()
        configureBackNavigation()

        prepareAnalyticsCookies {
            if (savedInstanceState == null) {
                webView.loadUrl(BuildConfig.BASE_URL)
            } else {
                webView.restoreState(savedInstanceState)
            }
        }
    }

    private fun prepareAnalyticsCookies(onComplete: () -> Unit) {
        val baseUri = runCatching { Uri.parse(BuildConfig.BASE_URL) }.getOrNull()

        if (baseUri == null) {
            onComplete()
            return
        }

        val scheme = baseUri.scheme?.lowercase()
        val host = baseUri.host?.lowercase()
        if ((scheme != "http" && scheme != "https") || host.isNullOrBlank()) {
            onComplete()
            return
        }

        val storedSid = getStoredAnalyticsSid()
        if (storedSid.isNullOrBlank()) {
            onComplete()
            return
        }
        val storedHsid = getStoredAnalyticsHsid() ?: storedSid

        val cookieOptions = StringBuilder()
            .append("Path=/; Max-Age=")
            .append(JP_ANALYTICS_COOKIE_MAX_AGE_SECONDS)
            .append("; SameSite=Lax")
            .apply {
                if (scheme == "https") {
                    append("; Secure")
                }
            }
            .toString()

        val cookieValues = listOf(
            "sid=$storedSid; $cookieOptions",
            "hsid=$storedHsid; $cookieOptions"
        )

        val targetUrls = linkedSetOf<String>().apply {
            add(BuildConfig.BASE_URL)
            add("$scheme://$host")
            allowedHosts.forEach { allowedHost ->
                add("$scheme://$allowedHost")
            }
        }.toList()

        val cookiePairs = targetUrls.flatMap { targetUrl ->
            cookieValues.map { cookieValue -> targetUrl to cookieValue }
        }

        setCookiesSequentially(
            cookieManager = CookieManager.getInstance(),
            cookiePairs = cookiePairs,
            index = 0,
            onComplete = onComplete
        )
    }

    private fun setCookiesSequentially(
        cookieManager: CookieManager,
        cookiePairs: List<Pair<String, String>>,
        index: Int,
        onComplete: () -> Unit
    ) {
        if (index >= cookiePairs.size) {
            cookieManager.flush()
            onComplete()
            return
        }

        val (url, cookieValue) = cookiePairs[index]
        cookieManager.setCookie(url, cookieValue) {
            setCookiesSequentially(cookieManager, cookiePairs, index + 1, onComplete)
        }
    }

    private fun getStoredAnalyticsSid(): String? {
        val prefs = getSharedPreferences(JP_ANALYTICS_PREFS, MODE_PRIVATE)
        return prefs.getString(JP_ANALYTICS_SID_KEY, null)
    }

    private fun getStoredAnalyticsHsid(): String? {
        val prefs = getSharedPreferences(JP_ANALYTICS_PREFS, MODE_PRIVATE)
        return prefs.getString(JP_ANALYTICS_HSID_KEY, null)
    }

    private fun persistAnalyticsCookiesFromUrl(urlString: String?) {
        val sidStored = getStoredAnalyticsSid()
        val hsidStored = getStoredAnalyticsHsid()

        if (!sidStored.isNullOrBlank() && !hsidStored.isNullOrBlank()) {
            return
        }

        val targetUrl = if (!urlString.isNullOrBlank()) urlString else BuildConfig.BASE_URL
        val cookieHeader = CookieManager.getInstance().getCookie(targetUrl) ?: return
        val cookies = parseCookieHeader(cookieHeader)

        val editor = getSharedPreferences(JP_ANALYTICS_PREFS, MODE_PRIVATE).edit()
        var shouldCommit = false

        if (sidStored.isNullOrBlank()) {
            val sid = cookies["sid"]
            if (!sid.isNullOrBlank()) {
                editor.putString(JP_ANALYTICS_SID_KEY, sid)
                shouldCommit = true
            }
        }

        if (hsidStored.isNullOrBlank()) {
            val hsid = cookies["hsid"]
            if (!hsid.isNullOrBlank()) {
                editor.putString(JP_ANALYTICS_HSID_KEY, hsid)
                shouldCommit = true
            }
        }

        if (shouldCommit) {
            editor.apply()
        }
    }

    private fun parseCookieHeader(cookieHeader: String): Map<String, String> {
        return cookieHeader
            .split(';')
            .mapNotNull { cookiePart ->
                val index = cookiePart.indexOf('=')
                if (index <= 0) {
                    return@mapNotNull null
                }

                val name = cookiePart.substring(0, index).trim()
                val value = cookiePart.substring(index + 1).trim()
                if (name.isEmpty() || value.isEmpty()) {
                    return@mapNotNull null
                }

                name to value
            }
            .toMap()
    }

    private fun configureSystemInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(swipeRefreshLayout) { view, insets ->
            val systemInsets = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()
            )

            view.updatePadding(
                left = systemInsets.left,
                top = systemInsets.top,
                right = systemInsets.right,
                bottom = systemInsets.bottom
            )

            insets
        }

        ViewCompat.requestApplyInsets(swipeRefreshLayout)
    }

    private fun applySurfaceColors() {
        val surfaceColor = ContextCompat.getColor(this, R.color.web_header_surface)

        swipeRefreshLayout.setBackgroundColor(surfaceColor)
        contentContainer.setBackgroundColor(surfaceColor)
        webView.setBackgroundColor(surfaceColor)

        window.statusBarColor = surfaceColor
        window.navigationBarColor = surfaceColor

        val isDarkMode = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val insetsController = WindowInsetsControllerCompat(window, window.decorView)
        insetsController.isAppearanceLightStatusBars = !isDarkMode
        insetsController.isAppearanceLightNavigationBars = !isDarkMode
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView() {
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.loadsImagesAutomatically = true

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(webView, true)

        webView.addJavascriptInterface(JPNativeBridge(), "JPNativeBridge")
        webView.webChromeClient = WebChromeClient()
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest
            ): Boolean {
                val targetUrl = request.url ?: return true

                if (isAllowedInWebView(targetUrl)) {
                    return false
                }

                val shouldOpenExternal = request.isForMainFrame && (request.hasGesture() || !request.isRedirect)

                if (shouldOpenExternal) {
                    startActivity(Intent(Intent.ACTION_VIEW, targetUrl))
                }
                return true
            }

            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                if (swipeRefreshLayout.isRefreshing) {
                    loadingView.visibility = View.GONE
                    return
                }

                loadingView.visibility = View.VISIBLE
            }

            override fun onPageFinished(view: WebView, url: String?) {
                loadingView.visibility = View.GONE
                swipeRefreshLayout.isRefreshing = false
                persistAnalyticsCookiesFromUrl(url)
            }
        }
    }

    private fun configureRefresh() {
        swipeRefreshLayout.setOnChildScrollUpCallback { _, _ ->
            webView.scrollY > 0
        }
        swipeRefreshLayout.setOnRefreshListener {
            webView.reload()
        }
    }

    private fun configureBackNavigation() {
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                if (webView.canGoBack()) {
                    webView.goBack()
                } else {
                    finish()
                }
            }
        })
    }

    private fun isAllowedInWebView(uri: Uri): Boolean {
        val scheme = uri.scheme?.lowercase()
        val host = uri.host?.lowercase()

        if (scheme != "http" && scheme != "https") {
            return false
        }

        if (host.isNullOrBlank()) {
            return false
        }

        if (host in allowedHosts) {
            return true
        }

        return BuildConfig.DEBUG && (host == "localhost" || host == "10.0.2.2" || host == "127.0.0.1")
    }

    private fun isCurrentPageTrustedForBridge(): Boolean {
        val currentUrl = webView.url ?: return false
        val uri = runCatching { Uri.parse(currentUrl) }.getOrNull() ?: return false
        return isAllowedInWebView(uri)
    }

    private fun startNativeBarcodeScan(requestId: String) {
        if (!isCurrentPageTrustedForBridge()) {
            dispatchNativeScanResult(requestId, "error", message = "Nepouzdan izvor.")
            return
        }

        if (activeScanRequestId != null) {
            dispatchNativeScanResult(requestId, "error", message = "Skeniranje je već aktivno.")
            return
        }

        activeScanRequestId = requestId

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            pendingCameraPermissionRequestId = requestId
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
            return
        }

        launchNativeScanner(requestId)
    }

    private fun launchNativeScanner(requestId: String) {
        barcodeScanner.startScan()
            .addOnSuccessListener { barcode ->
                val value = barcode.rawValue

                if (value.isNullOrBlank()) {
                    dispatchNativeScanResult(requestId, "error", message = "Barkod nije prepoznat.")
                } else {
                    dispatchNativeScanResult(requestId, "success", barCode = value)
                }
            }
            .addOnCanceledListener {
                dispatchNativeScanResult(requestId, "cancelled")
            }
            .addOnFailureListener {
                dispatchNativeScanResult(requestId, "error", message = "Skeniranje nije uspjelo.")
            }
            .addOnCompleteListener {
                activeScanRequestId = null
            }
    }

    private fun dispatchNativeScanResult(
        requestId: String,
        status: String,
        barCode: String? = null,
        message: String? = null
    ) {
        val detail = JSONObject().apply {
            put("requestId", requestId)
            put("status", status)
            if (!barCode.isNullOrBlank()) {
                put("barCode", barCode)
            }
            if (!message.isNullOrBlank()) {
                put("message", message)
            }
        }

        val script = "window.dispatchEvent(new CustomEvent('$JP_NATIVE_SCAN_EVENT', { detail: ${detail} }));"
        webView.post {
            webView.evaluateJavascript(script, null)
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        webView.saveState(outState)
        super.onSaveInstanceState(outState)
    }

    private inner class JPNativeBridge {
        @JavascriptInterface
        fun jpScanBarcode(requestId: String?) {
            if (requestId.isNullOrBlank()) {
                return
            }

            runOnUiThread {
                startNativeBarcodeScan(requestId)
            }
        }
    }
}
