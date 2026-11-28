package com.burrowsoft.piggybow

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

// FlutterFragmentActivity: local_auth (app lock biometrics) needs it.
class MainActivity : FlutterFragmentActivity() {
    // Feature 21, restoring a backup file: the phone's own document picker
    // (no storage permission), and nothing copied anywhere. The file's size is
    // checked first, and at most the limit + 1 bytes are ever read, even when
    // the size is unknown, so a big video can't fill the memory.
    private var pendingPick: MethodChannel.Result? = null
    private var pickLimit = 0L
    private val reader = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val openDocument =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            onPicked(uri)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Me → "Open settings" when Piggybow's notifications are off
        // (decisions 63 and 67). No permission and no plugin: the phone's own
        // screens.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
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
                } else {
                    result.notImplemented()
                }
            }
        // Restore from a file (lib/backup/backup_flow.dart): one pick at a time.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != OPEN_BACKUP_FILE) {
                    result.notImplemented()
                } else if (pendingPick != null) {
                    result.error("busy", "a file is already being picked", null)
                } else {
                    pendingPick = result
                    pickLimit = (call.argument<Number>("maxBytes") ?: 0).toLong()
                    try {
                        // Any file: a .piggybow file has no registered type.
                        openDocument.launch(arrayOf("*/*"))
                    } catch (e: Exception) {
                        pendingPick = null
                        result.error("unavailable", e.message, null)
                    }
                }
            }
    }

    override fun onDestroy() {
        reader.shutdown()
        super.onDestroy()
    }

    private fun onPicked(uri: Uri?) {
        val result = pendingPick ?: return
        pendingPick = null
        if (uri == null) {
            result.success(null)
            return
        }
        val limit = pickLimit
        reader.execute {
            val answer: Map<String, Any?> =
                try {
                    readPicked(uri, limit)
                } catch (e: Exception) {
                    mapOf("unreadable" to true)
                }
            main.post { result.success(answer) }
        }
    }

    // The picked file's name, and its bytes unless it's larger than [limit]:
    // by its SIZE when the provider knows it, and while reading either way
    // (an unknown size is never taken as small). Read into memory only.
    private fun readPicked(uri: Uri, limit: Long): Map<String, Any?> {
        var name: String? = null
        var size: Long? = null
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val n = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val s = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (n >= 0 && !cursor.isNull(n)) name = cursor.getString(n)
                if (s >= 0 && !cursor.isNull(s)) size = cursor.getLong(s)
            }
        }
        val known = size
        if (known != null && known > limit) {
            return mapOf("name" to name, "tooLarge" to true)
        }
        val input =
            contentResolver.openInputStream(uri)
                ?: return mapOf("name" to name, "unreadable" to true)
        val out = ByteArrayOutputStream()
        input.use { stream ->
            val buffer = ByteArray(64 * 1024)
            var total = 0L
            while (true) {
                val read = stream.read(buffer)
                if (read < 0) break
                total += read
                if (total > limit) return mapOf("name" to name, "tooLarge" to true)
                out.write(buffer, 0, read)
            }
        }
        return mapOf("name" to name, "bytes" to out.toByteArray())
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
        // The same names as lib/core/device.dart and lib/backup/backup_flow.dart
        // (tests check both sides).
        const val SETTINGS_CHANNEL = "com.burrowsoft.piggybow/settings"
        const val OPEN_NOTIFICATION_SETTINGS = "openNotificationSettings"
        const val ANDROID_SDK = "androidSdk"
        const val BACKUP_CHANNEL = "com.burrowsoft.piggybow/backup"
        const val OPEN_BACKUP_FILE = "openBackupFile"
    }
}
