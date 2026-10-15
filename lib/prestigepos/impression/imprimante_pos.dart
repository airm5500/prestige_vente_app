// lib/prestigepos/impression/imprimante_pos.dart
// PrestigePOS — imprimante du ticket de la borne : Sunmi intégrée (code existant de la borne, rien à configurer)
// ou imprimante ESC/POS externe (Bluetooth, USB, réseau). En cas d'échec, la borne affiche le ticket à l'écran
// avec la cause en clair (BorneImprimanteDiagnostic).
import 'dart:async';
import 'dart:typed_data';

import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/borne/borne_service.dart';
import 'package:prestige_vente_app/borne/borne_ticket.dart';
import 'package:prestige_vente_app/prestigepos/impression/imprimante_reglages.dart';
import 'package:prestige_vente_app/prestigepos/impression/ticket_escpos.dart';
import 'package:prestige_vente_app/prestigepos/impression/transports.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

/// Détection de l'imprimante intégrée Sunmi (remplaçable dans les tests).
typedef DetecteurSunmi = Future<bool> Function();

Future<bool> detecterSunmi() async {
  try {
    return await SunmiPrinter.bindingPrinter().timeout(const Duration(seconds: 3)) == true;
  } catch (_) {
    return false;
  }
}

class ImprimantePos implements BorneImprimante, BorneImprimanteDiagnostic {
  /// Réglages lus à chaque impression (un changement dans l'administration s'applique au ticket suivant).
  final ImprimanteConfig Function() config;
  final DetecteurSunmi sunmi;

  /// Impression Sunmi (code de la borne) ; remplaçable dans les tests.
  final BorneImprimante imprimanteSunmi;

  /// Transport d'une imprimante externe ; remplaçable dans les tests.
  final TransportImpression? Function(ImprimanteConfig c)? transport;

  ImprimantePos({
    ImprimanteConfig Function()? config,
    DetecteurSunmi? sunmi,
    BorneImprimante? imprimanteSunmi,
    this.transport,
  })  : config = config ?? (() => ImprimanteReglages.courant.value),
        sunmi = sunmi ?? detecterSunmi,
        imprimanteSunmi = imprimanteSunmi ?? const SunmiBorneImprimante();

  bool? _sunmiPresent;
  String? _echec;

  @override
  String? get dernierEchec => _echec;

  /// Sunmi intégrée détectée (mémorisé après la première détection).
  Future<bool> sunmiPresent() async => _sunmiPresent ??= await sunmi();

  /// Transport de l'imprimante externe configurée (null : configuration incomplète).
  static TransportImpression? transportPour(ImprimanteConfig c) {
    switch (c.type) {
      case TypeImprimante.bluetooth:
        final a = c.bluetooth;
        return a == null ? null : TransportBluetooth(a.adresse);
      case TypeImprimante.usb:
        final ids = c.usb?.usbIds;
        return ids == null ? null : TransportUsb(ids.$1, ids.$2);
      case TypeImprimante.reseau:
        return c.hote.isEmpty ? null : TransportReseau(c.hote, port: c.port);
      default:
        return null;
    }
  }

  /// Envoie [octets] à l'imprimante externe de [c] ; message clair si échec.
  Future<bool> _envoyer(ImprimanteConfig c, Uint8List octets) async {
    final t = (transport ?? transportPour)(c);
    if (t == null) {
      _echec = 'imprimante ${c.type.label} non choisie (Administration › Imprimante).';
      return false;
    }
    try {
      await t.envoyer(octets).timeout(const Duration(seconds: 25));
      _echec = null;
      return true;
    } on EchecImpression catch (e) {
      _echec = e.message;
    } on TimeoutException {
      _echec = 'l\'imprimante ne répond pas (délai dépassé).';
    } catch (e) {
      _echec = 'erreur d\'impression ($e).';
    }
    return false;
  }

  @override
  Future<bool> imprimer(BorneTicket ticket) async {
    final c = config();
    _echec = null;
    switch (c.type) {
      case TypeImprimante.aucune:
        return false;
      case TypeImprimante.automatique:
      case TypeImprimante.sunmi:
        if (!await sunmiPresent()) {
          // Pas de Sunmi : ticket à l'écran (message seulement si la Sunmi était explicitement choisie).
          if (c.type == TypeImprimante.sunmi) _echec = 'imprimante intégrée Sunmi introuvable sur cet appareil.';
          return false;
        }
        final ok = await imprimanteSunmi.imprimer(ticket);
        if (!ok) _echec = 'imprimante Sunmi indisponible (papier, capot ouvert ?).';
        return ok;
      default:
        return _envoyer(c, TicketEscPos.ticket(ticket, c));
    }
  }

  /// « Test d'impression » : message clair (null si imprimé).
  Future<String?> tester({String officine = ''}) async {
    final c = config();
    switch (c.type) {
      case TypeImprimante.aucune:
        return 'Aucune imprimante choisie : le ticket est affiché à l\'écran.';
      case TypeImprimante.automatique:
      case TypeImprimante.sunmi:
        _sunmiPresent = null;
        if (!await sunmiPresent()) {
          return c.type == TypeImprimante.sunmi
              ? 'Imprimante intégrée Sunmi introuvable sur cet appareil.'
              : 'Aucune imprimante intégrée Sunmi détectée : choisissez une imprimante Bluetooth, USB ou réseau.';
        }
        final ok = await imprimanteSunmi.imprimer(ticketEssai(officine: officine, largeur: c.papier));
        return ok ? null : 'Imprimante Sunmi indisponible (papier, capot ouvert ?).';
      default:
        final ok = await _envoyer(c, TicketEscPos.essai(c, officine: officine));
        return ok ? null : 'Test non imprimé : $_echec';
    }
  }

  /// Ticket fictif du test (Sunmi).
  static BorneTicket ticketEssai({String officine = '', int largeur = 58}) => BorneTicket(
        officine: officine.isEmpty ? 'PRESTIGEPOS' : officine,
        largeur: largeur,
        prevente: BornePrevente(
          venteId: 'TEST',
          reference: 'TEST-PRESTIGEPOS',
          total: 0,
          lignes: [
            SaleItemDetail(
                lgPREENREGISTREMENTDETAILID: '', lgFAMILLEID: '', strNAME: 'TEST D\'IMPRESSION', intCIP: '', intQUANTITY: 1, intPRICEUNITAIR: 0, intPRICE: 0, strREF: ''),
          ],
          at: DateTime.now(),
        ),
      );
}
