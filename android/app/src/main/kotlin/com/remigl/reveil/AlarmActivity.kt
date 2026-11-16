package com.remigl.reveil

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Écran de réveil : l'heure et un gros bouton « Arrêter ».
 * S'affiche par-dessus l'écran verrouillé et allume l'écran.
 */
class AlarmActivity : Activity() {

    private var receiverRegistered = false

    private val stoppedReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Ouvert alors que plus rien ne sonne (ancienne notification, etc.).
        if (!AlarmRingService.isRinging) {
            finish()
            return
        }

        setContentView(buildContent())

        val filter = IntentFilter(AlarmRingService.ACTION_STOPPED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(stoppedReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(stoppedReceiver, filter)
        }
        receiverRegistered = true
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            unregisterReceiver(stoppedReceiver)
            receiverRegistered = false
        }
        super.onDestroy()
    }

    private fun stopAlarm() {
        startService(
            Intent(this, AlarmRingService::class.java)
                .setAction(AlarmRingService.ACTION_STOP),
        )
        finish()
    }

    private fun buildContent(): LinearLayout {
        val title = TextView(this).apply {
            text = "Réveil"
            setTextColor(Color.LTGRAY)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            gravity = Gravity.CENTER
        }
        val time = TextView(this).apply {
            text = AlarmRingService.timeLabel()
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 88f)
            gravity = Gravity.CENTER
        }
        val stop = Button(this).apply {
            text = "Arrêter"
            isAllCaps = false
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            setOnClickListener { stopAlarm() }
        }

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.BLACK)
            setPadding(dp(32), dp(32), dp(32), dp(32))
            addView(title)
            addView(
                time,
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { bottomMargin = dp(48) },
            )
            addView(
                stop,
                LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(72)),
            )
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()
}
