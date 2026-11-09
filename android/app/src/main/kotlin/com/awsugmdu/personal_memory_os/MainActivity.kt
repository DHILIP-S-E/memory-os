package com.awsugmdu.personal_memory_os

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands text shared from the system share sheet to Dart.
 *  - cold start: Dart asks once via `getInitialText`
 *  - app already running: we push it with `onShare`
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initialText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialText = sharedText(intent)
        // Home-screen widget content from Dart.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "update" && call.arguments is String) {
                PmosWidgetProvider.store(applicationContext, call.arguments as String)
                result.success(null)
            } else if (call.method == "pin") {
                result.success(PmosWidgetProvider.requestPin(applicationContext))
            } else {
                result.notImplemented()
            }
        }
        val usage = UsageStatsBridge(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USAGE_CHANNEL).setMethodCallHandler(usage::handle)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "getInitialText") {
                    result.success(initialText)
                    initialText = null // deliver a share only once
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedText(intent)?.let { channel?.invokeMethod("onShare", it) }
    }

    private fun sharedText(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            intent.getStringExtra(Intent.EXTRA_TEXT)
        } else {
            null
        }

    companion object {
        private const val CHANNEL = "pmos/share"
        private const val WIDGET_CHANNEL = "pmos/widget"
        private const val USAGE_CHANNEL = "pmos/usage"
    }
}
