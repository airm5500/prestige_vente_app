package com.dici.prestigepos

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * PrestigePOS 1.1.0 — démarrage automatique de la borne avec l'appareil (canal « prestigepos/demarrage »).
 *
 * - « activer » : réglage gardé ici (lu par [DemarrageReceiver] au démarrage, avant Flutter) et alias d'activité
 *   [ALIAS_ACCUEIL] (catégorie HOME) activé ou désactivé : PrestigePOS n'est proposé comme application d'accueil
 *   que si le réglage est actif.
 * - « etat » : alias actif, PrestigePOS accueil par défaut, propriétaire de l'appareil, version d'Android.
 * - « ouvrirChoixAccueil » : écran d'Android « Application d'accueil » (repli : réglages d'Android).
 * - « retirerProprietaire » : PrestigePOS n'est plus propriétaire de l'appareil (annulation de l'étape adb).
 * - « revenirAndroid » : verrouillage arrêté, alias désactivé (le réglage est déjà désactivé côté Flutter), puis
 *   accueil d'Android ouvert : sortie fiable même si PrestigePOS était l'accueil.
 * Propre à la saveur pos : Prestige Mobile n'a ni ce canal, ni l'alias, ni le récepteur.
 */
class DemarrageBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "prestigepos/demarrage"
        const val PREFS = "prestigepos_demarrage"
        const val CLE_ACTIF = "actif"
        const val ALIAS_ACCUEIL = "com.dici.prestigepos.AccueilBorne"

        fun actif(context: Context): Boolean =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(CLE_ACTIF, false)

        fun proprietaire(context: Context): Boolean {
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            return dpm.isDeviceOwnerApp(context.packageName)
        }

        /** Propriétaire de l'appareil : PrestigePOS autorisé en tâche verrouillée (verrouillage sans confirmation). */
        fun autoriserVerrouillage(context: Context) {
            if (!proprietaire(context)) return
            val dpm = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            dpm.setLockTaskPackages(ComponentName(context, PosAdminReceiver::class.java), arrayOf(context.packageName))
        }
    }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "etat" -> result.success(etat())
                "activer" -> {
                    val actif = call.argument<Boolean>("actif") == true
                    activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(CLE_ACTIF, actif).apply()
                    alias(actif)
                    if (actif) autoriserVerrouillage(activity)
                    result.success(true)
                }
                "ouvrirChoixAccueil" -> {
                    val i = Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        activity.startActivity(i)
                    } catch (e: Exception) {
                        activity.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                    result.success(true)
                }
                "retirerProprietaire" -> {
                    if (proprietaire(activity)) retirerProprietaire()
                    result.success(!proprietaire(activity))
                }
                "revenirAndroid" -> {
                    revenirAndroid()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("DEMARRAGE", e.message, null)
        }
    }

    private fun alias(actif: Boolean) {
        activity.packageManager.setComponentEnabledSetting(
            ComponentName(activity.packageName, ALIAS_ACCUEIL),
            if (actif) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
            PackageManager.DONT_KILL_APP
        )
    }

    private fun etat(): Map<String, Any> {
        val pm = activity.packageManager
        val propose = pm.getComponentEnabledSetting(ComponentName(activity.packageName, ALIAS_ACCUEIL)) ==
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        val accueil = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val parDefaut = pm.resolveActivity(accueil, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName == activity.packageName
        return mapOf(
            "accueilPropose" to propose,
            "accueilParDefaut" to (propose && parDefaut),
            "proprietaire" to proprietaire(activity),
            "api" to Build.VERSION.SDK_INT
        )
    }

    /** Déprécié depuis Android 8 mais toujours effectif pour l'application propriétaire elle-même. */
    @Suppress("DEPRECATION")
    private fun retirerProprietaire() {
        val dpm = activity.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        dpm.clearDeviceOwnerApp(activity.packageName)
    }

    @Suppress("DEPRECATION")
    private fun enTacheVerrouillee(am: ActivityManager): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        else am.isInLockTaskMode

    private fun revenirAndroid() {
        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        if (enTacheVerrouillee(am)) {
            try {
                activity.stopLockTask()
            } catch (e: Exception) {
            }
        }
        activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(CLE_ACTIF, false).apply()
        alias(false)
        // Accueil d'Android (l'alias désactivé, ce n'est plus PrestigePOS) ; PrestigePOS passe en arrière-plan.
        val accueil = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        activity.startActivity(accueil)
        activity.moveTaskToBack(true)
    }
}
