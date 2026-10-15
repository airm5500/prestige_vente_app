package com.dici.prestigepos

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * PrestigePOS 1.1.0 — démarrage de l'appareil (BOOT_COMPLETED, et QUICKBOOT_POWERON de certains terminaux) :
 * si « Démarrer automatiquement avec l'appareil » est actif, la borne est ouverte.
 * - Android 9 et moins : l'ouverture est permise.
 * - Android 10+ : Android bloque l'ouverture depuis l'arrière-plan, SAUF pour le propriétaire de l'appareil ;
 *   sinon c'est l'application d'accueil (PrestigePOS choisi « Toujours ») qui rouvre la borne. Rien ne plante si
 *   l'ouverture est refusée.
 * Pas de LOCKED_BOOT_COMPLETED : avant le premier déverrouillage, les réglages et les identifiants de la borne
 * (stockage chiffré) ne sont pas lisibles ; la borne ne pourrait pas travailler.
 */
class DemarrageReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val a = intent.action ?: return
        if (a != Intent.ACTION_BOOT_COMPLETED && a != "android.intent.action.QUICKBOOT_POWERON") return
        if (!DemarrageBridge.actif(context)) return
        try {
            DemarrageBridge.autoriserVerrouillage(context)
            val i = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            context.startActivity(i)
        } catch (e: Exception) {
            // Ouverture refusée par Android : l'application d'accueil prendra le relais.
        }
    }
}
