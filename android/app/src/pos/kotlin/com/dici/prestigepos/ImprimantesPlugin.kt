package com.dici.prestigepos

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.PendingIntent
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.IOException
import java.util.UUID

/**
 * PrestigePOS — pont des imprimantes de ticket ESC/POS (canal « prestigepos/imprimantes ») :
 *  - Bluetooth classique, profil série SPP : appareils appairés, découverte, envoi des octets ;
 *  - USB (câble OTG) : périphériques branchés, autorisation Android, envoi en « bulk ».
 * Les octets ESC/POS sont fabriqués en Dart (lib/prestigepos/impression/escpos.dart). Toutes les opérations
 * lentes tournent hors du fil principal ; le résultat revient sur le fil principal.
 * Codes d'erreur (traduits en clair côté Dart) : PERMISSION, BT_ABSENT, BT_INACTIF, LOCALISATION, CONNEXION,
 * USB_ABSENT, USB_REFUS, USB_INTERFACE, ENVOI.
 * Les autorisations sont vérifiées avant chaque appel Bluetooth (accordee / connexionAutorisee), d'où la
 * suppression de l'avertissement MissingPermission de lint.
 */
@SuppressLint("MissingPermission", "UnspecifiedRegisterReceiverFlag")
class ImprimantesPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val CANAL = "prestigepos/imprimantes"
        private val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val CODE_AUTORISATIONS = 47110
        private const val ACTION_USB = "com.dici.prestigepos.USB_AUTORISATION"
    }

    private var canal: MethodChannel? = null
    private var contexte: Context? = null
    private var activite: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private val principal = Handler(Looper.getMainLooper())
    private var attenteAutorisations: MethodChannel.Result? = null

    // --- Cycle de vie -------------------------------------------------------------------------

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        contexte = b.applicationContext
        canal = MethodChannel(b.binaryMessenger, CANAL).also { it.setMethodCallHandler(this) }
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        canal?.setMethodCallHandler(null)
        canal = null
        contexte = null
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) {
        activite = b.activity
        binding = b
        b.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = onAttachedToActivity(b)

    override fun onDetachedFromActivity() {
        binding?.removeRequestPermissionsResultListener(this)
        binding = null
        activite = null
    }

    // --- Appels -------------------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "autorisations" -> autorisations(result)
                "bluetoothActiver" -> {
                    val a = activite
                    if (a != null) a.startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE))
                    result.success(true)
                }
                "bluetoothAppaires" -> result.success(appaires())
                "bluetoothRechercher" -> rechercher((call.argument<Int>("duree") ?: 12000).toLong(), result)
                "bluetoothEnvoyer" -> {
                    val adresse = call.argument<String>("adresse") ?: ""
                    val octets = call.argument<ByteArray>("octets") ?: ByteArray(0)
                    enArrierePlan(result) { envoyerBluetooth(adresse, octets); true }
                }
                "usbListe" -> result.success(usbListe())
                "usbEnvoyer" -> {
                    val vid = call.argument<Int>("vendorId") ?: -1
                    val pid = call.argument<Int>("productId") ?: -1
                    val octets = call.argument<ByteArray>("octets") ?: ByteArray(0)
                    envoyerUsb(vid, pid, octets, result)
                }
                else -> result.notImplemented()
            }
        } catch (e: ErreurImprimante) {
            result.error(e.code, e.message, null)
        } catch (e: SecurityException) {
            result.error("PERMISSION", e.message, null)
        } catch (e: Exception) {
            result.error("ENVOI", e.message, null)
        }
    }

    private class ErreurImprimante(val code: String, message: String) : Exception(message)

    private fun enArrierePlan(result: MethodChannel.Result, travail: () -> Any?) {
        Thread {
            try {
                val r = travail()
                principal.post { result.success(r) }
            } catch (e: ErreurImprimante) {
                principal.post { result.error(e.code, e.message, null) }
            } catch (e: SecurityException) {
                principal.post { result.error("PERMISSION", e.message, null) }
            } catch (e: Exception) {
                principal.post { result.error("ENVOI", e.message, null) }
            }
        }.start()
    }

    // --- Autorisations -------------------------------------------------------------------------

    private fun permissionsNecessaires(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    private fun accordee(p: String): Boolean {
        val c = contexte ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return c.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
    }

    private fun autorisations(result: MethodChannel.Result) {
        val manquantes = permissionsNecessaires().filter { !accordee(it) }
        if (manquantes.isEmpty()) {
            result.success(true)
            return
        }
        val a = activite
        if (a == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(false)
            return
        }
        attenteAutorisations?.success(false)
        attenteAutorisations = result
        a.requestPermissions(manquantes.toTypedArray(), CODE_AUTORISATIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != CODE_AUTORISATIONS) return false
        val r = attenteAutorisations ?: return true
        attenteAutorisations = null
        r.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
        return true
    }

    // --- Bluetooth ------------------------------------------------------------------------------

    private fun adaptateur(): BluetoothAdapter {
        val c = contexte ?: throw ErreurImprimante("BT_ABSENT", "Bluetooth indisponible")
        val m = c.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val a = m?.adapter ?: throw ErreurImprimante("BT_ABSENT", "Pas de Bluetooth")
        if (!a.isEnabled) throw ErreurImprimante("BT_INACTIF", "Bluetooth désactivé")
        return a
    }

    private fun connexionAutorisee() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !accordee(Manifest.permission.BLUETOOTH_CONNECT)) {
            throw ErreurImprimante("PERMISSION", "BLUETOOTH_CONNECT refusée")
        }
    }

    private fun decrire(d: BluetoothDevice, appaire: Boolean): Map<String, Any?> {
        val classe: BluetoothClass? = try { d.bluetoothClass } catch (ignoree: SecurityException) { null }
        val imprimante = classe != null &&
            (classe.majorDeviceClass == BluetoothClass.Device.Major.IMAGING ||
                classe.hasService(BluetoothClass.Service.RENDER))
        val nom = try { d.name } catch (ignoree: SecurityException) { null }
        return mapOf("nom" to (nom ?: ""), "adresse" to d.address, "appaire" to appaire, "imprimante" to imprimante)
    }

    private fun appaires(): List<Map<String, Any?>> {
        connexionAutorisee()
        return adaptateur().bondedDevices.map { decrire(it, true) }
    }

    private fun rechercher(duree: Long, result: MethodChannel.Result) {
        val c = contexte ?: throw ErreurImprimante("BT_ABSENT", "Bluetooth indisponible")
        val a = adaptateur()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!accordee(Manifest.permission.BLUETOOTH_SCAN) || !accordee(Manifest.permission.BLUETOOTH_CONNECT)) {
                throw ErreurImprimante("PERMISSION", "BLUETOOTH_SCAN refusée")
            }
        } else {
            if (!accordee(Manifest.permission.ACCESS_FINE_LOCATION)) throw ErreurImprimante("PERMISSION", "Localisation refusée")
            val lm = c.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            val actif = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) lm?.isLocationEnabled == true
            else lm?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true || lm?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
            if (!actif) throw ErreurImprimante("LOCALISATION", "Localisation désactivée")
        }
        val trouves = LinkedHashMap<String, Map<String, Any?>>()
        for (d in a.bondedDevices) trouves[d.address] = decrire(d, true)
        var fini = false
        lateinit var recepteur: BroadcastReceiver
        fun terminer() {
            if (fini) return
            fini = true
            try { c.unregisterReceiver(recepteur) } catch (ignoree: Exception) {}
            try { a.cancelDiscovery() } catch (ignoree: Exception) {}
            result.success(ArrayList(trouves.values))
        }
        recepteur = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val d: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                        }
                        if (d != null && !trouves.containsKey(d.address)) {
                            trouves[d.address] = decrire(d, d.bondState == BluetoothDevice.BOND_BONDED)
                        }
                    }
                    BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> terminer()
                }
            }
        }
        val filtre = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            c.registerReceiver(recepteur, filtre, Context.RECEIVER_EXPORTED)
        } else {
            c.registerReceiver(recepteur, filtre)
        }
        if (a.isDiscovering) a.cancelDiscovery()
        if (!a.startDiscovery()) {
            terminer()
            return
        }
        principal.postDelayed({ terminer() }, duree)
    }

    private fun envoyerBluetooth(adresse: String, octets: ByteArray) {
        connexionAutorisee()
        val a = adaptateur()
        if (!BluetoothAdapter.checkBluetoothAddress(adresse)) throw ErreurImprimante("CONNEXION", "Adresse invalide")
        try { a.cancelDiscovery() } catch (ignoree: SecurityException) {}
        val d = a.getRemoteDevice(adresse)
        val socket = connecter(d) ?: throw ErreurImprimante("CONNEXION", "Connexion impossible")
        try {
            val sortie = socket.outputStream
            var i = 0
            while (i < octets.size) {
                val n = minOf(1024, octets.size - i)
                sortie.write(octets, i, n)
                sortie.flush()
                i += n
            }
            // Laisse l'imprimante vider son tampon avant de fermer (certaines coupent le ticket sinon).
            Thread.sleep(minOf(3000L, 400L + octets.size / 8L))
        } catch (e: IOException) {
            throw ErreurImprimante("CONNEXION", e.message ?: "Envoi interrompu")
        } finally {
            try { socket.close() } catch (ignoree: IOException) {}
        }
    }

    /** Connexion SPP : sécurisée, puis non sécurisée, puis canal 1 (imprimantes anciennes). */
    private fun connecter(d: BluetoothDevice): BluetoothSocket? {
        val essais = listOf<() -> BluetoothSocket>(
            { d.createRfcommSocketToServiceRecord(SPP) },
            { d.createInsecureRfcommSocketToServiceRecord(SPP) },
            { d.javaClass.getMethod("createRfcommSocket", Integer.TYPE).invoke(d, 1) as BluetoothSocket },
        )
        for (creer in essais) {
            var s: BluetoothSocket? = null
            try {
                s = creer()
                s.connect()
                return s
            } catch (e: SecurityException) {
                throw e
            } catch (ignoree: Exception) {
                try { s?.close() } catch (ignoree: Exception) {}
            }
        }
        return null
    }

    // --- USB -------------------------------------------------------------------------------------------

    private fun usb(): UsbManager =
        (contexte?.getSystemService(Context.USB_SERVICE) as? UsbManager) ?: throw ErreurImprimante("USB_ABSENT", "USB indisponible")

    private fun interfaceImprimante(d: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        var repli: Pair<UsbInterface, UsbEndpoint>? = null
        for (i in 0 until d.interfaceCount) {
            val itf = d.getInterface(i)
            for (e in 0 until itf.endpointCount) {
                val ep = itf.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) {
                    if (itf.interfaceClass == UsbConstants.USB_CLASS_PRINTER) return Pair(itf, ep)
                    if (repli == null) repli = Pair(itf, ep)
                }
            }
        }
        return repli
    }

    private fun usbListe(): List<Map<String, Any?>> = usb().deviceList.values.map { d ->
        val nom = listOfNotNull(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) d.manufacturerName else null,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) d.productName else null,
        ).joinToString(" ").ifBlank { "USB ${d.vendorId}:${d.productId}" }
        val imprimante = (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_PRINTER }
        mapOf("nom" to nom, "adresse" to "${d.vendorId}:${d.productId}", "appaire" to false, "imprimante" to imprimante)
    }

    private fun envoyerUsb(vid: Int, pid: Int, octets: ByteArray, result: MethodChannel.Result) {
        val m = usb()
        val d = m.deviceList.values.firstOrNull { it.vendorId == vid && it.productId == pid }
            ?: throw ErreurImprimante("USB_ABSENT", "Imprimante USB non branchée")
        if (m.hasPermission(d)) {
            enArrierePlan(result) { ecrireUsb(m, d, octets); true }
            return
        }
        val c = contexte ?: throw ErreurImprimante("USB_ABSENT", "USB indisponible")
        val recepteur = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != ACTION_USB) return
                try { c.unregisterReceiver(this) } catch (ignoree: Exception) {}
                if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                    enArrierePlan(result) { ecrireUsb(m, d, octets); true }
                } else {
                    result.error("USB_REFUS", "Autorisation USB refusée", null)
                }
            }
        }
        if (Build.VERSION.SDK_INT >= 33) {
            c.registerReceiver(recepteur, IntentFilter(ACTION_USB), Context.RECEIVER_NOT_EXPORTED)
        } else {
            c.registerReceiver(recepteur, IntentFilter(ACTION_USB))
        }
        val drapeaux = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val pi = PendingIntent.getBroadcast(c, 0, Intent(ACTION_USB).setPackage(c.packageName), drapeaux)
        m.requestPermission(d, pi)
    }

    private fun ecrireUsb(m: UsbManager, d: UsbDevice, octets: ByteArray) {
        val (itf, ep) = interfaceImprimante(d) ?: throw ErreurImprimante("USB_INTERFACE", "Pas d'interface d'impression")
        val cx = m.openDevice(d) ?: throw ErreurImprimante("USB_REFUS", "Ouverture impossible")
        try {
            if (!cx.claimInterface(itf, true)) throw ErreurImprimante("USB_REFUS", "Interface occupée")
            var i = 0
            while (i < octets.size) {
                val n = minOf(4096, octets.size - i)
                val envoye = cx.bulkTransfer(ep, octets, i, n, 5000)
                if (envoye < 0) throw ErreurImprimante("ENVOI", "Transfert USB interrompu")
                i += envoye
            }
            cx.releaseInterface(itf)
        } finally {
            cx.close()
        }
    }
}
