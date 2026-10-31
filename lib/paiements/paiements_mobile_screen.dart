// lib/paiements/paiements_mobile_screen.dart
// B3 — « Paiements mobile money » : reçus / en attente / échoués / à régulariser, filtre par jour, PDF ;
// et la rubrique Réglages › Paiements mobile money (désactivée par défaut).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:prestige_vente_app/api/api_service.dart';
import 'package:prestige_vente_app/providers/auth_provider.dart';
import 'package:prestige_vente_app/borne/borne_config.dart';
import 'package:prestige_vente_app/borne/borne_diagnostic.dart';
import 'package:prestige_vente_app/droits/droits_vente.dart';
import 'package:prestige_vente_app/paiements/etat_mobile_money.dart';
import 'package:prestige_vente_app/paiements/mode_paiement_logo.dart';
import 'package:prestige_vente_app/paiements/paiements_mobile.dart';
import 'package:prestige_vente_app/parametres/parametres_widgets.dart';
import 'package:prestige_vente_app/utils/constants.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:prestige_vente_app/widgets/presentation_style.dart';
import 'package:provider/provider.dart';

/// Groupes de l'écran.
enum GroupePM { regulariser, recus, attente, echoues }

GroupePM groupeDe(StatutPM s) => switch (s) {
      StatutPM.payeApresAnnulation => GroupePM.regulariser,
      StatutPM.paye => GroupePM.recus,
      StatutPM.enAttente => GroupePM.attente,
      _ => GroupePM.echoues,
    };

String _titreGroupe(GroupePM g) => switch (g) {
      GroupePM.regulariser => 'À régulariser',
      GroupePM.recus => 'Reçus',
      GroupePM.attente => 'En attente',
      GroupePM.echoues => 'Échoués, expirés, annulés',
    };

/// PDF du jour (liste + totaux).
Future<Uint8List> pdfPaiements(DateTime jour, List<PaiementMobile> l) async {
  final doc = pw.Document();
  final recus = l.where((p) => p.statut == StatutPM.paye).fold<int>(0, (s, p) => s + p.montant);
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    build: (_) => [
      pw.Text('Paiements mobile money du ${DateFormat('dd/MM/yyyy').format(jour)}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      pw.Text('Reçus : ${Constants.formatNumber(recus)} F · ${l.length} paiement(s)'),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: ['Heure', 'Vente', 'Opérateur', 'Montant', 'Statut', 'Clôture'],
        data: [
          for (final p in l)
            [
              p.creeLe.length >= 16 ? p.creeLe.substring(11, 16) : p.creeLe,
              p.reference,
              nomOperateur[p.operateur] ?? p.operateur,
              Constants.formatNumber(p.montant),
              p.statut.label,
              p.clotureAuto ? (p.cloture ? 'faite' : 'à faire') : 'comptoir',
            ]
        ],
      ),
    ],
  ));
  return doc.save();
}

class PaiementsMobileScreen extends StatefulWidget {
  final PaiementsMobileApi? api;
  final DateTime? jour;

  /// Partage / impression du PDF (tests) ; sinon Printing.layoutPdf.
  final Future<void> Function(Uint8List pdf)? partagerPdf;
  const PaiementsMobileScreen({super.key, this.api, this.jour, this.partagerPdf});

  @override
  State<PaiementsMobileScreen> createState() => _PaiementsMobileScreenState();
}

class _PaiementsMobileScreenState extends State<PaiementsMobileScreen> {
  late DateTime _jour = widget.jour ?? DateTime.now();
  List<PaiementMobile>? _liste;
  String? _erreur;
  bool _charge = false;

  PaiementsMobileApi? get _api => widget.api ?? PaiementsMobile.instance.api;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final a = _api;
    if (a == null) {
      setState(() => _erreur = 'Serveur non connecté.');
      return;
    }
    setState(() => _charge = true);
    final r = await a.historique(_jour);
    if (!mounted) return;
    setState(() {
      _charge = false;
      if (r case VenteOk(:final value)) {
        _liste = value;
        _erreur = null;
      } else {
        _erreur = r.message;
      }
    });
  }

  Future<void> _choisirJour() async {
    final d = await showDatePicker(context: context, initialDate: _jour, firstDate: DateTime(2024), lastDate: DateTime.now());
    if (d == null) return;
    _jour = d;
    _charger();
  }

  Future<void> _pdf() async {
    final l = _liste;
    if (l == null) return;
    final bytes = await pdfPaiements(_jour, l);
    await (widget.partagerPdf ?? (b) => Printing.layoutPdf(onLayout: (_) async => b, name: 'paiements_mobile.pdf'))(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l = _liste ?? const <PaiementMobile>[];
    final groupes = {for (final g in GroupePM.values) g: l.where((p) => groupeDe(p.statut) == g).toList()};
    final recus = groupes[GroupePM.recus]!.fold<int>(0, (s, p) => s + p.montant);
    return Scaffold(
      backgroundColor: Pal.page,
      appBar: AppBar(
        title: const Text('Paiements mobile money'),
        backgroundColor: Pal.navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(key: const ValueKey('pm-jour'), tooltip: 'Choisir le jour', icon: const Icon(Icons.calendar_today), onPressed: _choisirJour),
          IconButton(key: const ValueKey('pm-pdf'), tooltip: 'PDF', icon: const Icon(Icons.picture_as_pdf), onPressed: _liste == null ? null : _pdf),
          IconButton(tooltip: 'Actualiser', icon: const Icon(Icons.refresh), onPressed: _charger),
        ],
      ),
      body: _erreur != null && _liste == null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erreur!, textAlign: TextAlign.center)))
          : ListView(padding: const EdgeInsets.all(12), children: [
              if (_charge) const LinearProgressIndicator(minHeight: 2),
              Text('${DateFormat('dd/MM/yyyy').format(_jour)} · reçus ${Constants.formatNumber(recus)} F',
                  key: const ValueKey('pm-total'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Pal.ink)),
              if (groupes[GroupePM.regulariser]!.isNotEmpty)
                Container(
                  key: const ValueKey('pm-alerte-regulariser'),
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF5D08A))),
                  child: const Text('Des paiements sont arrivés après une annulation : remboursez le client ou encaissez la vente avec ce paiement '
                      '(jamais un second encaissement).', style: TextStyle(color: Color(0xFF7C2D12))),
                ),
              for (final g in GroupePM.values)
                if (groupes[g]!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                    child: Text('${_titreGroupe(g)} (${groupes[g]!.length})', style: const TextStyle(fontWeight: FontWeight.w800, color: Pal.muted)),
                  ),
                  for (final p in groupes[g]!)
                    Card(
                      key: ValueKey('pm-ligne-${p.id}'),
                      child: ListTile(
                        leading: ModePaiementLogo(modeId: typeReglementOperateur[p.operateur], libelle: nomOperateur[p.operateur] ?? p.operateur, size: 36),
                        title: Text('${Constants.formatNumber(p.montant)} F · ${nomOperateur[p.operateur] ?? p.operateur}'),
                        subtitle: Text([
                          if (p.reference.isNotEmpty) 'Vente ${p.reference}',
                          if (p.creeLe.length >= 16) p.creeLe.substring(11, 16),
                          if (p.clotureAuto) p.cloture ? 'vente clôturée' : 'clôture à faire au comptoir',
                          if (p.message.isNotEmpty) p.message,
                        ].join(' · ')),
                        trailing: Text(p.statut.label, style: TextStyle(fontWeight: FontWeight.w700, color: p.statut.argentRecu ? Pal.green : Pal.muted)),
                      ),
                    ),
                ],
              if (_liste != null && l.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('Aucun paiement mobile money ce jour.', textAlign: TextAlign.center)),
            ]),
    );
  }
}

String paiementsSummary() => PaiementsMobileReglages.actif.value
    ? 'Actif${(PaiementsMobile.instance.capacitesConnues?.actif ?? false) ? ' · ${PaiementsMobile.instance.capacitesConnues!.fournisseur ?? ''}' : ''}'
    : 'Désactivé · QR du montant exact, confirmation automatique';

/// Réglages › Paiements mobile money.
/// 4.10.2 : ligne d'état sous l'option (retour du pharmacien du 31/10) : ce qui empêche le paiement d'être proposé —
/// pour l'encaissement de cet appareil (compte connecté) et, si la borne est configurée, pour la borne (utilisateur
/// borne, connexion d'essai à part). Capacités relues à chaque ouverture et à chaque changement de l'option.
class PaiementsMobilePage extends StatefulWidget {
  /// Diagnostics remplaçables (tests).
  final Future<DiagnosticMobileMoney> Function()? diagnosticAppareil;
  final Future<DiagnosticMobileMoney?> Function()? diagnosticBorne;
  const PaiementsMobilePage({super.key, this.diagnosticAppareil, this.diagnosticBorne});

  @override
  State<PaiementsMobilePage> createState() => _PaiementsMobilePageState();
}

class _PaiementsMobilePageState extends State<PaiementsMobilePage> {
  DiagnosticMobileMoney? _appareil;
  DiagnosticMobileMoney? _borne;
  bool _verification = false;

  @override
  void initState() {
    super.initState();
    _verifier();
  }

  Future<DiagnosticMobileMoney> _diagAppareil() async {
    final pm = PaiementsMobile.instance;
    final api = pm.api;
    final d = DroitsVente.instance;
    final r = await diagnostiquerMobileMoney(
      actif: PaiementsMobileReglages.actif.value,
      horsLigne: pm.horsLigne(),
      capacites: () async => api == null ? const VenteRefused('Paiement mobile money non disponible.', code: '404') : await api.capacites(),
      droits: () async => d.connus ? d.droits : null,
      compte: _login(),
      borne: false,
    );
    // Cache des opérateurs de l'encaissement remis à jour (capacités relues).
    if (PaiementsMobileReglages.actif.value) await pm.operateurs(rafraichir: true);
    return r;
  }

  String _login() {
    try {
      return context.read<AuthProvider>().user?.login ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<DiagnosticMobileMoney?> _diagBorne() async {
    final c = BorneReglages.courant.value;
    if (c.login.trim().isEmpty || !PaiementsMobileReglages.actif.value) return null;
    final ApiService api;
    try {
      api = context.read<ApiService>();
    } catch (_) {
      return null;
    }
    return TesteurBorne(baseUrl: api.dio.options.baseUrl).mobileMoney(c, actif: true);
  }

  Future<void> _verifier() async {
    setState(() => _verification = true);
    final a = await (widget.diagnosticAppareil ?? _diagAppareil)();
    if (!mounted) return;
    setState(() => _appareil = a);
    final b = await (widget.diagnosticBorne ?? _diagBorne)();
    if (!mounted) return;
    setState(() {
      _borne = b;
      _verification = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final actif = PaiementsMobileReglages.actif.value;
    final a = _appareil, b = _borne;
    return RubriquePage(title: 'Paiements mobile money', subtitle: paiementsSummary(), children: [
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Le client scanne un QR du montant exact ; le paiement est confirmé automatiquement par l\'agrégateur (module du '
              'serveur Prestige). Nécessite le module serveur configuré (compte marchand, clés, adresse publique HTTPS). '
              'Hors ligne : espèces seulement.',
              style: TextStyle(color: Pal.muted, fontSize: 13.5),
            ),
          ),
          SwitchListTile(
            key: const ValueKey('pm-actif'),
            title: const Text('Proposer le paiement par QR mobile money'),
            subtitle: Text(!actif ? 'Désactivé' : (_verification ? 'Vérification du serveur…' : 'Activé')),
            value: actif,
            onChanged: (v) async {
              await PaiementsMobileReglages.enregistrer(v);
              _verifier();
              if (mounted) setState(() {});
            },
          ),
          if (actif && a != null) LigneEtatMobileMoney(cle: 'pm-etat-appareil', titre: 'Encaissement sur cet appareil', d: a),
          if (actif && b != null) LigneEtatMobileMoney(cle: 'pm-etat-borne', titre: 'Borne libre-service', d: b),
          if (actif)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: TextButton.icon(
                  key: const ValueKey('pm-verifier'),
                  onPressed: _verification ? null : _verifier,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Vérifier à nouveau'),
                ),
              ),
            ),
          ListTile(
            key: const ValueKey('pm-historique'),
            leading: const Icon(Icons.receipt_long, color: Pal.navy),
            title: const Text('Paiements mobile money du jour'),
            subtitle: const Text('Reçus, en attente, échoués, à régulariser ; PDF'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaiementsMobileScreen())),
          ),
        ]),
      ),
    ]);
  }
}
