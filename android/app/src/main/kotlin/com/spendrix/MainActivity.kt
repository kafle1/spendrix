package com.spendrix

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

// local_auth needs a FragmentActivity for the fingerprint prompt
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // with the app lock on, keep money out of screenshots and the recent-apps preview
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spendrix/secure").setMethodCallHandler { call, result ->
            if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            result.success(null)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spendrix/apps").setMethodCallHandler { call, result ->
            val installed = try {
                packageManager.getPackageInfo(call.arguments as String, 0); true
            } catch (e: PackageManager.NameNotFoundException) { false }
            result.success(installed)
        }
        // the update card downloads the apk into the cache, then this hands it to Android's installer
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spendrix/update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "canInstall" -> result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls())
                    "allow" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        }
                        result.success(null)
                    }
                    "install" -> {
                        val apk = FileProvider.getUriForFile(this, "$packageName.update", File(call.arguments as String))
                        startActivity(
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(apk, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update", e.message, null)
            }
        }
    }
}
