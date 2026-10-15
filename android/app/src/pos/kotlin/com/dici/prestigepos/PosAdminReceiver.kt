package com.dici.prestigepos

import android.app.admin.DeviceAdminReceiver

/**
 * PrestigePOS 1.1.0 — administrateur de l'appareil, utilisé seulement si l'installateur rend PrestigePOS
 * « propriétaire de l'appareil » (adb shell dpm set-device-owner com.dici.prestigepos/.PosAdminReceiver) :
 * verrouillage de la borne sans confirmation (lock task autorisé). Aucune politique demandée (aucun effacement,
 * aucun mot de passe imposé). Annulation : docs/prestigepos/README.md › « Démarrage automatique ».
 */
class PosAdminReceiver : DeviceAdminReceiver()
