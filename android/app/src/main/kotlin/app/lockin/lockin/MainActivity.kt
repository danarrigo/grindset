package app.lockin.lockin

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        TrackingRuntime.attach(this)
        return TrackingRuntime.engine(context, FlutterShellArgs.fromIntent(intent).toArray())
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onResume() {
        super.onResume()
        TrackingRuntime.attach(this)
        TrackingRuntime.maybeStart(this, askNotifications = true)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == TrackingRuntime.NOTIFICATION_PERMISSION_REQUEST) TrackingRuntime.maybeStart(this)
    }

    override fun onDestroy() {
        super.onDestroy()
        TrackingRuntime.detach(this)
    }
}
