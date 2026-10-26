// Faux serveur Prestige : BORNES DE POINTAGE (demande 57), règles du VRAI serveur (commit 31622a33 :
// BornePointageService.authentifier, ProtectionBorne, RhPointageServiceImpl.saisirPointageBorne, BornePointageRessource,
// RhRessource.enrolerBorne), dans le MÊME ORDRE :
//   blocage de l'adresse (429) → réseau de l'officine (403 RESEAU) → borne, empreinte, date (300 s), signature
//   (401 BORNE ; 10 fausses par minute → 429) → rejeu 10 min (401 BORNE) → borne retirée (401 REVOQUEE) → débit
//   120 / min (429 + Retry-After) ; toute autre route avec X-Borne → 401 BORNE.
// La signature est recalculée ici à partir de ce que le serveur RELIT : chemin et paramètres reçus (encodés), octets
// bruts du corps, date et empreinte des en-têtes — l'application ne peut donc réussir que si elle signe exactement ce
// qu'elle envoie. (SignatureBorne est épinglée sur les vecteurs du code Java du serveur : signature_borne_test.dart.)
// Données FICTIVES seulement.
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math';

import 'package:prestige_vente_app/prestigepointage/signature_borne.dart';

import 'faux_serveur_prestige.dart';

class BorneServeur {
  final String id;
  final String nom;
  final String empreinte;
  final List<int> secret;
  String statut;
  final String creePar;
  BorneServeur(this.id, this.nom, this.empreinte, this.secret, this.creePar, {this.statut = 'ACTIVE'});
}

class FauxBornes {
  final FauxServeurPrestige s;

  /// Comptes autorisés à enrôler (P_SM_RH ou administrateur).
  final Set<String> enroleurs = {DonneesFictives.admin};
  final Map<String, BorneServeur> bornes = {};

  /// Horloge du serveur (heure locale de l'officine) ; remplaçable.
  DateTime Function() horloge = DateTime.now;

  /// KEY_BORNE_POINTAGE_RESEAU_LOCAL = 1 et adresse hors de l'officine : 403 RESEAU.
  bool horsReseau = false;
  bool empreintesPartagees = false;
  List<Map<String, dynamic>> modelesEmpreintes = [];

  /// Pointages enregistrés (id → corps reçu + borne) ; photos reçues (id → octets du JPEG).
  final Map<String, Map<String, dynamic>> pointages = {};
  final Map<String, List<int>> photos = {};

  /// Refus (diagnostic des tests).
  int refusSignature = 0, rejeux = 0;

  final Map<String, DateTime> _signaturesVues = {};
  final List<DateTime> _appels = [];
  int _echecs = 0;
  DateTime? _bloqueJusqua;
  int _attente = 0;

  /// Secret de la prochaine borne (32 octets) : aléatoire, ou fixé par un test.
  List<int> Function() nouveauSecret = () => List.generate(32, (_) => Random.secure().nextInt(256));

  FauxBornes(this.s) {
    s.filtreAvantSession = _filtre;
    s.routesParDefaut['POST /rh/bornes'] = _enroler;
    s.routesParDefaut['GET /rh/bornes'] = (r) => ReponseLocale({
          'success': true,
          'data': [for (final b in bornes.values) {'id': b.id, 'nom': b.nom, 'statut': b.statut, 'empreinte': b.empreinte.substring(0, 8)}],
        });
  }

  void retirer(String id) => bornes[id]?.statut = 'RETIREE';

  ReponseLocale _enroler(RequeteRecue r) {
    final compte = r.jsessionid == null ? null : s.compteSession[r.jsessionid];
    if (compte == null || !enroleurs.contains(compte)) {
      return const ReponseLocale({'success': false, 'interdit': true, 'msg': 'Droit manquant : Ressources humaines (bornes de pointage)'}, statut: 403);
    }
    final j = r.json;
    final emp = '${j['empreinte'] ?? ''}'.trim();
    final nom = '${j['nom'] ?? ''}'.trim();
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(emp)) {
      return const ReponseLocale({'success': false, 'code': 'INVALIDE', 'msg': 'Empreinte invalide : 64 caractères hexadécimaux attendus.'}, statut: 400);
    }
    if (nom.isEmpty) return const ReponseLocale({'success': false, 'code': 'INVALIDE', 'msg': 'Nom de la borne obligatoire.'}, statut: 400);
    for (final b in bornes.values) {
      if (b.empreinte == emp.toLowerCase() && b.statut == 'ACTIVE') b.statut = 'RETIREE';
    }
    final secret = nouveauSecret();
    final id = 'BORNE-${bornes.length + 1}-${DateTime.now().microsecondsSinceEpoch}';
    bornes[id] = BorneServeur(id, nom, emp.toLowerCase(), secret, compte);
    return ReponseLocale({'success': true, 'borneId': id, 'secret': base64Url.encode(secret).replaceAll('=', ''), 'creeLe': horloge().toIso8601String()},
        entetes: {'cache-control': 'no-store'});
  }

  ReponseLocale _refus(int statut, String code, String message, {int attente = 0}) => ReponseLocale(
        {'success': false, 'code': code, 'message': message},
        statut: statut,
        entetes: {'date': HttpDate.format(horloge().toUtc()), if (attente > 0) 'retry-after': '$attente'},
      );

  ReponseLocale _ok(Map<String, dynamic> corps) => ReponseLocale(corps, entetes: {'date': HttpDate.format(horloge().toUtc())});

  Future<ReponseLocale?> _filtre(RequeteRecue r) async {
    final borne = r.chemin.contains('/borne-pointage/');
    if (!borne) {
      return r.entete('x-borne') != null ? _refus(401, 'BORNE', 'Route non accessible à une borne de pointage.') : null;
    }
    final maintenant = horloge();
    final bloque = _bloqueJusqua;
    if (bloque != null && maintenant.isBefore(bloque)) {
      final a = bloque.difference(maintenant).inSeconds + 1;
      return _refus(429, 'TROP_DE_DEMANDES', 'Trop de demandes : réessayez dans $a s.', attente: a);
    }
    if (horsReseau) return _refus(403, 'RESEAU', 'Borne de pointage acceptée seulement sur le réseau de l\'officine.');
    final id = r.entete('x-borne'), date = r.entete('x-borne-date'), emp = r.entete('x-borne-empreinte'), sig = r.entete('x-borne-signature');
    final b = [id, date, emp, sig].any((x) => x == null || x.trim().isEmpty) ? null : bornes[id!.trim()];
    DateTime? d;
    try {
      d = DateTime.parse(date!.trim());
      if (!date.trim().endsWith('Z')) d = null; // Instant.parse : UTC « Z » exigé
    } catch (_) {
      d = null;
    }
    var juste = false;
    if (b != null && b.empreinte == emp!.trim().toLowerCase() && d != null && maintenant.toUtc().difference(d.toUtc()).inMilliseconds.abs() <= 300000) {
      final attendue = SignatureBorne.signer(b.secret, SignatureBorne.chaine(r.methode, r.cible, date!.trim(), emp.trim(), r.octets));
      juste = attendue == sig!.trim().replaceAll('=', '');
    }
    if (!juste) {
      refusSignature++;
      _echecs++;
      if (_echecs >= 10) {
        _attente = _attente == 0 ? 60 : min(900, _attente * 2);
        _bloqueJusqua = maintenant.add(Duration(seconds: _attente));
        _echecs = 0;
        return _refus(429, 'TROP_DE_DEMANDES', 'Trop de demandes.', attente: _attente);
      }
      return _refus(401, 'BORNE', 'Borne non reconnue : enrôlez-la à nouveau.');
    }
    _signaturesVues.removeWhere((_, t) => t.isBefore(maintenant));
    if (_signaturesVues.containsKey(sig!.trim())) {
      rejeux++;
      return _refus(401, 'BORNE', 'Borne non reconnue : enrôlez-la à nouveau.');
    }
    _signaturesVues[sig.trim()] = maintenant.add(const Duration(minutes: 10));
    if (b!.statut != 'ACTIVE') return _refus(401, 'REVOQUEE', 'Borne retirée : elle doit être enrôlée à nouveau.');
    _appels.removeWhere((t) => maintenant.difference(t) >= const Duration(minutes: 1));
    _appels.add(maintenant);
    if (_appels.length > 120) return _refus(429, 'TROP_DE_DEMANDES', 'Trop de demandes pour cette borne : réessayez dans une minute.', attente: 60);
    return _route(r, b);
  }

  ReponseLocale _route(RequeteRecue r, BorneServeur b) {
    final c = r.chemin;
    if (r.methode == 'GET' && c.endsWith('/borne-pointage/moi')) {
      return _ok({'success': true, 'borneId': b.id, 'nom': b.nom, 'statut': b.statut, 'empreintesPartagees': empreintesPartagees});
    }
    if (r.methode == 'GET' && c.endsWith('/borne-pointage/employes')) {
      const reduits = ['id', 'matricule', 'nom', 'prenoms', 'badge', 'statut'];
      return _ok({
        'success': true,
        'data': [
          for (final e in s.employesRh)
            if (e['statut'] == 'ACTIF') {for (final k in reduits) k: e[k]}
        ],
      });
    }
    if (r.methode == 'GET' && c.endsWith('/borne-pointage/empreintes')) {
      if (!empreintesPartagees) return _ok({'success': false, 'code': 'DESACTIVE', 'msg': 'Empreintes partagées désactivées (paramètre KEY_EMPREINTES_PARTAGEES).'});
      return _ok({'success': true, 'horodatage': '2026-10-26T08:00:00', 'modeles': modelesEmpreintes, 'suppressions': []});
    }
    if (r.methode == 'POST' && c.endsWith('/borne-pointage/pointages')) return _pointage(r.json, b);
    final photo = RegExp(r'/borne-pointage/pointages/([^/]+)/photo$').firstMatch(c);
    if (r.methode == 'POST' && photo != null) {
      final id = Uri.decodeComponent(photo.group(1)!);
      final p = pointages[id];
      if (p == null || p['borne'] != b.id) return _ok({'success': false, 'msg': 'Pointage introuvable pour cette borne.'});
      photos[id] = r.octets;
      return _ok({'success': true, 'message': 'Photo enregistrée.'});
    }
    return FauxServeurPrestige.payara404;
  }

  ReponseLocale _pointage(Map<String, dynamic> j, BorneServeur b) {
    final emp = '${j['employeId'] ?? ''}';
    if (!s.employesRh.any((e) => e['id'] == emp)) return _ok({'success': false, 'msg': 'Employé introuvable.'});
    final id = '${j['id'] ?? ''}'.trim();
    if (!RegExp(r'^[A-Za-z0-9-]{8,40}$').hasMatch(id)) {
      return _ok({'success': false, 'msg': 'Identifiant de pointage obligatoire (8 à 40 caractères : lettres, chiffres, tiret).'});
    }
    if (pointages.containsKey(id)) return _ok({'success': true, 'id': id, 'deja': true, 'message': 'Pointage déjà existant.'});
    final maintenant = horloge();
    var t = maintenant;
    if (j['jour'] != null || j['heure'] != null) {
      try {
        final h = '${j['heure']}'.split(':');
        final jr = DateTime.parse('${j['jour']}'.substring(0, 10));
        t = DateTime(jr.year, jr.month, jr.day, int.parse(h[0]), int.parse(h[1]));
      } catch (_) {
        return _ok({'success': false, 'msg': 'Date et heure invalides.'});
      }
    }
    if (t.isAfter(maintenant.add(const Duration(minutes: 2)))) return _ok({'success': false, 'msg': 'Un pointage ne peut pas être dans le futur (2 minutes au plus).'});
    if (t.isBefore(maintenant.subtract(const Duration(hours: 72)))) return _ok({'success': false, 'msg': 'Pointage trop ancien : 72 heures au plus (file hors ligne).'});
    if (pointages.values.any((p) => p['employeId'] == emp && p['horodatage'] == t.toIso8601String())) {
      return _ok({'success': false, 'msg': 'Un pointage existe déjà à cette heure pour cet employé.'});
    }
    pointages[id] = {...j, 'borne': b.id, 'horodatage': t.toIso8601String(), 'source': 'BORNE'};
    return _ok({'success': true, 'id': id, 'message': 'Pointage enregistré.'});
  }
}
