package com.smartanalog.flutter_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingLaunchAction: String? = null
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cacheLaunchAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        cacheLaunchAction(intent)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != notificationPermissionRequestCode) {
            return
        }
        val granted =
            grantResults.isNotEmpty() &&
                grantResults.first() == PackageManager.PERMISSION_GRANTED
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            widgetHostChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                syncWidgetPayloadMethod -> {
                    val payload = call.arguments as? Map<*, *>
                    if (payload == null) {
                        result.error("invalid_args", "Expected map payload", null)
                        return@setMethodCallHandler
                    }

                    runCatching {
                        val snapshotFile = File(applicationContext.filesDir, widgetReadFileName)
                        snapshotFile.writeText(JSONObject(payload).toString())
                    }.onSuccess {
                        result.success(true)
                    }.onFailure { error ->
                        result.error("write_failed", error.message, null)
                    }
                }

                refreshWidgetsMethod -> {
                    SmartAnalogAppWidgetProvider.refreshAllWidgets(applicationContext)
                    SmartAnalogLockStarWidgetProvider.refreshAllWidgets(applicationContext)
                    result.success(true)
                }

                enableScreenSaverModeMethod -> {
                    enableScreenSaverMode()
                    result.success(true)
                }

                disableScreenSaverModeMethod -> {
                    disableScreenSaverMode()
                    result.success(true)
                }

                enableAutoLockScreenModeMethod -> {
                    enableAutoLockScreenMode()
                    result.success(true)
                }

                disableAutoLockScreenModeMethod -> {
                    disableAutoLockScreenMode()
                    result.success(true)
                }

                checkNotificationPermissionMethod -> {
                    result.success(hasNotificationPermission())
                }

                requestNotificationPermissionMethod -> {
                    requestNotificationPermission(result)
                }

                isNotificationPermissionRuntimeRequiredMethod -> {
                    result.success(isNotificationPermissionRuntimeRequired())
                }

                isIgnoringBatteryOptimizationsMethod -> {
                    result.success(isIgnoringBatteryOptimizations())
                }

                openBatteryOptimizationSettingsMethod -> {
                    result.success(openBatteryOptimizationSettings())
                }

                openNotificationSettingsMethod -> {
                    result.success(openNotificationSettings())
                }

                openAppPermissionSettingsMethod -> {
                    result.success(openAppPermissionSettings())
                }

                canDrawOverlaysMethod -> {
                    result.success(canDrawOverlays())
                }

                openOverlayPermissionSettingsMethod -> {
                    result.success(openOverlayPermissionSettings())
                }

                canUseFullScreenIntentMethod -> {
                    result.success(canUseFullScreenIntent())
                }

                openFullScreenIntentSettingsMethod -> {
                    result.success(openFullScreenIntentSettings())
                }

                consumeLaunchActionMethod -> {
                    result.success(consumeLaunchAction())
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun cacheLaunchAction(currentIntent: Intent?) {
        val action = currentIntent?.getStringExtra(launchActionExtraKey)
        if (action == launchActionOpenScreenSaver) {
            pendingLaunchAction = action
        }
    }

    private fun consumeLaunchAction(): String? {
        val action = pendingLaunchAction
        pendingLaunchAction = null
        return action
    }

    private fun setLockScreenVisibility(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(enabled)
            setTurnScreenOn(enabled)
        } else {
            val lockFlags =
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (enabled) {
                window.addFlags(lockFlags)
            } else {
                window.clearFlags(lockFlags)
            }
        }
    }

    private fun enableScreenSaverMode() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setLockScreenVisibility(true)
    }

    private fun disableScreenSaverMode() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setLockScreenVisibility(false)
    }

    private fun enableAutoLockScreenMode() {
        ContextCompat.startForegroundService(
            this,
            LockScreenAutoLaunchService.startIntent(this),
        )
    }

    private fun disableAutoLockScreenMode() {
        stopService(LockScreenAutoLaunchService.stopIntent(this))
    }

    private fun hasNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun isNotificationPermissionRuntimeRequired(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (hasNotificationPermission()) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error("permission_busy", "Notification permission request already in progress", null)
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val powerManager = getSystemService(PowerManager::class.java)
        return powerManager?.isIgnoringBatteryOptimizations(packageName) == true
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        val requestIntent =
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        val fallbackIntent =
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        return launchSettingsIntent(requestIntent, fallbackIntent)
    }

    private fun openNotificationSettings(): Boolean {
        val notificationIntent = openNotificationSettingsIntent()
        return launchSettingsIntent(notificationIntent, buildAppDetailsSettingsIntent())
    }

    private fun openAppPermissionSettings(): Boolean {
        return launchSettingsIntent(buildAppDetailsSettingsIntent(), null)
    }

    private fun canDrawOverlays(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        return Settings.canDrawOverlays(this)
    }

    private fun openOverlayPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return openAppPermissionSettings()
        }
        val overlayIntent =
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                    data = Uri.parse("package:$packageName")
                }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        return launchSettingsIntent(overlayIntent, buildAppDetailsSettingsIntent())
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return true
        }
        val manager = getSystemService(android.app.NotificationManager::class.java)
        return manager?.canUseFullScreenIntent() == true
    }

    private fun openFullScreenIntentSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return openNotificationSettings()
        }
        val manageIntent =
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        return launchSettingsIntent(manageIntent, openNotificationSettingsIntent())
    }

    private fun buildAppDetailsSettingsIntent(): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun openNotificationSettingsIntent(): Intent {
        return Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            putExtra("android.provider.extra.APP_PACKAGE", packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun launchSettingsIntent(primary: Intent, fallback: Intent?): Boolean {
        val launchedPrimary =
            runCatching {
                startActivity(primary)
            }.isSuccess
        if (launchedPrimary) {
            return true
        }
        if (fallback == null) {
            return false
        }
        return runCatching {
            startActivity(fallback)
        }.isSuccess
    }

    companion object {
        private const val widgetHostChannel = "com.smartanalog.flutter_app/widget_host"
        private const val syncWidgetPayloadMethod = "syncWidgetReadPayload"
        private const val refreshWidgetsMethod = "refreshHomeWidgets"
        private const val enableScreenSaverModeMethod = "enableScreenSaverMode"
        private const val disableScreenSaverModeMethod = "disableScreenSaverMode"
        private const val enableAutoLockScreenModeMethod = "enableAutoLockScreenMode"
        private const val disableAutoLockScreenModeMethod = "disableAutoLockScreenMode"
        private const val checkNotificationPermissionMethod = "checkNotificationPermission"
        private const val requestNotificationPermissionMethod = "requestNotificationPermission"
        private const val isNotificationPermissionRuntimeRequiredMethod =
            "isNotificationPermissionRuntimeRequired"
        private const val isIgnoringBatteryOptimizationsMethod = "isIgnoringBatteryOptimizations"
        private const val openBatteryOptimizationSettingsMethod = "openBatteryOptimizationSettings"
        private const val openNotificationSettingsMethod = "openNotificationSettings"
        private const val openAppPermissionSettingsMethod = "openAppPermissionSettings"
        private const val canDrawOverlaysMethod = "canDrawOverlays"
        private const val openOverlayPermissionSettingsMethod = "openOverlayPermissionSettings"
        private const val canUseFullScreenIntentMethod = "canUseFullScreenIntent"
        private const val openFullScreenIntentSettingsMethod = "openFullScreenIntentSettings"
        private const val consumeLaunchActionMethod = "consumeLaunchAction"
        private const val widgetReadFileName = "widget_snapshot_read_v1.json"
        private const val notificationPermissionRequestCode = 42101

        const val launchActionExtraKey = "launch_action"
        const val launchActionOpenScreenSaver = "open_screen_saver"
    }
}
