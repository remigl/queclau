package com.remigl.reveil

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * Programme le réveil auprès d'AlarmManager et le mémorise.
 *
 * Le réveil est stocké en heure « murale » (année, mois, jour, heure, minute)
 * et converti en instant réel ici, avec le fuseau courant du téléphone. S'il
 * change de fuseau ou d'heure, [reschedule] recalcule l'instant : « 8h30 »
 * reste « 8h30 » à l'horloge du téléphone.
 */
object AlarmScheduler {

    const val ACTION_FIRE = "com.remigl.reveil.FIRE"

    enum class Result { OK, PAST, EXACT_ALARM_DENIED }

    data class WallTime(
        val year: Int,
        val month: Int,
        val day: Int,
        val hour: Int,
        val minute: Int,
    ) {
        /** Instant réel correspondant, dans le fuseau actuel du téléphone. */
        fun toEpochMillis(): Long =
            LocalDateTime.of(year, month, day, hour, minute)
                .atZone(ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli()

        fun toMap(): Map<String, Int> = mapOf(
            "year" to year,
            "month" to month,
            "day" to day,
            "hour" to hour,
            "minute" to minute,
        )
    }

    fun schedule(context: Context, time: WallTime): Result {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            !alarmManager.canScheduleExactAlarms()
        ) {
            return Result.EXACT_ALARM_DENIED
        }

        val triggerAt = time.toEpochMillis()
        if (triggerAt <= System.currentTimeMillis()) return Result.PAST

        // setAlarmClock : l'API prévue pour les réveils. Exacte, elle réveille
        // le téléphone même en mode Doze et affiche l'icône de réveil dans la
        // barre d'état.
        alarmManager.setAlarmClock(
            AlarmManager.AlarmClockInfo(triggerAt, showIntent(context)),
            fireIntent(context),
        )
        save(context, time)
        return Result.OK
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(fireIntent(context))
        clear(context)
    }

    /** Le réveil programmé, ou `null`. */
    fun current(context: Context): WallTime? {
        val p = prefs(context)
        if (!p.contains(KEY_YEAR)) return null
        return WallTime(
            p.getInt(KEY_YEAR, 0),
            p.getInt(KEY_MONTH, 1),
            p.getInt(KEY_DAY, 1),
            p.getInt(KEY_HOUR, 0),
            p.getInt(KEY_MINUTE, 0),
        )
    }

    fun clear(context: Context) {
        prefs(context).edit().clear().apply()
    }

    /**
     * Reprogramme le réveil mémorisé. AlarmManager oublie tout au redémarrage,
     * et l'instant réel doit être recalculé si l'heure ou le fuseau change.
     */
    fun reschedule(context: Context) {
        val time = current(context) ?: return
        if (schedule(context, time) == Result.PAST) clear(context)
    }

    private fun fireIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, AlarmReceiver::class.java).setAction(ACTION_FIRE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /** Ouvert quand l'utilisateur touche l'icône de réveil du système. */
    private fun showIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            1,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun save(context: Context, time: WallTime) {
        prefs(context).edit()
            .putInt(KEY_YEAR, time.year)
            .putInt(KEY_MONTH, time.month)
            .putInt(KEY_DAY, time.day)
            .putInt(KEY_HOUR, time.hour)
            .putInt(KEY_MINUTE, time.minute)
            .apply()
    }

    // Stockage « protégé par l'appareil » : lisible après un redémarrage, avant
    // même le premier déverrouillage (sinon un redémarrage nocturne ferait
    // rater le réveil).
    private fun prefs(context: Context): SharedPreferences =
        context.createDeviceProtectedStorageContext()
            .getSharedPreferences("reveil", Context.MODE_PRIVATE)

    private const val KEY_YEAR = "year"
    private const val KEY_MONTH = "month"
    private const val KEY_DAY = "day"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"
}
