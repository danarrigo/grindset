package app.lockin.lockin

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import java.io.ByteArrayOutputStream

/** Installed app label and a small PNG icon, for display only. */
object AppDetails {
    private const val ICON_PX = 96

    fun load(context: Context, pkg: String): Map<String, Any>? = try {
        val manager = context.packageManager
        val info = manager.getApplicationInfo(pkg, 0)
        val drawable = manager.getApplicationIcon(info)
        val bitmap = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, ICON_PX, ICON_PX)
        drawable.draw(Canvas(bitmap))
        val png = ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
        bitmap.recycle()
        mapOf("label" to manager.getApplicationLabel(info).toString(), "icon" to png)
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }
}
