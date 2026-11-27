package com.burrowsoft.piggybow

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: local_auth (app lock biometrics) needs it.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Me → "Open settings" when Piggybow's notifications are off
        // (decision 63). No permission and no plugin: the phone's own screen.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == OPEN_NOTIFICATION_SETTINGS) {
                    startActivity(notificationSettings())
                    result.success(null)
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
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null),
            )
        }

    companion object {
        // The same names as lib/core/device.dart (a test checks both sides).
        const val SETTINGS_CHANNEL = "com.burrowsoft.piggybow/settings"
        const val OPEN_NOTIFICATION_SETTINGS = "openNotificationSettings"
    }
}
