package com.dici.prestige_vente_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Empreinte Sunmi (pointage) : canal inactif tant que l'écran d'empreinte n'est pas utilisé.
        // Contexte de l'activité : nécessaire pour afficher la confirmation d'empreinte Android.
        SunmiFingerprintBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
