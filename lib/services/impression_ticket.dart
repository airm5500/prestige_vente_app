// lib/services/impression_ticket.dart
// 4.14.0 — Impression du ticket dessiné par le serveur (lib/services/ticket_serveur.dart), avant le gabarit local.
// Appelé par ReceiptService pour les tickets de vente et de prévente (comptant, assurance, carnet), après la clôture
// ou sur « Réimprimer ». Renvoie false quand le ticket doit être composé par le gabarit local (route absente, vente
// hors ligne sans identifiant serveur, refus du serveur, réseau coupé avec une route jamais vue) : rien ne change
// alors par rapport à la 4.13.1, hormis la mise en page corrigée.
//
// Échec d'impression locale (papier, capot, Bluetooth) : le motif est affiché, la vente reste telle quelle (jamais
// annulée ni recréée), « Réimprimer » rappelle la route. Réseau coupé alors que le serveur dessine les tickets :
// « Ticket non imprimé : réseau indisponible » et « Réimprimer ».
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:provider/provider.dart';
import 'package:sunmi_printer_plus/enums.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

/// Imprime des images de ticket ; renvoie null si imprimé, sinon le motif de l'échec (affiché tel quel).
typedef ImprimeurImages = Future<String?> Function(List<TicketImage> tickets);

class ImpressionTicket {
  ImpressionTicket._();

  /// Client HTTP de la session (null : pas de serveur → gabarit local). Remplaçable dans les tests.
  static Dio? Function(BuildContext context) dioDe = _dioDe;

  /// Imprimante des images (Sunmi intégrée par défaut). Remplaçable dans les tests et par PrestigePOS.
  static ImprimeurImages imprimeur = imprimerSunmi;

  /// Diagnostic (tests) : nombre d'images envoyées à l'imprimante.
  static int imagesImprimees = 0;

  static bool _copiesParServeur = false;

  /// Une série de copies commence (imprimerCopiesAvecPause).
  static void debutCopies() => _copiesParServeur = false;

  /// Le serveur a fourni les tickets de cette vente : il décide du nombre d'exemplaires, le mobile n'ajoute pas les
  /// copies suivantes.
  static bool get copiesParServeur => _copiesParServeur;

  static Dio? _dioDe(BuildContext context) {
    try {
      return Provider.of<ApiService>(context, listen: false).dio;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void reinitialiser() {
    dioDe = _dioDe;
    imprimeur = imprimerSunmi;
    imagesImprimees = 0;
    _copiesParServeur = false;
  }

  /// Essaie le ticket du serveur. true : traité (imprimé, affiché ou échec expliqué avec « Réimprimer ») ;
  /// false : à composer avec le gabarit local.
  static Future<bool> parServeur(
    BuildContext context, {
    required TypeTicketServeur type,
    required String venteId,
    required int largeur,
    required bool apercu,
  }) async {
    if (venteId.trim().isEmpty) return false;
    final dio = dioDe(context);
    if (dio == null) return false;
    final avant = TicketServeur.etat(dio.options.baseUrl);
    if (avant == EtatRouteTicket.absente) return false;
    while (true) {
      final r = await TicketServeur.lire(dio, type: type, id: venteId, largeur: largeur);
      if (!context.mounted) return true;
      switch (r) {
        case RouteTicketAbsente():
          return false;
        case TicketRefuse():
          return false;
        case TicketReseauIndisponible():
          // Route jamais vue : ticket local (comme avant). Route déjà vue : pas de ticket recomposé.
          if (TicketServeur.etat(dio.options.baseUrl) != EtatRouteTicket.presente) return false;
          if (!await _reimprimer(context, TicketServeur.messageReseau)) return true;
        case TicketsServeur(:final tickets):
          _copiesParServeur = true;
          if (apercu) {
            await _apercu(context, tickets);
            return true;
          }
          final echec = await imprimeur(tickets);
          if (echec == null) {
            imagesImprimees += tickets.length;
            return true;
          }
          if (!context.mounted) return true;
          if (!await _reimprimer(context, 'Ticket non imprimé : $echec')) return true;
      }
      if (!context.mounted) return true;
    }
  }

  /// Motif + « Réimprimer » ; true si l'utilisateur veut réimprimer. La vente n'est jamais touchée.
  static Future<bool> _reimprimer(BuildContext context, String message) async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('ticket-non-imprime'),
        title: const Text('Ticket non imprimé'),
        content: Text('$message\n\nLa vente est enregistrée, elle n\'a pas changé.'),
        actions: [
          TextButton(
            key: const ValueKey('ticket-non-imprime-fermer'),
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Fermer'),
          ),
          ElevatedButton.icon(
            key: const ValueKey('ticket-reimprimer'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(96, 48)),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Réimprimer'),
          ),
        ],
      ),
    );
    return r == true;
  }

  /// Mode test d'impression : les images du serveur à l'écran.
  static Future<void> _apercu(BuildContext context, List<TicketImage> tickets) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          key: const ValueKey('ticket-serveur-apercu'),
          title: const Text('Aperçu du ticket (serveur)'),
          content: SizedBox(
            width: tickets.first.largeurPoints >= 576 ? 420 : 300,
            child: SingleChildScrollView(
              child: Column(children: [
                for (final t in tickets) ...[
                  Image.memory(t.png, width: double.infinity, fit: BoxFit.fitWidth, filterQuality: FilterQuality.none),
                  const Divider(),
                ],
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer'))],
        ),
      );

  /// Motif lisible d'un état d'imprimante Sunmi bloquant (null : on peut imprimer).
  static String? motifSunmi(PrinterStatus s) => switch (s) {
        PrinterStatus.OUT_OF_PAPER => 'plus de papier.',
        PrinterStatus.OPEN_THE_LID => 'capot de l\'imprimante ouvert.',
        PrinterStatus.OVERHEATED => 'imprimante trop chaude, attendez un moment.',
        PrinterStatus.NO_PRINTER_DETECTED => 'imprimante intégrée introuvable.',
        PrinterStatus.PAPER_CUTTER_ABNORMAL => 'couteau de l\'imprimante bloqué.',
        _ => null,
      };

  /// Imprimante intégrée Sunmi : chaque image telle quelle (largeur exacte du rouleau), coupe entre deux tickets.
  static Future<String?> imprimerSunmi(List<TicketImage> tickets) async {
    try {
      if (await SunmiPrinter.bindingPrinter() != true) return 'imprimante non connectée.';
      final motif = motifSunmi(await SunmiPrinter.getPrinterStatus());
      if (motif != null) return motif;
      if (await LargeurTicket.integree() == null) return 'aucune imprimante intégrée sur cet appareil.';
      await SunmiPrinter.initPrinter();
      for (var i = 0; i < tickets.length; i++) {
        await SunmiPrinter.startTransactionPrint(true);
        await SunmiPrinter.setAlignment(SunmiPrintAlign.LEFT);
        await SunmiPrinter.printImage(tickets[i].png);
        await SunmiPrinter.lineWrap(3);
        await SunmiPrinter.cut();
        await SunmiPrinter.exitTransactionPrint(true);
      }
      return null;
    } catch (e) {
      return 'erreur de l\'imprimante ($e).';
    }
  }
}
