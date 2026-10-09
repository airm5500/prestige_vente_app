package com.dici.prestige_vente_app

import android.app.Activity
import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Lecture des badges NFC (cartes sans contact) pour le pointage.
 *
 * Mode lecteur Android : tant que l'écran de pointage le demande, toute carte approchée est lue
 * et son identifiant (UID, en hexadécimal) est envoyé à Flutter. Aucun effet ailleurs dans l'application.
 * Le mode lecteur n'existe que lorsque l'activité est au premier plan : il est réactivé à chaque reprise.
 */
class NfcBadgeBridge(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHODS = "prestige/nfc"
        const val EVENTS = "prestige/nfc/tags"
        private val FLAGS = NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or
            NfcAdapter.FLAG_READER_NFC_F or NfcAdapter.FLAG_READER_NFC_V or
            NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK
    }

    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var wanted = false
    private var resumed = true

    private val adapter: NfcAdapter? get() = NfcAdapter.getDefaultAdapter(activity)

    init {
        MethodChannel(messenger, METHODS).setMethodCallHandler(this)
        EventChannel(messenger, EVENTS).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> {
                val a = adapter
                result.success(mapOf("supported" to (a != null), "enabled" to (a?.isEnabled == true)))
            }
            "start" -> {
                wanted = true
                result.success(enable())
            }
            "stop" -> {
                wanted = false
                disable()
                result.success(null)
            }
            "openSettings" -> {
                try {
                    activity.startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                } catch (_: Exception) {
                    activity.startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun onResume() {
        resumed = true
        if (wanted) enable()
    }

    fun onPause() {
        resumed = false
        // Android coupe le mode lecteur quand l'activité passe en arrière-plan.
        try {
            adapter?.disableReaderMode(activity)
        } catch (_: Exception) {
        }
    }

    private fun enable(): Boolean {
        val a = adapter ?: return false
        if (!a.isEnabled || !resumed) return false
        return try {
            val options = Bundle().apply { putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, 250) }
            a.enableReaderMode(activity, { tag -> onTag(tag) }, FLAGS, options)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun disable() {
        try {
            adapter?.disableReaderMode(activity)
        } catch (_: Exception) {
        }
    }

    private fun onTag(tag: Tag) {
        val id = tag.id ?: return
        if (id.isEmpty()) return
        val uid = id.joinToString("") { "%02X".format(it) }
        main.post { sink?.success(uid) }
    }
}
