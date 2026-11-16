package com.remigl.reveil

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Appelé par AlarmManager à l'heure du réveil, application ouverte ou non.
 * Démarre le service qui joue la sonnerie.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmScheduler.ACTION_FIRE) return
        AlarmScheduler.clear(context)
        // Autorisé depuis l'arrière-plan car déclenché par une alarme exacte.
        context.startForegroundService(Intent(context, AlarmRingService::class.java))
    }
}

/**
 * Reprogramme le réveil après un redémarrage, une mise à jour de
 * l'application, ou un changement d'heure / de fuseau horaire.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> AlarmScheduler.reschedule(context)
        }
    }
}
