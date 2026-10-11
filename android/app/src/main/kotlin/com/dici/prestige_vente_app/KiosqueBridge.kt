package com.dici.prestige_vente_app

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Mode kiosque de la borne libre-service (B1) : épinglage d'écran Android (lock task).
 *
 * - Sans « Device Owner » : startLockTask() active l'ÉPINGLAGE STANDARD, Android demande une
 *   confirmation à l'écran (« Épingler l'application ? ») ; la sortie système reste possible par
 *   l'appui long Retour + Aperçu (selon le modèle), à protéger par le code de l'appareil
 *   (Paramètres › Sécurité › Épinglage d'écran › « Demander le code avant de désépingler »).
 * - Avec l'appli « Device Owner » (dpm set-device-owner) et le paquet autorisé
 *   (setLockTaskPackages) : verrouillage complet sans confirmation.
 * Canal inactif tant que la borne n'est pas ouverte : aucun effet sur le reste de l'application.
 */
class KiosqueBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "prestige/kiosque"
    }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "demarrer" -> {
                    activity.startLockTask()
                    result.success(etat())
                }
                "arreter" -> {
                    if (etat() != "aucun") activity.stopLockTask()
                    result.success(true)
                }
                "etat" -> result.success(etat())
                "proprietaire" -> {
                    val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    result.success(dpm.isDeviceOwnerApp(activity.packageName))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("KIOSQUE", e.message, null)
        }
    }

    /** « aucun », « epingle » (épinglage standard) ou « verrouille » (Device Owner). */
    private fun etat(): String {
        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val s = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.lockTaskModeState
        } else {
            @Suppress("DEPRECATION")
            if (am.isInLockTaskMode) ActivityManager.LOCK_TASK_MODE_PINNED else ActivityManager.LOCK_TASK_MODE_NONE
        }
        return when (s) {
            ActivityManager.LOCK_TASK_MODE_LOCKED -> "verrouille"
            ActivityManager.LOCK_TASK_MODE_PINNED -> "epingle"
            else -> "aucun"
        }
    }
}
