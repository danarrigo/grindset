package app.lockin.lockin

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** User-chosen document output, without broad storage permissions or a heap-sized byte array. */
object ExportFile {
    private const val REQUEST = 4303
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: Pair<File, MethodChannel.Result>? = null

    fun save(context: Context, host: Activity?, path: String, name: String, result: MethodChannel.Result) {
        checkNotNull(host) { "Open Grindset to export data." }
        check(pending == null) { "An export dialog is already open." }
        val source = File(path).canonicalFile
        require(source.path.startsWith(context.cacheDir.canonicalPath + File.separator) && source.isFile &&
            name.matches(Regex("[A-Za-z0-9_.-]+\\.json"))) { "Choose a prepared JSON archive." }
        pending = source to result
        try {
            host.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, name)
            }, REQUEST)
        } catch (error: Exception) {
            pending = null
            throw error
        }
    }

    fun onResult(context: Context, request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val job = pending ?: return true
        pending = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) {
            job.second.success(false)
            return true
        }
        executor.execute {
            try {
                job.first.inputStream().use { input ->
                    checkNotNull(context.contentResolver.openOutputStream(uri, "wt")).use { output -> input.copyTo(output) }
                }
                main.post { job.second.success(true) }
            } catch (_: Exception) {
                main.post { job.second.error("EXPORT_FAILED", "Could not save the archive. Check destination access and free space.", null) }
            }
        }
        return true
    }

    fun cancelPending() {
        pending?.second?.success(false)
        pending = null
    }
}
