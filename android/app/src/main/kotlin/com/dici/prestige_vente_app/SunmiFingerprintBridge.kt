package com.dici.prestige_vente_app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.sunmi.fingerprintservice.ConnectStatusCallback
import com.sunmi.fingerprintservice.EnrollOnClientCallback
import com.sunmi.fingerprintservice.FingerprintKeywords
import com.sunmi.fingerprintservice.FingerprintOpt
import com.sunmi.fingerprintservice.IdentifyOnClientCallback
import com.sunmi.fingerprintservice.SunmiFingerprintKernel
import com.sunmi.fingerprintservice.bean.FingerprintError
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Pont Flutter <-> service d'empreinte Sunmi (com.sunmi.fingerprintservice, capteur Aratek A400).
 *
 * Les gabarits (templates) d'empreinte sont gardés par l'application (mode "OnClient") :
 * - enrollOnClient : l'employé pose son doigt, le service renvoie le gabarit ;
 * - identifyOnClient : le service compare le doigt posé aux gabarits fournis par l'application.
 * Rien n'est lancé tant que l'écran d'empreinte n'est pas ouvert : aucun effet sur le reste de l'application.
 */
class SunmiFingerprintBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHODS = "prestige/fingerprint"
        const val EVENTS = "prestige/fingerprint/events"
        private const val SERVICE_PACKAGE = "com.sunmi.fingerprintservice"
        private const val SERVICE_ACTION = "com.sunmi.fingerprint.service"
        private const val CONNECT_TIMEOUT_MS = 6000L
    }

    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var opt: FingerprintOpt? = null
    private var engaged = false

    init {
        MethodChannel(messenger, METHODS).setMethodCallHandler(this)
        EventChannel(messenger, EVENTS).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun emit(event: String) = main.post { events?.success(event) }

    /** Réponse unique garantie (les callbacks du service arrivent sur des threads binder). */
    private class Once(private val result: MethodChannel.Result, private val main: Handler) {
        private val done = AtomicBoolean(false)
        fun success(value: Any?) {
            if (done.compareAndSet(false, true)) main.post { result.success(value) }
        }
        fun error(code: String, message: String?) {
            if (done.compareAndSet(false, true)) main.post { result.error(code, message, null) }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isServiceInstalled" -> result.success(isServiceInstalled())
                "connect" -> connect(Once(result, main))
                "engage" -> engage(Once(result, main))
                "release" -> result.success(release())
                "deviceInfo" -> result.success(deviceInfo())
                "capacity" -> result.success(mapOf(
                    "capacity" to (requireOpt().deviceCapacity),
                    "enrolled" to (requireOpt().enrolledNumber),
                ))
                "enroll" -> enroll(call.argument<Int>("timeout") ?: 15, Once(result, main))
                "identify" -> identify(
                    call.argument<List<ByteArray>>("templates") ?: emptyList(),
                    call.argument<Int>("timeout") ?: 10,
                    Once(result, main),
                )
                "cancel" -> result.success(cancel())
                else -> result.notImplemented()
            }
        } catch (e: IllegalStateException) {
            result.error("NOT_CONNECTED", e.message, null)
        } catch (e: Exception) {
            result.error("ERROR", e.toString(), null)
        }
    }

    private fun isServiceInstalled(): Boolean {
        val intent = Intent(SERVICE_ACTION).setPackage(SERVICE_PACKAGE)
        return context.packageManager.queryIntentServices(intent, 0).isNotEmpty()
    }

    private fun requireOpt(): FingerprintOpt = opt ?: throw IllegalStateException("Service d'empreinte non connecté")

    private fun connect(reply: Once) {
        if (opt != null) return reply.success(true)
        if (!isServiceInstalled()) return reply.error("NO_SERVICE", "Service d'empreinte Sunmi absent de ce terminal")
        val kernel = SunmiFingerprintKernel.getInstance()
        val started = kernel.initService(context, object : SunmiFingerprintKernel.ConnectCallback {
            override fun onConnect() {
                opt = kernel.fingerprintOpt
                reply.success(opt != null)
            }

            override fun onDisconnect() {
                opt = null
                engaged = false
                emit("disconnected")
                reply.error("DISCONNECTED", "Service d'empreinte déconnecté")
            }
        })
        if (!started) return reply.error("BIND_FAILED", "Connexion au service d'empreinte impossible")
        main.postDelayed({ reply.error("TIMEOUT", "Le service d'empreinte ne répond pas") }, CONNECT_TIMEOUT_MS)
    }

    private fun engage(reply: Once) {
        if (engaged) return reply.success(true)
        val ret = requireOpt().engageFingerprint(Bundle(), object : ConnectStatusCallback.Stub() {
            override fun onConnectSuccess() {
                engaged = true
                reply.success(true)
            }

            override fun onConnectFailed() {
                engaged = false
                reply.error("ENGAGE_FAILED", "Capteur d'empreinte indisponible")
            }
        })
        when (ret) {
            0 -> main.postDelayed({ reply.error("TIMEOUT", "Le capteur ne répond pas") }, CONNECT_TIMEOUT_MS)
            FingerprintKeywords.ALREADY_ENGAGED, 3 -> reply.error("ALREADY_ENGAGED", "Capteur déjà utilisé par une autre application")
            FingerprintKeywords.API_NOT_SUPPORT, 1 -> reply.error("NOT_SUPPORTED", "Fonction non supportée par ce terminal")
            else -> reply.error("ENGAGE_FAILED", "Erreur capteur (code $ret)")
        }
    }

    private fun release(): Int {
        val o = opt ?: return 0
        engaged = false
        return o.releaseFingerprint()
    }

    private fun deviceInfo(): Map<String, Any?> {
        val b = requireOpt().fingerprintDeviceInfo ?: return emptyMap()
        return b.keySet().associateWith { k -> b.get(k)?.toString() }
    }

    private fun cancel(): Int {
        val o = opt ?: return 0
        return try {
            o.cancelEnroll(); o.cancelIdentify()
        } catch (e: Exception) {
            -2
        }
    }

    private fun reason(error: FingerprintError?) = error?.reason ?: "erreur inconnue"

    /** Enregistrement : renvoie le gabarit (byte[]) de l'empreinte posée. */
    private fun enroll(timeout: Int, reply: Once) {
        var template: ByteArray? = null
        val settings = Bundle().apply { putInt(FingerprintKeywords.TIMEOUT, timeout) }
        val ret = requireOpt().enrollFingerprintOnClient(settings, object : EnrollOnClientCallback.Stub() {
            override fun onEnrollFailed(error: FingerprintError?) = reply.error("ENROLL_FAILED", reason(error))
            override fun onEnrollTimeout() = reply.error("TIMEOUT", "Aucun doigt détecté")
            override fun onPressFingerHint() = emit("press")
            override fun onRaiseFingerHint() = emit("raise")
            override fun onEnrollFingerprint(data: Bundle?) {
                template = data?.getByteArray(FingerprintKeywords.EnrollParas.TEMPLATE)
            }

            override fun onEnrollEnd() {
                val t = template
                if (t != null) reply.success(t) else reply.error("ENROLL_FAILED", "Empreinte non enregistrée")
            }
        })
        if (ret != 0) reply.error(if (ret == FingerprintKeywords.API_NOT_SUPPORT) "NOT_SUPPORTED" else "ENROLL_FAILED", "Enregistrement impossible (code $ret)")
    }

    /**
     * Identification : le service demande les gabarits un par un (fetchDataFromClient)
     * et signale la correspondance (onIdentifyResult) pour le dernier gabarit fourni.
     * Renvoie {index, score} ; index = -1 si aucune empreinte ne correspond.
     */
    private fun identify(templates: List<ByteArray>, timeout: Int, reply: Once) {
        if (templates.isEmpty()) return reply.success(mapOf("index" to -1, "score" to 0))
        var next = 0
        var matched = -1
        var score = 0
        val settings = Bundle().apply { putInt(FingerprintKeywords.TIMEOUT, timeout) }
        val ret = requireOpt().identifyOnClient(settings, object : IdentifyOnClientCallback.Stub() {
            override fun onIdentifyFailed(error: FingerprintError?) = reply.error("IDENTIFY_FAILED", reason(error))
            override fun onIdentifyTimeout() = reply.error("TIMEOUT", "Aucun doigt détecté")
            override fun onIdentifyHintPress() = emit("press")
            override fun onIdentifyHintRaise() = emit("raise")

            override fun fetchDataFromClient(infos: Bundle?): Bundle? {
                if (next >= templates.size) return null
                return Bundle().apply { putByteArray(FingerprintKeywords.IdentifyParas.TEMPLATE, templates[next++]) }
            }

            override fun onIdentifyResult(data: Bundle?) {
                matched = next - 1
                score = data?.getInt(FingerprintKeywords.IdentifyParas.SCORE, -1) ?: -1
            }

            override fun onIdentifyEnd() {
                reply.success(mapOf("index" to matched, "score" to score))
            }
        })
        if (ret != 0) reply.error(if (ret == FingerprintKeywords.API_NOT_SUPPORT) "NOT_SUPPORTED" else "IDENTIFY_FAILED", "Identification impossible (code $ret)")
    }
}
