// lib/paiements/paiements_mobile.dart
// B3 — Paiement mobile money par agrégateur (module serveur v1/paiements-mobile, patch
// docs/serveur/B3_paiements_mobile.patch). DÉSACTIVÉ PAR DÉFAUT (réglage de l'appareil) et sans effet
// tant que le serveur n'annonce pas d'opérateur (GET /paiements-mobile/capacites).
// - montant toujours FIXÉ PAR LE SERVEUR (net de la vente, ou part contrôlée d'un paiement en deux modes) ;
// - le téléphone affiche le QR / lien et interroge le statut toutes les 3 s jusqu'au paiement, à l'échec
//   ou à l'expiration ; annulation possible tant que rien n'est payé ;
// - un paiement arrivé après une annulation est signalé « à régulariser » (jamais d'encaissement double) ;
// - hors ligne : indisponible (espèces seulement).
import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/ventes/core/vente_result.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StatutPM { enAttente, paye, echoue, expire, annule, payeApresAnnulation }

extension StatutPMInfo on StatutPM {
  static StatutPM de(String? c) => switch (c) {
        'paye' => StatutPM.paye,
        'echoue' => StatutPM.echoue,
        'expire' => StatutPM.expire,
        'annule' => StatutPM.annule,
        'paye_apres_annulation' => StatutPM.payeApresAnnulation,
        _ => StatutPM.enAttente,
      };

  String get label => switch (this) {
        StatutPM.enAttente => 'En attente',
        StatutPM.paye => 'Payé',
        StatutPM.echoue => 'Échoué',
        StatutPM.expire => 'Expiré',
        StatutPM.annule => 'Annulé',
        StatutPM.payeApresAnnulation => 'À régulariser',
      };

  bool get termine => this != StatutPM.enAttente;
  bool get argentRecu => this == StatutPM.paye || this == StatutPM.payeApresAnnulation;
}

/// Opérateurs (code du serveur) et mode de règlement Prestige.
const Map<String, String> typeReglementOperateur = {'orange': '7', 'moov': '8', 'mtn': '9', 'wave': '10'};
const Map<String, String> nomOperateur = {'orange': 'Orange Money', 'moov': 'Moov Money', 'mtn': 'MTN MoMo', 'wave': 'Wave'};

/// Opérateur d'un mode de règlement Prestige (7, 8, 9, 10), sinon null.
String? operateurDuMode(String typeReglementId) {
  for (final e in typeReglementOperateur.entries) {
    if (e.value == typeReglementId) return e.key;
  }
  return null;
}

class PaiementMobile {
  final String id;
  final String venteId;
  final String reference;
  final int montant;
  final String operateur;
  final StatutPM statut;
  final String lien;
  final bool clotureAuto;
  final bool cloture;
  final String message;
  final String creeLe;
  const PaiementMobile({
    required this.id,
    required this.venteId,
    this.reference = '',
    required this.montant,
    required this.operateur,
    required this.statut,
    this.lien = '',
    this.clotureAuto = false,
    this.cloture = false,
    this.message = '',
    this.creeLe = '',
  });

  bool get aRegulariser => statut == StatutPM.payeApresAnnulation;

  static PaiementMobile fromJson(Map<String, dynamic> j) => PaiementMobile(
        id: '${j['id'] ?? ''}',
        venteId: '${j['venteId'] ?? ''}',
        reference: '${j['reference'] ?? ''}',
        montant: (j['montant'] as num?)?.toInt() ?? 0,
        operateur: '${j['operateur'] ?? ''}',
        statut: StatutPMInfo.de('${j['statut']}'),
        lien: '${j['lien'] ?? ''}',
        clotureAuto: j['clotureAuto'] == true,
        cloture: j['cloture'] == true,
        message: '${j['message'] ?? ''}',
        creeLe: '${j['creeLe'] ?? ''}',
      );
}

class CapacitesPM {
  final List<String> operateurs;
  final String? fournisseur;
  final int expirationMin;
  const CapacitesPM({this.operateurs = const [], this.fournisseur, this.expirationMin = 10});
  bool get actif => operateurs.isNotEmpty;
}

/// Accès serveur (remplaçable dans les tests).
abstract class PaiementsMobileApi {
  Future<VenteResult<CapacitesPM>> capacites();
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle});
  Future<VenteResult<PaiementMobile>> statut(String id);
  Future<VenteResult<PaiementMobile>> annuler(String id);
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour);
}

VenteResult<PaiementMobile> _unPaiement(Object? body) {
  if (body is! Map) return const VenteFailed('Paiement : réponse illisible.');
  if (body['success'] != true) return VenteRefused('${body['message'] ?? body['msg'] ?? 'Paiement refusé par le serveur.'}');
  final d = body['data'];
  if (d is! Map) return const VenteFailed('Paiement : réponse illisible.');
  return VenteOk(PaiementMobile.fromJson(Map<String, dynamic>.from(d)));
}

class DioPaiementsMobileApi implements PaiementsMobileApi {
  final Dio Function() dio;
  DioPaiementsMobileApi(this.dio);

  Future<VenteResult<Object?>> _call(Future<Response<dynamic>> Function(Dio d) f) async {
    try {
      final r = await f(dio());
      final code = r.statusCode ?? 0;
      if (code == 404) return const VenteRefused('Paiement mobile money non disponible sur ce serveur.', code: '404');
      if (code == 401 || code == 403) return const VenteFailed('Session expirée : reconnectez-vous.');
      if (code != 200) return VenteFailed('Paiement : erreur du serveur (code $code).');
      return VenteOk(r.data);
    } on DioException catch (e) {
      return VenteFailed('Paiement : serveur injoignable (${e.type.name}).', maybeApplied: e.type == DioExceptionType.receiveTimeout);
    }
  }

  Options get _o => Options(validateStatus: (_) => true);

  @override
  Future<VenteResult<CapacitesPM>> capacites() async {
    final r = await _call((d) => d.get('/paiements-mobile/capacites', options: _o));
    if (r is! VenteOk<Object?>) return r.map((_) => const CapacitesPM());
    final b = r.value;
    if (b is! Map || b['success'] != true) return const VenteOk(CapacitesPM());
    final ops = b['paiementsMobile'];
    return VenteOk(CapacitesPM(
      operateurs: ops is List ? [for (final o in ops) '$o'] : const [],
      fournisseur: b['fournisseur'] is String ? b['fournisseur'] as String : null,
      expirationMin: (b['expirationMin'] as num?)?.toInt() ?? 10,
    ));
  }

  @override
  Future<VenteResult<PaiementMobile>> creer({required String venteId, required String operateur, int? part, bool cloturer = false, required String cle}) async {
    final r = await _call((d) => d.post('/paiements-mobile',
        data: {'venteId': venteId, 'operateur': operateur, if (part != null) 'part': part, 'cloturer': cloturer},
        options: Options(validateStatus: (_) => true, headers: {'X-Client-Ref': cle})));
    return r is VenteOk<Object?> ? _unPaiement(r.value) : r.map((_) => throw StateError('inutilisé'));
  }

  @override
  Future<VenteResult<PaiementMobile>> statut(String id) async {
    final r = await _call((d) => d.get('/paiements-mobile/${Uri.encodeComponent(id)}', options: _o));
    return r is VenteOk<Object?> ? _unPaiement(r.value) : r.map((_) => throw StateError('inutilisé'));
  }

  @override
  Future<VenteResult<PaiementMobile>> annuler(String id) async {
    final r = await _call((d) => d.post('/paiements-mobile/${Uri.encodeComponent(id)}/annuler', options: _o));
    return r is VenteOk<Object?> ? _unPaiement(r.value) : r.map((_) => throw StateError('inutilisé'));
  }

  @override
  Future<VenteResult<List<PaiementMobile>>> historique(DateTime jour) async {
    final r = await _call((d) => d.get('/paiements-mobile', queryParameters: {'date': DateFormat('yyyy-MM-dd').format(jour)}, options: _o));
    if (r is! VenteOk<Object?>) return r.map((_) => <PaiementMobile>[]);
    final b = r.value;
    if (b is! Map || b['success'] != true) return VenteRefused('${b is Map ? b['message'] ?? '' : ''}'.isEmpty ? 'Historique refusé.' : '${(b as Map)['message']}');
    final d = b['data'];
    return VenteOk([if (d is List) for (final e in d) if (e is Map) PaiementMobile.fromJson(Map<String, dynamic>.from(e))]);
  }
}

/// Réglage de l'appareil (désactivé par défaut).
class PaiementsMobileReglages {
  PaiementsMobileReglages._();
  static const _cle = 'paiements_mobile_actif_v1';
  static final ValueNotifier<bool> actif = ValueNotifier(false);

  static Future<void> charger() async {
    try {
      actif.value = (await SharedPreferences.getInstance()).getBool(_cle) ?? false;
    } catch (_) {
      actif.value = false;
    }
  }

  static Future<void> enregistrer(bool v) async {
    actif.value = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(_cle, v);
    } catch (_) {}
  }
}

/// Point d'entrée : capacités en cache (5 min), disponibilité selon le réglage et le réseau.
class PaiementsMobile {
  PaiementsMobileApi? api;
  bool Function() horsLigne;
  DateTime Function() clock;
  PaiementsMobile({this.api, bool Function()? horsLigne, DateTime Function()? clock})
      : horsLigne = horsLigne ?? (() => false),
        clock = clock ?? DateTime.now;

  static PaiementsMobile instance = PaiementsMobile();

  CapacitesPM? _cap;
  DateTime? _capAt;

  CapacitesPM? get capacitesConnues => _cap;

  /// Opérateurs proposables maintenant (vide : désactivé, hors ligne ou serveur sans module).
  Future<List<String>> operateurs({bool rafraichir = false}) async {
    if (!PaiementsMobileReglages.actif.value || horsLigne() || api == null) return const [];
    final at = _capAt;
    if (rafraichir || _cap == null || at == null || clock().difference(at) > const Duration(minutes: 5)) {
      final r = await api!.capacites();
      if (r case VenteOk(:final value)) {
        _cap = value;
        _capAt = clock();
      } else if (_cap == null) {
        return const [];
      }
    }
    return _cap!.operateurs;
  }

  /// Clé client (X-Client-Ref) d'une demande : la même demande renvoyée ne crée jamais deux paiements.
  static String nouvelleCle() {
    final r = Random.secure();
    return 'PM-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }
}

/// Attente d'un paiement : création, interrogation toutes les 3 s, compte à rebours, annulation.
class AttentePaiement extends ChangeNotifier {
  final PaiementsMobileApi api;
  final Duration intervalle;
  final Duration delai;
  final DateTime Function() clock;
  AttentePaiement(this.api, {this.intervalle = const Duration(seconds: 3), this.delai = const Duration(minutes: 10), DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  PaiementMobile? paiement;
  String? erreur;
  bool creation = false;
  DateTime? _fin;
  Timer? _timer;
  bool _interrogation = false;
  bool _ferme = false;
  String? _cle;

  StatutPM? get statut => paiement?.statut;

  /// Secondes restantes avant l'expiration (0 au-delà).
  int get reste {
    final f = _fin;
    if (f == null) return 0;
    final s = f.difference(clock()).inSeconds;
    return s < 0 ? 0 : s;
  }

  bool get termine => paiement?.statut.termine ?? false;

  Future<void> demarrer({required String venteId, required String operateur, int? part, bool cloturer = false}) async {
    if (creation || paiement != null) return; // anti double appui
    creation = true;
    erreur = null;
    _cle ??= PaiementsMobile.nouvelleCle();
    _notifier();
    final r = await api.creer(venteId: venteId, operateur: operateur, part: part, cloturer: cloturer, cle: _cle!);
    creation = false;
    if (r case VenteOk(:final value)) {
      paiement = value;
      _fin = clock().add(delai);
      _journal('Paiement mobile money demandé', ResultatJournal.info);
      _planifier();
    } else {
      erreur = r.message;
    }
    _notifier();
  }

  void _planifier() {
    _timer?.cancel();
    if (_ferme || termine) return;
    _timer = Timer(intervalle, interroger);
  }

  /// Interroge le serveur (appelé toutes les 3 s ; aussi à la main dans les tests).
  Future<void> interroger() async {
    final p = paiement;
    if (p == null || _interrogation || _ferme) return;
    _interrogation = true;
    try {
      final r = await api.statut(p.id);
      if (r case VenteOk(:final value)) {
        final avant = p.statut;
        paiement = value;
        if (avant != value.statut) _journalStatut(value);
      }
      if (!termine && reste == 0) {
        // Délai local dépassé : le serveur expirera ; on arrête d'attendre.
        _arreter();
      }
    } finally {
      _interrogation = false;
    }
    _notifier();
    if (!termine) _planifier();
  }

  /// Annulation (tant que rien n'est payé). Une vérification suit : un paiement déjà parti est signalé.
  Future<void> annuler() async {
    final p = paiement;
    if (p == null || termine) {
      _arreter();
      return;
    }
    final r = await api.annuler(p.id);
    if (r case VenteOk(:final value)) {
      paiement = value;
      _journalStatut(value);
    }
    _timer?.cancel();
    _notifier();
  }

  /// Dernière vérification après une annulation (paiement tardif → « à régulariser »).
  Future<StatutPM?> verifierApresAnnulation() async {
    final p = paiement;
    if (p == null) return null;
    final r = await api.statut(p.id);
    if (r case VenteOk(:final value)) {
      if (value.statut != p.statut) _journalStatut(value);
      paiement = value;
      _notifier();
    }
    return paiement?.statut;
  }

  void _arreter() {
    _timer?.cancel();
    _timer = null;
  }

  void _journalStatut(PaiementMobile p) {
    switch (p.statut) {
      case StatutPM.paye:
        _journal('Paiement mobile money reçu', ResultatJournal.ok);
      case StatutPM.payeApresAnnulation:
        _journal('Paiement mobile money reçu après annulation : à régulariser', ResultatJournal.refus);
      case StatutPM.echoue:
        _journal('Paiement mobile money échoué', ResultatJournal.refus);
      case StatutPM.expire:
        _journal('Paiement mobile money expiré', ResultatJournal.info);
      case StatutPM.annule:
        _journal('Paiement mobile money annulé', ResultatJournal.info);
      case StatutPM.enAttente:
        break;
    }
  }

  void _journal(String action, ResultatJournal res) {
    final p = paiement;
    if (p == null) return;
    JournalTerminal.instance.noter(
      type: TypeJournal.encaissement,
      action: action,
      refLocale: p.id,
      refServeur: p.reference,
      montant: p.montant,
      // Pas de « modes » ici : l'encaissement est compté une fois, à la clôture de la vente.
      resultat: res,
      motif: p.message,
    );
  }

  void _notifier() {
    if (!_ferme) notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _arreter();
    super.dispose();
  }
}
