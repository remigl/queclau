package com.remigl.reveil

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Activité Flutter. Expose au code Dart (lib/services/alarm_service.dart) le
 * canal « reveil/alarm » qui pilote [AlarmScheduler].
 */
class MainActivity : FlutterActivity() {

    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::onMethodCall)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MODEL_CHANNEL)
            .setMethodCallHandler(::onModelCall)
    }

    override fun onResume() {
        super.onResume()
        // Si le réveil sonne (par exemple notifications refusées, donc pas
        // d'écran de réveil automatique), ouvrir l'appli permet de l'arrêter.
        if (AlarmRingService.isRinging) {
            startActivity(Intent(this, AlarmActivity::class.java))
        }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "schedule" -> schedule(call, result)
            "cancel" -> {
                AlarmScheduler.cancel(this)
                result.success(null)
            }
            "getAlarm" -> result.success(AlarmScheduler.current(this)?.toMap())
            "openExactAlarmSettings" -> {
                openExactAlarmSettings()
                result.success(null)
            }
            "requestNotificationPermission" -> requestNotificationPermission(result)
            else -> result.notImplemented()
        }
    }

    /** Canal « reveil/model » : prépare le fichier du modèle de langage. */
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

    private fun schedule(call: MethodCall, result: MethodChannel.Result) {
        val year = call.argument<Int>("year")
        val month = call.argument<Int>("month")
        val day = call.argument<Int>("day")
        val hour = call.argument<Int>("hour")
        val minute = call.argument<Int>("minute")
        if (year == null || month == null || day == null || hour == null || minute == null) {
            result.error("bad_args", "Date ou heure manquante.", null)
            return
        }

        val outcome = try {
            AlarmScheduler.schedule(
                this,
                AlarmScheduler.WallTime(year, month, day, hour, minute),
            )
        } catch (e: Exception) {
            result.error("failed", e.message, null)
            return
        }

        when (outcome) {
            AlarmScheduler.Result.OK -> result.success(null)
            AlarmScheduler.Result.PAST ->
                result.error("past", "Cette heure est déjà passée.", null)
            AlarmScheduler.Result.EXACT_ALARM_DENIED ->
                result.error("exact_alarm_denied", "Alarmes exactes non autorisées.", null)
        }
    }

    /** Android 12 / 12L : écran système « Alarmes et rappels ». */
    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                    Uri.parse("package:$packageName"),
                ),
            )
        } catch (_: Exception) {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ),
            )
        }
    }

    /** Android 13+ : l'affichage de notifications se demande à l'exécution. */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotificationResult != null) {
            result.success(false)
            return
        }
        pendingNotificationResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_NOTIFICATIONS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingNotificationResult?.success(granted)
        pendingNotificationResult = null
    }

    private companion object {
        const val CHANNEL = "reveil/alarm"
        const val MODEL_CHANNEL = "reveil/model"
        const val REQUEST_NOTIFICATIONS = 4711
    }
}
