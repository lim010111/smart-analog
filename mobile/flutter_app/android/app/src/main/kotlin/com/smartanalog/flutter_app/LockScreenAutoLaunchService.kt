package com.smartanalog.flutter_app

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat

class LockScreenAutoLaunchService : Service() {
    private var screenReceiver: BroadcastReceiver? = null
    private var lastWakeLaunchAtMs: Long = 0L
    private var overlayView: FrameLayout? = null
    private val overlayHandler = Handler(Looper.getMainLooper())
    private val clearOverlayRunnable = Runnable { clearOverlayPrompt() }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        registerScreenReceiver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val command = intent?.getStringExtra(extraCommand) ?: commandStart
        if (command == commandStop) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(notificationId, buildNotification())
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterScreenReceiver()
        clearOverlayPrompt()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun registerScreenReceiver() {
        if (screenReceiver != null) {
            return
        }

        val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    when (intent.action) {
                        Intent.ACTION_SCREEN_ON -> launchScreenSaverIfKeyguardLocked()
                        Intent.ACTION_SCREEN_OFF,
                        Intent.ACTION_USER_PRESENT,
                        -> clearOverlayPrompt()
                    }
                }
            }
        val filter = IntentFilter(Intent.ACTION_SCREEN_ON).apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(receiver, filter)
        screenReceiver = receiver
    }

    private fun unregisterScreenReceiver() {
        val receiver = screenReceiver ?: return
        runCatching { unregisterReceiver(receiver) }
        screenReceiver = null
    }

    private fun launchScreenSaverIfKeyguardLocked() {
        val keyguardManager = getSystemService(KeyguardManager::class.java)
        if (keyguardManager?.isKeyguardLocked != true) {
            return
        }

        val nowElapsed = SystemClock.elapsedRealtime()
        if (nowElapsed - lastWakeLaunchAtMs < wakeLaunchCooldownMs) {
            return
        }
        lastWakeLaunchAtMs = nowElapsed

        val launchIntent = buildScreenSaverLaunchIntent()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            runCatching { startActivity(launchIntent) }
            showOverlayPromptIfAvailable()
            return
        }

        val fullScreenPendingIntent =
            PendingIntent.getActivity(
                this,
                fullScreenPendingIntentRequestCode,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        runCatching { startActivity(launchIntent) }
        postWakeAlertNotification(fullScreenPendingIntent)
        showOverlayPromptIfAvailable()
    }

    private fun showOverlayPromptIfAvailable() {
        if (!canDrawOverlaysForApp()) {
            return
        }
        if (overlayView != null) {
            overlayHandler.removeCallbacks(clearOverlayRunnable)
            overlayHandler.postDelayed(clearOverlayRunnable, overlayAutoDismissMs)
            return
        }

        val windowManager = getSystemService(WindowManager::class.java) ?: return
        val overlay = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#7A000000"))
            isClickable = true
            setOnClickListener {
                clearOverlayPrompt()
                runCatching { startActivity(buildScreenSaverLaunchIntent()) }
            }
        }

        val promptText = TextView(this).apply {
            text = getString(R.string.lock_screen_overlay_prompt_text)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setBackgroundColor(Color.parseColor("#CC0F172A"))
            val horizontalPadding = (24 * resources.displayMetrics.density).toInt()
            val verticalPadding = (16 * resources.displayMetrics.density).toInt()
            setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding)
        }

        val promptLayoutParams =
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            )
        overlay.addView(promptText, promptLayoutParams)

        val overlayType =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            }

        val windowLayoutParams =
            WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                overlayType,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.CENTER
            }

        runCatching {
            windowManager.addView(overlay, windowLayoutParams)
        }.onSuccess {
            overlayView = overlay
            overlayHandler.removeCallbacks(clearOverlayRunnable)
            overlayHandler.postDelayed(clearOverlayRunnable, overlayAutoDismissMs)
        }
    }

    private fun clearOverlayPrompt() {
        overlayHandler.removeCallbacks(clearOverlayRunnable)
        val view = overlayView ?: return
        overlayView = null
        val windowManager = getSystemService(WindowManager::class.java) ?: return
        runCatching { windowManager.removeView(view) }
    }

    private fun canDrawOverlaysForApp(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return Settings.canDrawOverlays(this)
    }

    private fun buildScreenSaverLaunchIntent(): Intent {
        return Intent(this, MainActivity::class.java).apply {
            flags =
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.launchActionExtraKey, MainActivity.launchActionOpenScreenSaver)
        }
    }

    private fun postWakeAlertNotification(fullScreenPendingIntent: PendingIntent) {
        createWakeAlertChannelIfNeeded()
        val builder =
            NotificationCompat.Builder(this, wakeAlertChannelId)
                .setContentTitle(getString(R.string.lock_screen_wake_alert_title))
                .setContentText(getString(R.string.lock_screen_wake_alert_text))
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentIntent(fullScreenPendingIntent)
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
        if (canUseFullScreenIntentForApp()) {
            builder.setFullScreenIntent(fullScreenPendingIntent, true)
        }
        val notification = builder.build()

        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(wakeAlertNotificationId, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        val channel =
            NotificationChannel(
                notificationChannelId,
                getString(R.string.lock_screen_mode_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.lock_screen_mode_channel_description)
            }
        manager?.createNotificationChannel(channel)
    }

    private fun createWakeAlertChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(NotificationManager::class.java)
        val channel =
            NotificationChannel(
                wakeAlertChannelId,
                getString(R.string.lock_screen_wake_alert_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = getString(R.string.lock_screen_wake_alert_channel_description)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
        manager?.createNotificationChannel(channel)
    }

    private fun canUseFullScreenIntentForApp(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return true
        }
        val manager = getSystemService(NotificationManager::class.java)
        return manager?.canUseFullScreenIntent() == true
    }

    private fun buildNotification(): Notification {
        val openAppIntent =
            Intent(this, MainActivity::class.java).apply {
                flags =
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        return NotificationCompat.Builder(this, notificationChannelId)
            .setContentTitle(getString(R.string.lock_screen_mode_notification_title))
            .setContentText(getString(R.string.lock_screen_mode_notification_text))
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
    }

    companion object {
        private const val notificationId = 42001
        private const val notificationChannelId = "smart_analog_lock_screen_mode"
        private const val wakeAlertNotificationId = 42002
        private const val wakeAlertChannelId = "smart_analog_lock_screen_wake_alert"
        private const val fullScreenPendingIntentRequestCode = 42003
        private const val wakeLaunchCooldownMs = 2500L
        private const val overlayAutoDismissMs = 8000L
        private const val extraCommand = "command"
        private const val commandStart = "start"
        private const val commandStop = "stop"

        fun startIntent(context: Context): Intent {
            return Intent(context, LockScreenAutoLaunchService::class.java).apply {
                putExtra(extraCommand, commandStart)
            }
        }

        fun stopIntent(context: Context): Intent {
            return Intent(context, LockScreenAutoLaunchService::class.java).apply {
                putExtra(extraCommand, commandStop)
            }
        }
    }
}
