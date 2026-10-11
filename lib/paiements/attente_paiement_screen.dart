// lib/paiements/attente_paiement_screen.dart
// B3 — Écran d'attente d'un paiement mobile money : QR du lien (montant exact fixé par le serveur),
// compte à rebours, « En attente du paiement… » (barre animée), « Paiement reçu ✓ » automatique,
// annulation tant que rien n'est payé ; paiement arrivé après l'annulation : alerte « à régulariser ».
import 'package:flutter/material.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:qr_flutter/qr_flutter.dart';

String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Contenu de l'attente (écran du comptoir et borne).
class AttentePaiementVue extends StatelessWidget {
  final AttentePaiement attente;
  final String operateur;
  final VoidCallback onAnnuler;
  final VoidCallback? onReessayer;

  /// Taille du QR (borne : plus grand).
  final double qr;
  const AttentePaiementVue({super.key, required this.attente, required this.operateur, required this.onAnnuler, this.onReessayer, this.qr = 220});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: attente,
        builder: (context, _) {
          final p = attente.paiement;
          final nom = nomOperateur[operateur] ?? operateur;
          final children = <Widget>[];
          if (p == null) {
            if (attente.erreur != null) {
              children.addAll([
                const Icon(Icons.error_outline, size: 52, color: Color(0xFFB91C1C)),
                const SizedBox(height: 8),
                Text(attente.erreur!, key: const ValueKey('pm-erreur'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Pal.ink)),
                const SizedBox(height: 12),
                if (onReessayer != null) ElevatedButton(onPressed: onReessayer, child: const Text('Réessayer')),
              ]);
            } else {
              children.addAll([const CircularProgressIndicator(), const SizedBox(height: 12), Text('Création du paiement $nom…')]);
            }
          } else {
            final montant = '${Constants.formatNumber(p.montant)} F';
            switch (p.statut) {
              case StatutPM.enAttente:
                children.addAll([
                  Text('Paiement $nom', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Pal.ink)),
                  Text('Montant exact : $montant', key: const ValueKey('pm-montant'), style: const TextStyle(fontSize: 18, color: Pal.navy, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: p.lien.isEmpty ? SizedBox(width: qr, height: qr) : QrImageView(key: const ValueKey('pm-qr'), data: p.lien, size: qr),
                  ),
                  const SizedBox(height: 6),
                  Text('Scannez avec votre application $nom', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, color: Pal.ink)),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(key: ValueKey('pm-attente-barre'), minHeight: 4),
                  const SizedBox(height: 6),
                  const Text('En attente du paiement…', key: ValueKey('pm-attente'), style: TextStyle(color: Color(0xFF7C2D12), fontWeight: FontWeight.w700)),
                  Text('Annulation automatique dans ${_mmss(attente.reste)}', key: const ValueKey('pm-rebours'), style: const TextStyle(color: Pal.muted)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('pm-annuler'),
                    onPressed: onAnnuler,
                    icon: const Icon(Icons.close),
                    label: const Text('Annuler ce paiement'),
                  ),
                ]);
              case StatutPM.paye:
                children.addAll([
                  Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(color: Color(0xFFE6F4EA), shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 52, color: Color(0xFF166534)),
                  ),
                  const SizedBox(height: 8),
                  const Text('Paiement reçu ✓', key: ValueKey('pm-recu'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF166534))),
                  Text('$montant par $nom', style: const TextStyle(fontSize: 16, color: Pal.ink)),
                ]);
              case StatutPM.payeApresAnnulation:
                children.addAll([
                  const Icon(Icons.warning_amber_rounded, size: 56, color: Color(0xFFB45309)),
                  const SizedBox(height: 8),
                  const Text('Paiement reçu APRÈS l\'annulation', key: ValueKey('pm-regulariser'), textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF7C2D12))),
                  Text('$montant par $nom : à régulariser (rembourser le client ou encaisser la vente avec ce paiement). '
                      'Ne pas encaisser une seconde fois.', textAlign: TextAlign.center, style: const TextStyle(color: Pal.ink)),
                ]);
              case StatutPM.echoue:
              case StatutPM.expire:
              case StatutPM.annule:
                children.addAll([
                  const Icon(Icons.cancel_outlined, size: 52, color: Color(0xFFB91C1C)),
                  const SizedBox(height: 8),
                  Text(
                      switch (p.statut) {
                        StatutPM.echoue => 'Paiement refusé ou échoué',
                        StatutPM.expire => 'Délai de paiement dépassé',
                        _ => 'Paiement annulé',
                      },
                      key: const ValueKey('pm-fin'),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Pal.ink)),
                  if (p.message.isNotEmpty) Text(p.message, textAlign: TextAlign.center, style: const TextStyle(color: Pal.muted)),
                ]);
            }
          }
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Column(mainAxisSize: MainAxisSize.min, children: children)),
            ),
          );
        },
      );
}

/// Écran du comptoir : renvoie le paiement PAYÉ (null sinon : annulé, expiré, échoué, fermé).
class AttentePaiementScreen extends StatefulWidget {
  final PaiementsMobileApi api;
  final String venteId;
  final String operateur;
  final int? part;
  final Duration intervalle;
  final Duration delai;
  const AttentePaiementScreen({
    super.key,
    required this.api,
    required this.venteId,
    required this.operateur,
    this.part,
    this.intervalle = const Duration(seconds: 3),
    this.delai = const Duration(minutes: 10),
  });

  static Future<PaiementMobile?> ouvrir(BuildContext context, {required String venteId, required String operateur, int? part, PaiementsMobileApi? api}) {
    final a = api ?? PaiementsMobile.instance.api;
    if (a == null) return Future.value(null);
    final exp = PaiementsMobile.instance.capacitesConnues?.expirationMin ?? 10;
    return Navigator.of(context).push<PaiementMobile>(MaterialPageRoute(
      builder: (_) => AttentePaiementScreen(api: a, venteId: venteId, operateur: operateur, part: part, delai: Duration(minutes: exp)),
    ));
  }

  @override
  State<AttentePaiementScreen> createState() => _AttentePaiementScreenState();
}

class _AttentePaiementScreenState extends State<AttentePaiementScreen> {
  late final AttentePaiement _a = AttentePaiement(widget.api, intervalle: widget.intervalle, delai: widget.delai)..addListener(_maj);
  bool _rendu = false;

  @override
  void initState() {
    super.initState();
    _demarrer();
  }

  void _demarrer() => _a.demarrer(venteId: widget.venteId, operateur: widget.operateur, part: widget.part);

  void _maj() {
    final p = _a.paiement;
    if (!mounted || p == null || _rendu) return;
    if (p.statut == StatutPM.paye) {
      _rendu = true;
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.of(context).pop(p);
      });
    }
  }

  Future<void> _annuler() async {
    if (_a.paiement == null || _a.termine) {
      Navigator.of(context).pop();
      return;
    }
    await _a.annuler();
    // Dernière vérification : un paiement déjà parti chez l'opérateur est signalé.
    await Future<void>.delayed(widget.intervalle);
    if (!mounted) return;
    await _a.verifierApresAnnulation();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _a,
      builder: (context, _) => PopScope(
        canPop: _a.paiement == null || _a.termine,
        child: Scaffold(
          backgroundColor: Pal.page,
          appBar: AppBar(
            title: const Text('Paiement mobile money'),
            backgroundColor: Pal.navy,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            actions: [
              ListenableBuilder(
                listenable: _a,
                builder: (_, __) => _a.paiement == null || _a.termine
                    ? IconButton(key: const ValueKey('pm-fermer'), tooltip: 'Fermer', icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          body: AttentePaiementVue(attente: _a, operateur: widget.operateur, onAnnuler: _annuler, onReessayer: _demarrer),
        ),
      ));
}
