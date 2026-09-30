package com.example.yusal

import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var ready = false
    private val pending = mutableListOf<Map<String, Any>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yusal/house_import")
        channel!!.setMethodCallHandler { call, result ->
            if (call.method == "getPending") {
                ready = true
                result.success(pending.toList())
                pending.clear()
            } else result.notImplemented()
        }
        receive(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receive(intent)
    }

    private fun receive(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        Thread {
            val payload: Map<String, Any> = try {
                var size: Long? = null
                contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) size = cursor.getLong(0)
                }
                if (size != null && size!! > 10485760) {
                    mapOf("error" to "FILE_TOO_LARGE")
                } else {
                    contentResolver.openInputStream(uri)?.use { input ->
                        val output = ByteArrayOutputStream()
                        val chunk = ByteArray(8192)
                        var tooLarge = false
                        while (true) {
                            val count = input.read(chunk, 0, minOf(chunk.size, 10485761 - output.size()))
                            if (count <= 0) break
                            if (output.size() + count > 10485760) { tooLarge = true; break }
                            output.write(chunk, 0, count)
                        }
                        if (tooLarge) mapOf("error" to "FILE_TOO_LARGE") else mapOf("bytes" to output.toByteArray())
                    } ?: mapOf("error" to "IO_ERROR")
                }
            } catch (_: Exception) { mapOf("error" to "IO_ERROR") }
            runOnUiThread {
                if (ready) channel?.invokeMethod("importFile", payload) else pending.add(payload)
            }
        }.start()
    }
}
