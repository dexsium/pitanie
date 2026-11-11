package com.pitanie.pitanie_widgets

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Мост между приложением и виджетами главного экрана.
 * Данные передаются готовым JSON-снимком дня и хранятся локально в SharedPreferences,
 * в сеть ничего не отправляется. Нажатия на виджет открывают приложение с командой
 * (pitanie://widget/<команда>), которую плагин передаёт в Dart.
 */
class PitanieWidgetsPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var binding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pitanie_widgets")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "update" -> {
                val json = call.argument<String>("json")
                if (json == null) {
                    result.error("bad_args", "json is required", null)
                } else {
                    WidgetStore.save(context, json)
                    WidgetRenderer.updateAll(context)
                    result.success(true)
                }
            }
            "initialAction" -> {
                val act = binding?.activity
                result.success(act?.intent?.let { takeAction(it) })
            }
            "isSupported" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    /** Команда из адреса pitanie://widget/<команда>; после чтения адрес стирается. */
    private fun takeAction(intent: Intent): String? {
        val data = intent.data ?: return null
        if (data.scheme != "pitanie" || data.host != "widget") return null
        val action = data.lastPathSegment
        intent.data = null
        return action
    }

    override fun onNewIntent(intent: Intent): Boolean {
        val action = takeAction(intent) ?: return false
        channel.invokeMethod("onAction", action)
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        binding?.removeOnNewIntentListener(this)
        binding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        binding?.removeOnNewIntentListener(this)
        binding = null
    }
}
