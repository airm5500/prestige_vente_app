package com.dici.prestigepos

import com.dici.prestige_vente_app.KiosqueBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Activité de PrestigePOS (saveur `pos`) : remplace MainActivity de Prestige Mobile dans le manifeste de la
 * saveur. Mêmes plugins Flutter (GeneratedPluginRegistrant, via super), épinglage d'écran de la borne
 * (KiosqueBridge, code partagé) et pont des imprimantes Bluetooth / USB, propre à PrestigePOS.
 * 1.1.0 : pont du démarrage automatique (DemarrageBridge).
 * Les ponts empreinte Sunmi et NFC (pointage) de Prestige Mobile ne sont pas utilisés par PrestigePOS.
 */
class PosActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        KiosqueBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        flutterEngine.plugins.add(ImprimantesPlugin())
        // 1.1.0 : démarrage automatique ; propriétaire de l'appareil → verrouillage de la borne sans confirmation.
        DemarrageBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        try {
            DemarrageBridge.autoriserVerrouillage(this)
        } catch (e: Exception) {
        }
    }
}
