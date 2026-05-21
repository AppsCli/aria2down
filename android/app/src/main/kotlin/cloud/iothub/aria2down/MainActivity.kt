package cloud.iothub.aria2down

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var controlSink: EventChannel.EventSink? = null
    private var pendingControl: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cloud.iothub.aria2down/keep_alive",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start", "update" -> {
                    ensureNotificationPermission()
                    val intent = Intent(this, Aria2KeepAliveService::class.java).apply {
                        action = if (call.method == "start") {
                            Aria2KeepAliveService.ACTION_START
                        } else {
                            Aria2KeepAliveService.ACTION_UPDATE
                        }
                        putExtra(
                            Aria2KeepAliveService.EXTRA_DOWN_SPEED,
                            (call.argument<Number>("downSpeed") ?: 0).toLong(),
                        )
                        putExtra(
                            Aria2KeepAliveService.EXTRA_UP_SPEED,
                            (call.argument<Number>("upSpeed") ?: 0).toLong(),
                        )
                        putExtra(
                            Aria2KeepAliveService.EXTRA_ACTIVE,
                            (call.argument<Number>("active") ?: 0).toInt(),
                        )
                        putExtra(
                            Aria2KeepAliveService.EXTRA_WAITING,
                            (call.argument<Number>("waiting") ?: 0).toInt(),
                        )
                        call.argument<String>("title")?.let {
                            putExtra(Aria2KeepAliveService.EXTRA_TITLE, it)
                        }
                        call.argument<String>("labelShow")?.let {
                            putExtra(Aria2KeepAliveService.EXTRA_LABEL_SHOW, it)
                        }
                        call.argument<String>("labelPause")?.let {
                            putExtra(Aria2KeepAliveService.EXTRA_LABEL_PAUSE, it)
                        }
                        call.argument<String>("labelResume")?.let {
                            putExtra(Aria2KeepAliveService.EXTRA_LABEL_RESUME, it)
                        }
                        call.argument<String>("labelQuit")?.let {
                            putExtra(Aria2KeepAliveService.EXTRA_LABEL_QUIT, it)
                        }
                    }
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

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cloud.iothub.aria2down/keep_alive_control",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    controlSink = events
                    val pending = pendingControl
                    if (pending != null && events != null) {
                        events.success(pending)
                        pendingControl = null
                    }
                }

                override fun onCancel(arguments: Any?) {
                    controlSink = null
                }
            },
        )

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

    override fun onCreate(savedInstanceState: Bundle?) {
        normalizeSendIntent(intent)
        super.onCreate(savedInstanceState)
        handleControlIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        normalizeSendIntent(intent)
        super.onNewIntent(intent)
        handleControlIntent(intent)
    }

    private fun handleControlIntent(intent: Intent?) {
        val action = intent?.action ?: return
        val control = when (action) {
            Aria2KeepAliveService.ACTION_PAUSE_ALL -> "pause_all"
            Aria2KeepAliveService.ACTION_RESUME_ALL -> "resume_all"
            Aria2KeepAliveService.ACTION_SHOW_WINDOW -> "show_window"
            else -> return
        }
        // 控制信号被消费一次后清除，避免下次进入 Activity 再次触发。
        intent.action = Intent.ACTION_MAIN
        val sink = controlSink
        if (sink != null) {
            sink.success(control)
        } else {
            pendingControl = control
        }
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
