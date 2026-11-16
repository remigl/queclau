package com.remigl.reveil

import android.content.Intent
import android.provider.AlarmClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Activité Flutter. Expose au code Dart deux canaux :
 *  - « reveil/alarm » : règle une alarme dans l'Horloge du téléphone ;
 *  - « reveil/model » : prépare le fichier du modèle de langage local.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL)
            .setMethodCallHandler(::onAlarmCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MODEL_CHANNEL)
            .setMethodCallHandler(::onModelCall)
    }

    private fun onAlarmCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "setAlarm") {
            result.notImplemented()
            return
        }
        val hour = call.argument<Int>("hour")
        val minute = call.argument<Int>("minute")
        if (hour == null || minute == null || hour !in 0..23 || minute !in 0..59) {
            result.error("bad_args", "Heure invalide.", null)
            return
        }

        // Intent standard d'Android : l'application Horloge crée l'alarme.
        // EXTRA_SKIP_UI lui demande de le faire sans ouvrir son écran.
        // Elle choisit le jour elle-même : la prochaine occurrence de l'heure.
        val intent = Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, hour)
            .putExtra(AlarmClock.EXTRA_MINUTES, minute)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
        try {
            startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            // Aucune application Horloge, ou demande refusée.
            result.error("no_clock", e.message, null)
        }
    }

    private fun onModelCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "prepare") {
            result.notImplemented()
            return
        }
        val context = applicationContext
        // La première copie du modèle est longue : hors du thread principal.
        Thread {
            val path = try {
                ModelFiles.prepare(context)
            } catch (_: Exception) {
                null
            }
            runOnUiThread { result.success(path) }
        }.start()
    }

    private companion object {
        const val ALARM_CHANNEL = "reveil/alarm"
        const val MODEL_CHANNEL = "reveil/model"
    }
}
