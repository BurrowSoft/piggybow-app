package com.burrowsoft.piggybow

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: local_auth (app lock biometrics) needs it.
class MainActivity : FlutterFragmentActivity() {
    // The home-screen shortcut's action (res/xml/shortcuts.xml), kept until
    // Flutter takes it (lib/core/launch_actions.dart).
    private var launchAction: String? = null
    private var settings: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Not on a re-creation: that start was answered the first time.
        if (savedInstanceState == null) noteLaunchAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // The app already open: tell Flutter one is waiting.
        if (noteLaunchAction(intent)) settings?.invokeMethod(LAUNCH_ACTION, null)
    }

    // "Add a spend" from the shortcut, unless Android is replaying an old
    // start from the recent apps.
    private fun noteLaunchAction(intent: Intent?): Boolean {
        if (intent == null || intent.action != ACTION_ADD_SPEND) return false
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return false
        launchAction = ADD_SPEND
        return true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Me → "Open settings" when Piggybow's notifications are off
        // (decisions 63 and 67). No permission and no plugin: the phone's own
        // screens.
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
        settings = channel
        channel
            .setMethodCallHandler { call, result ->
                if (call.method == OPEN_NOTIFICATION_SETTINGS) {
                    // Its notification settings; if those can't open, the
                    // app's details; if neither can, nothing (the notice
                    // already says where to go).
                    for (intent in listOf(notificationSettings(), appDetails())) {
                        try {
                            startActivity(intent)
                            break
                        } catch (e: Exception) {
                            // The next one.
                        }
                    }
                    result.success(null)
                } else if (call.method == ANDROID_SDK) {
                    // The Android version, read once at start-up: Android 7
                    // can't draw dark navigation-bar icons (lib/core/system_bars.dart).
                    result.success(Build.VERSION.SDK_INT)
                } else if (call.method == TAKE_LAUNCH_ACTION) {
                    // The shortcut's action, once: taking it clears it.
                    result.success(launchAction)
                    launchAction = null
                } else {
                    result.notImplemented()
                }
            }
    }

    // Android 8+: Piggybow's own notification settings; before that, its app
    // details page, where notifications are switched.
    private fun notificationSettings(): Intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            appDetails()
        }

    private fun appDetails(): Intent =
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.fromParts("package", packageName, null),
        )

    companion object {
        // The same names as lib/core/device.dart (a test checks both sides).
        const val SETTINGS_CHANNEL = "com.burrowsoft.piggybow/settings"
        const val OPEN_NOTIFICATION_SETTINGS = "openNotificationSettings"
        const val ANDROID_SDK = "androidSdk"
        const val TAKE_LAUNCH_ACTION = "takeLaunchAction"
        const val LAUNCH_ACTION = "launchAction"
        const val ADD_SPEND = "addSpend"

        // The shortcut's intent action (res/xml/shortcuts.xml, one per flavour).
        const val ACTION_ADD_SPEND = "com.burrowsoft.piggybow.action.ADD_SPEND"
    }
}
