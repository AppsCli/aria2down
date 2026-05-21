package cloud.iothub.aria2down

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/**
 * 前台服务：本机 aria2 运行时降低被系统回收的概率。
 *
 * - `ACTION_START` 启动 / 更新通知；Extra 携带速率与任务数。
 * - `ACTION_UPDATE` 仅更新通知（不重启服务）。
 * - `ACTION_PAUSE_ALL` / `ACTION_RESUME_ALL` / `ACTION_QUIT` 由通知按钮
 *   触发，进一步通过 [MainActivity] 转发到 Dart 控制信号 stream。
 *
 * 仅在「有活跃任务」时保持 [PowerManager.PARTIAL_WAKE_LOCK]，避免空闲
 * 持锁耗电。
 */
class Aria2KeepAliveService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()

        val action = intent?.action ?: ACTION_START
        when (action) {
            ACTION_PAUSE_ALL, ACTION_RESUME_ALL, ACTION_QUIT -> {
                forwardControlToActivity(action)
                if (action == ACTION_QUIT) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }

        val down = intent?.getLongExtra(EXTRA_DOWN_SPEED, 0L) ?: 0L
        val up = intent?.getLongExtra(EXTRA_UP_SPEED, 0L) ?: 0L
        val active = intent?.getIntExtra(EXTRA_ACTIVE, 0) ?: 0
        val waiting = intent?.getIntExtra(EXTRA_WAITING, 0) ?: 0
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: getString(R.string.keep_alive_title)
        val showCtl = intent?.getStringExtra(EXTRA_LABEL_SHOW) ?: "Show"
        val pauseCtl = intent?.getStringExtra(EXTRA_LABEL_PAUSE) ?: "Pause"
        val resumeCtl = intent?.getStringExtra(EXTRA_LABEL_RESUME) ?: "Resume"
        val quitCtl = intent?.getStringExtra(EXTRA_LABEL_QUIT) ?: "Quit"

        val notif = buildNotification(
            title = title,
            body = formatStats(down, up, active, waiting),
            showLabel = showCtl,
            pauseLabel = pauseCtl,
            resumeLabel = resumeCtl,
            quitLabel = quitCtl,
        )
        startForeground(NOTIFICATION_ID, notif)

        if (active > 0) acquireWakeLock() else releaseWakeLock()

        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun formatStats(down: Long, up: Long, active: Int, waiting: Int): String {
        return "↓ ${formatSpeed(down)}  ↑ ${formatSpeed(up)}  " +
                getString(R.string.keep_alive_stats_active, active, waiting)
    }

    private fun formatSpeed(bytesPerSec: Long): String {
        if (bytesPerSec < 1024) return "$bytesPerSec B/s"
        val kb = bytesPerSec / 1024.0
        if (kb < 1024) return String.format("%.1f KiB/s", kb)
        val mb = kb / 1024.0
        if (mb < 1024) return String.format("%.1f MiB/s", mb)
        val gb = mb / 1024.0
        return String.format("%.2f GiB/s", gb)
    }

    private fun buildNotification(
        title: String,
        body: String,
        showLabel: String,
        pauseLabel: String,
        resumeLabel: String,
        quitLabel: String,
    ): Notification {
        val contentIntent = activityIntent(ACTION_SHOW_WINDOW)
        val pauseIntent = servicePendingIntent(ACTION_PAUSE_ALL, REQ_PAUSE)
        val resumeIntent = servicePendingIntent(ACTION_RESUME_ALL, REQ_RESUME)
        val quitIntent = servicePendingIntent(ACTION_QUIT, REQ_QUIT)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(contentIntent)
            .addAction(0, showLabel, contentIntent)
            .addAction(0, pauseLabel, pauseIntent)
            .addAction(0, resumeLabel, resumeIntent)
            .addAction(0, quitLabel, quitIntent)
            .build()
    }

    private fun activityIntent(action: String): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            this.action = action
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(this, REQ_SHOW, intent, flags)
    }

    private fun servicePendingIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, Aria2KeepAliveService::class.java).apply {
            this.action = action
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getService(this, requestCode, intent, flags)
    }

    private fun forwardControlToActivity(action: String) {
        // 启动 / 唤起 MainActivity 并夹带 control action，Flutter 侧根据
        // intent.action 把指令分发给 Riverpod 控制器。
        val intent = Intent(this, MainActivity::class.java).apply {
            this.action = action
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        try {
            startActivity(intent)
        } catch (_: Throwable) {
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.keep_alive_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.keep_alive_channel_desc)
            setShowBadge(false)
        }
        mgr.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        val current = wakeLock
        if (current != null && current.isHeld) return
        val pm = getSystemService(POWER_SERVICE) as? PowerManager ?: return
        val lock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
        try {
            lock.setReferenceCounted(false)
            lock.acquire(WAKE_LOCK_TIMEOUT_MS)
            wakeLock = lock
        } catch (_: Throwable) {
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        try {
            if (lock.isHeld) lock.release()
        } catch (_: Throwable) {
        }
        wakeLock = null
    }

    companion object {
        const val CHANNEL_ID = "aria2down_daemon"
        const val NOTIFICATION_ID = 0x4152

        const val ACTION_START = "cloud.iothub.aria2down.action.START"
        const val ACTION_UPDATE = "cloud.iothub.aria2down.action.UPDATE"
        const val ACTION_PAUSE_ALL = "cloud.iothub.aria2down.action.PAUSE_ALL"
        const val ACTION_RESUME_ALL = "cloud.iothub.aria2down.action.RESUME_ALL"
        const val ACTION_QUIT = "cloud.iothub.aria2down.action.QUIT"
        const val ACTION_SHOW_WINDOW = "cloud.iothub.aria2down.action.SHOW_WINDOW"

        const val EXTRA_DOWN_SPEED = "downSpeed"
        const val EXTRA_UP_SPEED = "upSpeed"
        const val EXTRA_ACTIVE = "active"
        const val EXTRA_WAITING = "waiting"
        const val EXTRA_TITLE = "title"
        const val EXTRA_LABEL_SHOW = "labelShow"
        const val EXTRA_LABEL_PAUSE = "labelPause"
        const val EXTRA_LABEL_RESUME = "labelResume"
        const val EXTRA_LABEL_QUIT = "labelQuit"

        private const val REQ_SHOW = 0x100
        private const val REQ_PAUSE = 0x101
        private const val REQ_RESUME = 0x102
        private const val REQ_QUIT = 0x103

        private const val WAKE_LOCK_TAG = "aria2down:keepalive"
        private const val WAKE_LOCK_TIMEOUT_MS = 30L * 60L * 1000L // 30 min 防御性兜底
    }
}
