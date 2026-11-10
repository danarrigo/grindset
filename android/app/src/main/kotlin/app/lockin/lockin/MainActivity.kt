package app.lockin.lockin

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.lockin/usage")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageAccess" -> result.success(UsageReader.hasAccess(this))
                "requestUsageAccess" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.data = Uri.parse("package:$packageName")
                    startActivity(intent)
                    result.success(null)
                }
                "readUsage" -> {
                    val from = call.argument<Number>("from")?.toLong()
                    val until = call.argument<Number>("until")?.toLong()
                    if (from == null || until == null || from >= until) {
                        result.error("INVALID_RANGE", "Choose a positive usage range", null)
                    } else {
                        executor.execute {
                            try {
                                val records = UsageReader.read(this, from, until)
                                runOnUiThread { result.success(records) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("USAGE_READ_FAILED", error.message, null) }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }
}
