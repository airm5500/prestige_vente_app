// lib/horsligne/horsligne_ui.dart
// Bandeau global du hors ligne (placé par MaterialApp.builder, au-dessus de tous les écrans) :
// - serveur injoignable → « Serveur injoignable depuis HH:MM » + [Continuer hors ligne] ;
// - hors ligne → « Hors ligne — catalogue du … » ;
// - retour en ligne → « Serveur de nouveau joignable » quelques secondes.
// - ventes hors ligne (H2) : « · N vente(s) en attente », « Envoi 2/5… » pendant l'envoi,
//   « N vente(s) hors ligne à vérifier » ; « Voir » ouvre l'écran « Ventes hors ligne ».
// En ligne sans vente hors ligne : rien n'est affiché et l'écran est inchangé.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/horsligne/horsligne.dart';
import 'package:prestige_vente_app/horsligne/server_monitor.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_horsligne.dart';
import 'package:prestige_vente_app/horsligne/stock/stock_ui.dart';
import 'package:prestige_vente_app/horsligne/ventes_hors_ligne_screen.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:provider/provider.dart';

enum BandeauHorsLigne { injoignable, horsLigne, retour, envoi, enAttente, aVerifier }

class HorsLigneScope extends StatefulWidget {
  final Widget child;

  /// Instance utilisée (tests) ; sinon [HorsLigne.instance].
  final HorsLigne? horsLigne;

  /// Relier à l'ApiService / AuthProvider de l'appli (surveillance, synchro).
  final bool bindApp;

  /// Durée du message « Serveur de nouveau joignable ».
  final Duration retourDuree;

  /// Bandeau « Serveur de nouveau joignable » (false : annoncé par ConnexionToasts).
  final bool bandeauRetour;
  const HorsLigneScope(
      {super.key, required this.child, this.horsLigne, this.bindApp = true, this.retourDuree = const Duration(seconds: 4), this.bandeauRetour = true});

  @override
  State<HorsLigneScope> createState() => _HorsLigneScopeState();
}

class _HorsLigneScopeState extends State<HorsLigneScope> {
  HorsLigne get _hl => widget.horsLigne ?? HorsLigne.instance;
  late final HorsLigne _bound = _hl;
  late final StockHorsLigne _stock = StockHorsLigne.instance;
  bool _retour = false;
  DateTime? _retourVu;
  Timer? _retourTimer;
  bool _connecte = false;

  @override
  void initState() {
    super.initState();
    _bound.monitor.addListener(_onMonitor);
    _bound.sync.addListener(_onChange);
    _bound.ventesEnAttente.addListener(_onChange);
    _stock.attach(_bound);
    _stock.queue.addListener(_onChange); // stock hors ligne (H3)
    _bound.ventes.addListener(_onChange);
    if (widget.bindApp) _bound.monitor.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.bindApp) return;
    final api = Provider.of<ApiService?>(context);
    if (api != null) {
      _bound.bind(api);
      _stock.bind(api);
    }
    final connecte = Provider.of<AuthProvider?>(context)?.user != null;
    if (connecte == _connecte) return;
    _connecte = connecte;
    if (connecte) {
      // Après la connexion : copie mise à jour si elle a plus de 12 h, puis toutes les 30 min.
      _bound.sync.syncIfStale();
      _bound.sync.startAuto(() => _bound.monitor.etat == EtatServeur.enLigne);
      // Ventes hors ligne restées en attente (appli fermée pendant l'envoi) : reprise.
      _bound.demarrerVentes();
    } else {
      _bound.sync.stopAuto();
    }
  }

  @override
  void dispose() {
    _retourTimer?.cancel();
    _bound.monitor.removeListener(_onMonitor);
    _bound.sync.removeListener(_onChange);
    _bound.ventesEnAttente.removeListener(_onChange);
    _stock.queue.removeListener(_onChange);
    _bound.ventes.removeListener(_onChange);
    if (widget.bindApp) {
      _bound.monitor.stop();
      _bound.sync.stopAuto();
    }
    super.dispose();
  }

  bool _confirmationOuverte = false;

  void _onChange() {
    if (mounted) setState(() {});
    // Retour du serveur avec des ventes en attente : confirmation (aucun envoi sans accord).
    if (_bound.ventes.confirmationDemandee && !_confirmationOuverte && HorsLigne.navigatorKey.currentState != null) {
      _confirmationOuverte = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await confirmerEnvoiGlobal(_bound);
        } finally {
          _confirmationOuverte = false;
        }
        // Puis les opérations de stock en attente (H3), même principe.
        if (StockHorsLigne.confirmerAuRetour && _stock.queue.pendingCount > 0) await ouvrirEnvoiStock(null, stock: _stock);
      });
    }
  }

  void _onMonitor() {
    final m = _bound.monitor;
    final r = m.retourAt;
    if (widget.bandeauRetour && m.etat == EtatServeur.enLigne && r != null && r != _retourVu) {
      _retourVu = r;
      _retour = true;
      _retourTimer?.cancel();
      _retourTimer = Timer(widget.retourDuree, () {
        if (mounted) setState(() => _retour = false);
      });
    } else if (m.etat != EtatServeur.enLigne) {
      _retour = false;
    }
    _onChange();
  }

  BandeauHorsLigne? get _bandeau => switch (_bound.monitor.etat) {
        EtatServeur.injoignable => BandeauHorsLigne.injoignable,
        EtatServeur.horsLigne => BandeauHorsLigne.horsLigne,
        EtatServeur.enLigne => _bound.ventes.running
            ? BandeauHorsLigne.envoi
            : _bound.ventes.enAttente > 0
                ? BandeauHorsLigne.enAttente
                : _bound.ventes.aVerifier > 0
                    ? BandeauHorsLigne.aVerifier
                    : (_retour ? BandeauHorsLigne.retour : null),
      };

  @override
  Widget build(BuildContext context) {
    final b = _bandeau;
    // Structure fixe (le Navigator n'est jamais recréé) ; sans bandeau, l'écran est identique.
    return Column(children: [
      b == null ? const SizedBox.shrink() : HorsLigneBanner(kind: b, horsLigne: _bound),
      MediaQuery.removePadding(context: context, removeTop: b != null, child: StockBandeau(horsLigne: _bound, stock: _stock)),
      Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: b != null || StockBandeau.visible(_stock), child: widget.child)),
    ]);
  }
}

class HorsLigneBanner extends StatelessWidget {
  final BandeauHorsLigne kind;
  final HorsLigne horsLigne;
  const HorsLigneBanner({super.key, required this.kind, required this.horsLigne});

  static String heure(DateTime d) => DateFormat('HH:mm').format(d);

  @override
  Widget build(BuildContext context) {
    final m = horsLigne.monitor;
    final f = horsLigne.ventes;
    final envoi = f.running ? 'Envoi ${f.index}/${f.total}…' : null;
    final (Color bg, Color fg, IconData icon, String text) = switch (kind) {
      BandeauHorsLigne.injoignable => (
          const Color(0xFFFFF3D6),
          const Color(0xFF92400E),
          Icons.wifi_off,
          'Serveur injoignable${m.depuis == null ? '' : ' depuis ${heure(m.depuis!)}'}',
        ),
      BandeauHorsLigne.horsLigne => (
          const Color(0xFF334155),
          Colors.white,
          Icons.cloud_off,
          [
            'Hors ligne — ${horsLigne.catalogueLabel}',
            if (horsLigne.ventesEnAttente.value != null) '${horsLigne.ventesEnAttente.value} vente(s) en attente',
            if (f.aVerifier > 0) '${f.aVerifier} à vérifier',
            if (envoi != null) envoi,
            if (m.joignablePendantManuel) 'serveur joignable',
          ].join(' · '),
        ),
      BandeauHorsLigne.retour => (const Color(0xFFDCFCE7), const Color(0xFF166534), Icons.cloud_done, 'Serveur de nouveau joignable'),
      BandeauHorsLigne.envoi => (
          const Color(0xFFE3ECF7),
          const Color(0xFF1F4F8F),
          Icons.cloud_upload,
          'Ventes hors ligne : ${envoi ?? 'envoi…'}',
        ),
      BandeauHorsLigne.enAttente => (
          const Color(0xFFFFF3D6),
          const Color(0xFF92400E),
          Icons.cloud_upload_outlined,
          '${f.enAttente} vente(s) en attente${f.aVerifier > 0 ? ' · ${f.aVerifier} anomalie(s)' : ''}',
        ),
      BandeauHorsLigne.aVerifier => (
          const Color(0xFFFDECEC),
          const Color(0xFF7F1D1D),
          Icons.report_problem_outlined,
          '${f.aVerifier} vente(s) hors ligne en anomalie',
        ),
    };
    final voir = kind == BandeauHorsLigne.aVerifier || kind == BandeauHorsLigne.envoi || (kind == BandeauHorsLigne.horsLigne && f.enAttente + f.aVerifier > 0);
    return Material(
      key: Key('bandeau_${kind.name}'),
      color: bg,
      child: SafeArea(
        bottom: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              if (kind == BandeauHorsLigne.injoignable)
                TextButton(
                  key: const Key('continuer_hors_ligne'),
                  style: TextButton.styleFrom(
                    foregroundColor: fg,
                    minimumSize: const Size(44, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => m.goOffline(manuel: false),
                  child: const Text('Continuer hors ligne'),
                ),
              if (kind == BandeauHorsLigne.horsLigne && m.joignablePendantManuel)
                TextButton(
                  key: const Key('repasser_en_ligne'),
                  style: TextButton.styleFrom(
                    foregroundColor: fg,
                    minimumSize: const Size(44, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: m.goOnline,
                  child: const Text('Repasser en ligne'),
                ),
              if (kind == BandeauHorsLigne.enAttente)
                TextButton(
                  key: const Key('bandeau_envoyer'),
                  style: TextButton.styleFrom(
                    foregroundColor: fg,
                    minimumSize: const Size(44, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => confirmerEnvoiGlobal(horsLigne),
                  child: const Text('Envoyer'),
                ),
              if (voir)
                TextButton(
                  key: const Key('voir_ventes_hl'),
                  style: TextButton.styleFrom(
                    foregroundColor: fg,
                    minimumSize: const Size(44, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => ouvrirVentesHorsLigne(),
                  child: const Text('Voir'),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Mention sous les résultats d'une recherche produit faite hors ligne (rien en ligne).
class HorsLigneCatalogueNote extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const HorsLigneCatalogueNote({super.key, this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 2)});

  @override
  Widget build(BuildContext context) {
    final hl = HorsLigne.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([hl.monitor, hl.sync]),
      builder: (context, _) {
        if (!hl.offline) return const SizedBox.shrink();
        return Padding(
          padding: padding,
          child: Row(children: [
            const Icon(Icons.cloud_off, size: 14, color: Color(0xFF475569)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Hors ligne : ${hl.catalogueLabel} — stock connu à cette date',
                  key: const Key('note_catalogue_local'), style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
            ),
          ]),
        );
      },
    );
  }
}
