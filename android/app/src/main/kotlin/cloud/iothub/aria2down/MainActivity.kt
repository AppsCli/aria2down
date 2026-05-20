package cloud.iothub.aria2down

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cloud.iothub.aria2down/keep_alive",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    ensureNotificationPermission()
                    val intent = Intent(this, Aria2KeepAliveService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, Aria2KeepAliveService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 外部唤起：从 content:// 读取字节 (.torrent / .metalink)，回传 ByteArray。
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cloud.iothub.aria2down/incoming_link",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readContent" -> {
                    val uriStr = call.argument<String>("uri")
                    if (uriStr == null) {
                        result.error("ARG", "missing uri", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = Uri.parse(uriStr)
                        val bytes = contentResolver.openInputStream(uri)?.use {
                            it.readBytes()
                        }
                        if (bytes == null) {
                            result.error("IO", "openInputStream returned null", null)
                        } else {
                            result.success(bytes)
                        }
                    } catch (e: Exception) {
                        result.error("IO", e.message ?: e.javaClass.simpleName, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ACTION_SEND 的 text 不会被 app_links 视作 deep link；把它包装成
    // aria2down:// scheme 后回写到 intent，app_links 自然能接到。
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        normalizeSendIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        normalizeSendIntent(intent)
        super.onNewIntent(intent)
    }

    private fun normalizeSendIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        if (text.isBlank()) return
        val encoded = Uri.encode(text)
        intent.action = Intent.ACTION_VIEW
        intent.data = Uri.parse("aria2down://add?uri=$encoded")
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    companion object {
        private const val REQUEST_POST_NOTIFICATIONS = 0x4152_4E54
    }
}
