package com.dici.prestige_vente_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var nfc: NfcBadgeBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Empreinte Sunmi (pointage) : canal inactif tant que l'écran d'empreinte n'est pas utilisé.
        // Contexte de l'activité : nécessaire pour afficher la confirmation d'empreinte Android.
        SunmiFingerprintBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // Badges NFC (pointage) : lecteur actif seulement quand l'écran de pointage le demande.
        nfc = NfcBadgeBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // Borne libre-service (B1) : épinglage d'écran, seulement quand la borne le demande.
        KiosqueBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        // 4.10.0 : bouton « Pointer » → application Prestige Pointage (com.dici.prestigepointage) si elle est installée.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "prestige/pointage").setMethodCallHandler { call, result ->
            val paquet = call.argument<String>("paquet")
            if (paquet != "com.dici.prestigepointage") {
                result.success(false)
                return@setMethodCallHandler
            }
            val intention = packageManager.getLaunchIntentForPackage(paquet)
            when (call.method) {
                "estInstallee" -> result.success(intention != null)
                "ouvrir" -> {
                    if (intention == null) {
                        result.success(false)
                    } else {
                        intention.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        try {
                            startActivity(intention)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        nfc?.onResume()
    }

    override fun onPause() {
        nfc?.onPause()
        super.onPause()
    }
}
