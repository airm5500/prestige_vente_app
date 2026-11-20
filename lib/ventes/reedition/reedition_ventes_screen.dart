// lib/ventes/reedition/reedition_ventes_screen.dart
// 5.4.0 — Écran « Réédition des ventes » (accueil, famille Ventes ; bouton de la Caisse) : ventes terminées du jour
// (ou d'un autre jour), celles de CE terminal par défaut, filtre par type (comptant, assurance, carnet) et recherche
// par n° de ticket ; « Réimprimer » avec le nombre d'exemplaires (même rendu que le ticket d'origine). Règles et
// routes : lib/ventes/reedition/reedition_ventes.dart.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/api/models/sale.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/providers/settings_provider.dart';
import 'package:prestige_vente_app/serveur/nom_appareil.dart';
import 'package:prestige_vente_app/services/impression_ticket.dart';
import 'package:prestige_vente_app/services/largeur_ticket.dart';
import 'package:prestige_vente_app/services/receipt_service.dart';
import 'package:prestige_vente_app/services/ticket_serveur.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/assurance/assurance_print.dart' show showPrintCopiesDialog;
import 'package:prestige_vente_app/ventes/carnet/carnet_history.dart' show buildCarnetReprint;
import 'package:prestige_vente_app/ventes/common/copies_ticket.dart';
import 'package:prestige_vente_app/ventes/common/vente_messages.dart';
import 'package:prestige_vente_app/ventes/core/vente_gateway.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/ventes/reedition/reedition_ventes.dart';
import 'package:prestige_vente_app/ventes/reedition/ventes_du_terminal.dart';
import 'package:provider/provider.dart';

/// Portée de la liste.
enum PorteeReedition { terminal, tous }

class ReeditionVentesScreen extends StatefulWidget {
  /// Client HTTP (tests) ; par défaut celui de la session (ApiService).
  final Dio? dio;

  /// Jour affiché à l'ouverture (tests) ; par défaut aujourd'hui.
  final DateTime? jour;
  const ReeditionVentesScreen({super.key, this.dio, this.jour});

  @override
  State<ReeditionVentesScreen> createState() => _ReeditionVentesScreenState();
}

class _ReeditionVentesScreenState extends State<ReeditionVentesScreen> {
  final _recherche = TextEditingController();
  Timer? _attente;
  late DateTime _jour;
  PorteeReedition _portee = PorteeReedition.terminal;
  TypeReedition _type = TypeReedition.tous;
  List<VenteTerminee>? _ventes;
  bool _tronquee = false;
  String? _erreur;
  bool _charge = false;
  int _demande = 0;
  String? _impression;

  @override
  void initState() {
    super.initState();
    final j = widget.jour ?? DateTime.now();
    _jour = DateTime(j.year, j.month, j.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  @override
  void dispose() {
    _attente?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  Dio? get _dio {
    if (widget.dio != null) return widget.dio;
    try {
      return Provider.of<ApiService>(context, listen: false).dio;
    } catch (_) {
      return null;
    }
  }

  Future<void> _charger() async {
    final dio = _dio;
    if (dio == null) {
      setState(() => _erreur = 'Serveur non configuré : liste des ventes indisponible.');
      return;
    }
    final n = ++_demande;
    setState(() {
      _charge = true;
      _erreur = null;
    });
    if (!VentesDuTerminal.instance.charge) await VentesDuTerminal.instance.charger();
    final r = await ReeditionVentesService(dio).lister(jour: _jour, type: _type, recherche: _recherche.text);
    if (!mounted || n != _demande) return;
    setState(() {
      _charge = false;
      switch (r) {
        case ListeVentes(:final ventes, :final tronquee):
          _ventes = ventes;
          _tronquee = tronquee;
        case EchecListeVentes(:final message):
          _erreur = message;
      }
    });
  }

  void _rechercheModifiee(String _) {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 500), _charger);
    setState(() {});
  }

  List<VenteTerminee> get _affichees {
    final l = _ventes ?? const <VenteTerminee>[];
    final nom = NomAppareil.instance.effectif;
    return [
      for (final v in l)
        if ((_portee == PorteeReedition.tous || v.deCeTerminal(notee: VentesDuTerminal.instance.contient, nomPoste: nom)) &&
            (_type == TypeReedition.tous || v.categorie == _type) &&
            v.correspond(_recherche.text))
          v,
    ];
  }

  Future<void> _choisirJour() async {
    final now = DateTime.now();
    final j = await showDatePicker(
      context: context,
      initialDate: _jour,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      helpText: 'Jour des ventes',
    );
    if (j == null || !mounted) return;
    setState(() => _jour = DateTime(j.year, j.month, j.day));
    await _charger();
  }

  void _jourRelatif(int decalage) {
    final n = DateTime.now();
    setState(() => _jour = DateTime(n.year, n.month, n.day).subtract(Duration(days: decalage)));
    _charger();
  }

  // ---------------------------------------------------------------------------
  // Réimpression
  // ---------------------------------------------------------------------------

  Future<void> _reimprimer(VenteTerminee v) async {
    if (_impression != null) return;
    final copies = await showPrintCopiesDialog(context,
        title: 'Réimprimer le ticket N° ${v.numero}', message: '${v.categorie.libelle} · ${_heure(v)}', initialCopies: 1);
    if (copies < 1 || !mounted) return;
    setState(() => _impression = v.id);
    try {
      await imprimerCopiesAvecPause(context, copies, () => reimprimerVente(context, v));
    } finally {
      if (mounted) setState(() => _impression = null);
    }
  }

  // ---------------------------------------------------------------------------
  // Affichage
  // ---------------------------------------------------------------------------

  String _heure(VenteTerminee v) => v.date == null ? '' : DateFormat('HH:mm').format(v.date!);

  String get _libelleJour {
    final n = DateTime.now();
    final aujourdhui = DateTime(n.year, n.month, n.day);
    if (_jour == aujourdhui) return 'Aujourd\'hui';
    if (_jour == aujourdhui.subtract(const Duration(days: 1))) return 'Hier';
    return DateFormat('dd/MM/yyyy').format(_jour);
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final aujourdhui = DateTime(n.year, n.month, n.day);
    final hier = aujourdhui.subtract(const Duration(days: 1));
    final affichees = _affichees;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Réédition des ventes'),
        actions: [
          IconButton(key: const ValueKey('reedition-actualiser'), tooltip: 'Actualiser', onPressed: _charge ? null : _charger, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: SegmentedButton<PorteeReedition>(
            key: const ValueKey('reedition-portee'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: PorteeReedition.terminal, label: Text('Ce terminal'), icon: Icon(Icons.phone_android)),
              ButtonSegment(value: PorteeReedition.tous, label: Text('Tous les postes'), icon: Icon(Icons.devices)),
            ],
            selected: {_portee},
            onSelectionChanged: (s) => setState(() => _portee = s.first),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            ChoiceChip(key: const ValueKey('reedition-jour-aujourdhui'), label: const Text('Aujourd\'hui'), selected: _jour == aujourdhui, onSelected: (_) => _jourRelatif(0)),
            const SizedBox(width: 6),
            ChoiceChip(key: const ValueKey('reedition-jour-hier'), label: const Text('Hier'), selected: _jour == hier, onSelected: (_) => _jourRelatif(1)),
            const SizedBox(width: 6),
            ActionChip(
              key: const ValueKey('reedition-jour-autre'),
              avatar: const Icon(Icons.calendar_month, size: 18),
              label: Text(_jour != aujourdhui && _jour != hier ? _libelleJour : 'Autre jour'),
              onPressed: _choisirJour,
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final t in TypeReedition.values)
              ChoiceChip(
                key: ValueKey('reedition-type-${t.name}'),
                label: Text(t.libelle),
                selected: _type == t,
                onSelected: (_) {
                  setState(() => _type = t);
                  _charger();
                },
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: TextField(
            key: const ValueKey('reedition-recherche'),
            controller: _recherche,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.search,
            onChanged: _rechercheModifiee,
            onSubmitted: (_) => _charger(),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'N° de ticket',
              border: const OutlineInputBorder(),
              suffixIcon: _recherche.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _recherche.clear();
                        _rechercheModifiee('');
                      },
                    ),
            ),
          ),
        ),
        if (_charge) const LinearProgressIndicator(minHeight: 3),
        Expanded(child: _liste(affichees)),
      ]),
    );
  }

  Widget _liste(List<VenteTerminee> affichees) {
    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40, color: Color(0xFF7F1D1D)),
            const SizedBox(height: 8),
            Text(_erreur!, key: const ValueKey('reedition-erreur'), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF7F1D1D))),
            const SizedBox(height: 8),
            TextButton.icon(onPressed: _charger, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ]),
        ),
      );
    }
    if (_ventes == null) return const SizedBox.shrink();
    if (affichees.isEmpty) {
      final ailleurs = _portee == PorteeReedition.terminal && (_ventes ?? const []).isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            ailleurs
                ? 'Aucune vente de ce terminal ($_libelleJour). D\'autres postes en ont : choisissez « Tous les postes ».'
                : 'Aucune vente terminée ($_libelleJour).',
            key: const ValueKey('reedition-vide'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      key: const ValueKey('reedition-liste'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: affichees.length + (_tronquee ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == affichees.length) {
          return const Text('Journée très chargée : les 1 000 ventes les plus récentes sont listées. Cherchez par n° de ticket.',
              style: TextStyle(fontSize: 13, color: Color(0xFF475569)));
        }
        return _carte(affichees[i]);
      },
    );
  }

  Widget _carte(VenteTerminee v) {
    final couleur = switch (v.categorie) {
      TypeReedition.comptant => Colors.blue.shade700,
      TypeReedition.carnet => Colors.green.shade800,
      _ => Colors.red.shade700,
    };
    final enCours = _impression == v.id;
    return Card(
      key: ValueKey('reedition-vente-${v.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('N° ${v.numero}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(v.categorie.libelle, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: couleur)),
                ),
                if (v.annulee)
                  const Text('Annulée', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7F1D1D))),
              ]),
              const SizedBox(height: 2),
              Text(
                [_heure(v), '${Constants.formatNumber(v.montant)} F', if (v.client.isNotEmpty) v.client].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: FilledButton.tonalIcon(
              key: ValueKey('reedition-reimprimer-${v.id}'),
              onPressed: _impression != null ? null : () => _reimprimer(v),
              // Pendant l'impression : boutons désactivés ; « Préparation du ticket… » montre l'attente du serveur.
              icon: Icon(enCours ? Icons.hourglass_top : Icons.print),
              label: const Text('Réimprimer'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Réimprime UN exemplaire du ticket de [v] : ticket du serveur (route image, comme à l'impression d'origine), sinon
/// gabarit local reconstruit avec la vente relue (serveur sans la route image).
Future<void> reimprimerVente(BuildContext context, VenteTerminee v) async {
  final settings = Provider.of<SettingsProvider>(context, listen: false);
  final papier = await LargeurTicket.pourImpression(settings.paperWidth);
  if (!context.mounted) return;
  final type = v.comptant ? TypeTicketServeur.vno : TypeTicketServeur.vo;
  if (await ImpressionTicket.parServeur(context, type: type, venteId: v.id, largeur: papier, apercu: settings.isTestPrintMode)) return;
  if (!context.mounted) return;
  await _gabaritLocal(context, v, settings);
}

Future<void> _gabaritLocal(BuildContext context, VenteTerminee v, SettingsProvider settings) async {
  final auth = Provider.of<AuthProvider>(context, listen: false);
  final officine = auth.officine, user = auth.user;
  ApiService? api;
  try {
    api = Provider.of<ApiService>(context, listen: false);
  } catch (_) {}
  if (officine == null || user == null || api == null) {
    showVenteSnack(context, 'Données officine ou utilisateur manquantes : ticket non imprimé.', error: true);
    return;
  }
  final gw = DioVenteGateway(api);
  final vente = await gw.fullSale(v.id);
  final lignes = await gw.saleDetails(v.id);
  if (!context.mounted) return;
  if (vente is! VenteOk<Map<String, dynamic>> || lignes is! VenteOk<List<SaleItemDetail>>) {
    showVenteSnack(context, 'Vente non relue sur le serveur : ticket non imprimé. Réessayez.', error: true);
    return;
  }
  final data = vente.value;
  final items = lignes.value;
  if (v.comptant) {
    int n(Object? x) => x is num ? x.toInt() : int.tryParse('${x ?? ''}') ?? 0;
    final net = data['intCUSTPART'] != null ? n(data['intCUSTPART']) : v.montant;
    await ReceiptService().printSaleTicket(
      context: context,
      officine: officine,
      saleSummary: SaleSummary(montant: v.montant, montantNet: net > 0 ? net : v.montant, reference: v.reference, venteId: v.id),
      items: items,
      paymentMethod: PaymentMethod(id: '1', name: '${data['modeReglement'] ?? data['strTYPEREGLEMENT'] ?? 'COMPTANT'}'),
      currentUser: user,
      isTestMode: settings.isTestPrintMode,
      paperWidth: settings.paperWidth,
      showQrCode: settings.showQrCodeOnSaleTicket,
      ticketCodeType: settings.ticketCodeType,
    );
    return;
  }
  final t = buildCarnetReprint(
    PreventeListItem(lgPREENREGISTREMENTID: v.id, heure: '', dtUPDATED: '', intPRICE: v.montant, strREF: v.reference, userFullName: '', lgTYPEVENTEID: v.lgTypeVenteId),
    data,
  );
  if (t == null) {
    showVenteSnack(context, 'Référence de la vente introuvable : ticket non imprimé.', error: true);
    return;
  }
  await ReceiptService().printAssuranceSaleTicket(
    context: context,
    officine: officine,
    saleSummary: t.summary,
    items: items.isEmpty ? t.items : items,
    client: t.client,
    ayantDroit: t.ayantDroit,
    paymentMethod: PaymentMethod(id: '1', name: v.categorie == TypeReedition.carnet ? 'CARNET' : 'COMPTANT'),
    currentUser: user,
    isTestMode: settings.isTestPrintMode,
    paperWidth: settings.paperWidth,
    ticketCodeType: settings.ticketCodeType,
    showQrCode: settings.showQrCodeOnSaleTicket,
    numberOfCopies: 1,
    reference: v.reference,
    carnet: v.categorie == TypeReedition.carnet,
    confirmEachCopy: false,
  );
}
