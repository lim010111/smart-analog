package com.smartanalog.flutter_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
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
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val widgetHostChannel = "com.smartanalog.flutter_app/widget_host"
        private const val syncWidgetPayloadMethod = "syncWidgetReadPayload"
        private const val refreshWidgetsMethod = "refreshHomeWidgets"
        private const val widgetReadFileName = "widget_snapshot_read_v1.json"
    }
}
