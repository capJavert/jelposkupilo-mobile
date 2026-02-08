package eu.jelposkupilo.app

import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.FrameLayout
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.updatePadding
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout

class MainActivity : AppCompatActivity() {
    private lateinit var webView: WebView
    private lateinit var swipeRefreshLayout: SwipeRefreshLayout
    private lateinit var contentContainer: FrameLayout
    private lateinit var loadingView: View

    private val allowedHosts = setOf("jelposkupilo.eu", "www.jelposkupilo.eu")

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

        if (savedInstanceState == null) {
            webView.loadUrl(BuildConfig.BASE_URL)
        } else {
            webView.restoreState(savedInstanceState)
        }
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

    private fun configureWebView() {
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.loadsImagesAutomatically = true

        val cookieManager = CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(webView, true)

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

                val shouldOpenExternal =
                    request.isForMainFrame && (request.hasGesture() || !request.isRedirect)

                if (shouldOpenExternal) {
                    startActivity(Intent(Intent.ACTION_VIEW, targetUrl))
                }
                return true
            }

            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                loadingView.visibility = View.VISIBLE
            }

            override fun onPageFinished(view: WebView, url: String?) {
                loadingView.visibility = View.GONE
                swipeRefreshLayout.isRefreshing = false
            }
        }
    }

    private fun configureRefresh() {
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

    override fun onSaveInstanceState(outState: Bundle) {
        webView.saveState(outState)
        super.onSaveInstanceState(outState)
    }
}
