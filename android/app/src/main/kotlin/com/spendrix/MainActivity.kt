package com.spendrix

import android.content.pm.PackageManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }
}
