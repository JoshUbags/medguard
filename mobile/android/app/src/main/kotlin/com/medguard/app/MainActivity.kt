package com.medguard.app

import android.content.Intent
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter activity host.
 *
 * Two responsibilities beyond plain hosting:
 *   1. FlutterFragmentActivity is required by `local_auth` so the biometric
 *      prompt can be hosted by the AndroidX fragment manager.
 *   2. The `medguard.app/intents` MethodChannel exposes the launch URI (and
 *      any subsequent deep-link intents) to Dart so the lock-screen
 *      emergency widget can route directly to the emergency screen rather
 *      than dumping the user on the home tab.
 */
class MainActivity : FlutterFragmentActivity() {

    private val channelName = "medguard.app/intents"
    private var pendingDeepLink: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> result.success(
                        intent?.dataString ?: pendingDeepLink,
                    )
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val link = intent.dataString
        if (link != null) {
            pendingDeepLink = link
            channel?.invokeMethod("onDeepLink", link)
        }
    }
}
