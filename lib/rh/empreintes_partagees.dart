// lib/rh/empreintes_partagees.dart
// 4.4.0 — Empreintes des employés PARTAGÉES entre les terminaux de pointage (demande 43, serveur du 16/10/2026).
//
// Routes du serveur (droit P_SM_RH ; paramètre KEY_EMPREINTES_PARTAGEES, désactivé par défaut) :
//   POST   v1/rh/employes/{id}/empreintes  {modeles:[base64], format, capteur, doigt, consentement:{le, par}}
//          + X-Client-Ref → {success, nombre, ids} ; {success:false, code:DESACTIVE|EMPLOYE|CONSENTEMENT|…}
//   GET    v1/rh/empreintes?depuis=<AAAA-MM-JJTHH:MM:SS>&format=SUNMI_A400_RAW
//          → {success, horodatage, modeles:[{id, employeId, format, capteur, doigt, modele, dtCreation}],
//             suppressions:[{id, employeId, dtSuppression}]}
//   DELETE v1/rh/employes/{id}/empreintes → {success, nombre}
//
// Fonctionnement sur un terminal V3H (lecteur Aratek A400 du service Sunmi) :
// - enrôlement (consentement « partage » + captures + test) → modèles gardés chiffrés sur le terminal ET envoyés
//   au serveur ; réseau coupé → envoi refait à la synchronisation suivante, même X-Client-Ref (pas de doublon) ;
// - à l'ouverture du terminal puis toutes les 15 min : synchronisation INCRÉMENTALE (depuis l'horodatage du
//   serveur de la fois précédente) : nouveaux modèles ajoutés, suppressions appliquées ; l'horodatage n'avance
//   qu'après une synchronisation complète (coupure en cours → tout est repris la fois suivante, sans doublon :
//   chaque modèle est identifié par son id) ;
// - suppression dans l'application → DELETE au serveur (refait plus tard si le réseau est coupé) ;
// - serveur sans ces routes (404), ou partage désactivé : fonctionnement d'avant (empreintes sur ce terminal
//   seulement), sans erreur affichée.
// Jamais de gabarit dans un journal, un message ou une trace ; l'état gardé dans les préférences ne contient que
// l'état du partage, l'horodatage du serveur et les identifiants d'employés à supprimer.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:prestige_vente_app/horsligne/journal/journal_terminal.dart';
import 'package:prestige_vente_app/rh/identification.dart';
import 'package:prestige_vente_app/rh/rh_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Format des gabarits du service d'empreinte Sunmi (capteur Aratek A400) : seuls ces modèles sont échangés.
const String formatEmpreinteSunmi = 'SUNMI_A400_RAW';

/// État du partage vu depuis ce terminal.
enum EtatPartageEmpreintes {
  /// Jamais vérifié (aucune synchronisation encore).
  inconnu,

  /// Partage actif : modèles conservés sur le serveur et recopiés sur les terminaux.
  actif,

  /// Paramètre KEY_EMPREINTES_PARTAGEES désactivé sur le serveur.
  desactive,

  /// Serveur sans les routes (version plus ancienne) : empreintes locales seulement.
  absent,

  /// Refus du serveur (droit RH manquant, session…) : empreintes locales seulement.
  refuse,
}

class StatutPartageEmpreintes {
  final EtatPartageEmpreintes etat;

  /// Dernière synchronisation complète (heure du terminal).
  final DateTime? derniere;

  /// Horodatage du serveur à repasser en « depuis ».
  final String? depuis;
  final String message;

  /// Employés dont la suppression doit encore être envoyée au serveur.
  final List<String> suppressionsEnAttente;

  const StatutPartageEmpreintes({
    this.etat = EtatPartageEmpreintes.inconnu,
    this.derniere,
    this.depuis,
    this.message = '',
    this.suppressionsEnAttente = const [],
  });

  bool get actif => etat == EtatPartageEmpreintes.actif;

  StatutPartageEmpreintes copie({EtatPartageEmpreintes? etat, DateTime? derniere, String? depuis, String? message, List<String>? suppressionsEnAttente}) =>
      StatutPartageEmpreintes(
        etat: etat ?? this.etat,
        derniere: derniere ?? this.derniere,
        depuis: depuis ?? this.depuis,
        message: message ?? this.message,
        suppressionsEnAttente: suppressionsEnAttente ?? this.suppressionsEnAttente,
      );

  Map<String, dynamic> toJson() => {
        'etat': etat.name,
        if (derniere != null) 'derniere': derniere!.toIso8601String(),
        if (depuis != null) 'depuis': depuis,
        if (message.isNotEmpty) 'message': message,
        if (suppressionsEnAttente.isNotEmpty) 'suppressions': suppressionsEnAttente,
      };

  factory StatutPartageEmpreintes.fromJson(Map<String, dynamic> j) => StatutPartageEmpreintes(
        etat: EtatPartageEmpreintes.values.asNameMap()['${j['etat']}'] ?? EtatPartageEmpreintes.inconnu,
        derniere: DateTime.tryParse('${j['derniere']}'),
        depuis: j['depuis'] == null ? null : '${j['depuis']}',
        message: '${j['message'] ?? ''}',
        suppressionsEnAttente: [for (final x in (j['suppressions'] as List? ?? const [])) '$x'],
      );
}

/// Ligne d'état pour les réglages du terminal et l'écran des empreintes.
String texteStatutEmpreintes(StatutPartageEmpreintes s, int employes) {
  final n = '$employes employé${employes > 1 ? 's' : ''}';
  return switch (s.etat) {
    EtatPartageEmpreintes.actif => 'Empreintes : $n, dernière synchronisation '
        '${s.derniere == null ? 'jamais' : 'le ${DateFormat('dd/MM/yyyy à HH:mm').format(s.derniere!)}'}',
    EtatPartageEmpreintes.desactive => 'Empreintes : $n sur ce terminal — partage désactivé sur le serveur',
    EtatPartageEmpreintes.absent => 'Empreintes : $n sur ce terminal — serveur sans partage des empreintes',
    EtatPartageEmpreintes.refuse => 'Empreintes : $n sur ce terminal — partage refusé par le serveur${s.message.isEmpty ? '' : ' (${s.message})'}',
    EtatPartageEmpreintes.inconnu => 'Empreintes : $n sur ce terminal — partage pas encore vérifié',
  };
}

/// Bilan d'une synchronisation (comptes seulement, jamais de gabarit).
class BilanSynchroEmpreintes {
  final EtatPartageEmpreintes etat;
  final int ajoutes;
  final int retires;
  final int envoyes;

  /// Serveur injoignable : rien n'a changé, à refaire.
  final bool horsLigne;
  const BilanSynchroEmpreintes(this.etat, {this.ajoutes = 0, this.retires = 0, this.envoyes = 0, this.horsLigne = false});
}

class EmpreintesPartagees {
  final RhServeur serveur;
  final CoffreEmpreintes coffre;
  final bool Function() horsLigne;
  final DateTime Function() clock;
  final JournalTerminal Function() journal;

  EmpreintesPartagees({
    required this.serveur,
    required this.coffre,
    bool Function()? horsLigne,
    DateTime Function()? clock,
    JournalTerminal Function()? journal,
    this.cle = pref,
  })  : horsLigne = horsLigne ?? (() => false),
        clock = clock ?? DateTime.now,
        journal = journal ?? (() => JournalTerminal.instance);

  static const String pref = 'rh_empreintes_partage_v1';

  /// Clé des préférences de l'état (une par terminal ; les tests simulent deux terminaux).
  final String cle;

  /// Synchronisation périodique pendant que le terminal est ouvert.
  static const Duration intervalle = Duration(minutes: 15);

  static final Expando<EmpreintesPartagees> _parCoffre = Expando('empreintesPartagees');

  /// Service du [coffre] (un seul par coffre : une synchronisation à la fois).
  static EmpreintesPartagees pour(RhServeur serveur, CoffreEmpreintes coffre, {bool Function()? horsLigne}) =>
      _parCoffre[coffre] ??= EmpreintesPartagees(serveur: serveur, coffre: coffre, horsLigne: horsLigne);

  Future<void>? _enCours;

  // ------------------------------------------------------------------------------------------------ état

  Future<StatutPartageEmpreintes> statut() => lireStatut(cle);

  /// État enregistré sur ce terminal (sans service : réglages, écrans d'information).
  static Future<StatutPartageEmpreintes> lireStatut([String cle = pref]) async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(cle);
      if (v == null || v.isEmpty) return const StatutPartageEmpreintes();
      return StatutPartageEmpreintes.fromJson(Map<String, dynamic>.from(jsonDecode(v) as Map));
    } catch (_) {
      return const StatutPartageEmpreintes();
    }
  }

  Future<void> _poser(StatutPartageEmpreintes s) async {
    try {
      await (await SharedPreferences.getInstance()).setString(cle, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  /// Employés ayant au moins un modèle sur ce terminal.
  Future<int> nombreEmployes() async => (await coffre.lire()).values.where((e) => e.modeles.isNotEmpty).length;

  void _noter(String action, {ResultatJournal r = ResultatJournal.info}) =>
      journal().noter(type: TypeJournal.pointageRh, action: action, resultat: r);

  static String _ref() {
    final h = Random.secure();
    return 'EMP-${List.generate(16, (_) => h.nextInt(16).toRadixString(16)).join()}';
  }

  EtatPartageEmpreintes _etatRefus(ReponseRh r) {
    if (r.status == 404 || r.status == 405) return EtatPartageEmpreintes.absent;
    if ('${r.body?['code'] ?? ''}' == 'DESACTIVE') return EtatPartageEmpreintes.desactive;
    return EtatPartageEmpreintes.refuse;
  }

  // ------------------------------------------------------------------------------------------------ envoi

  /// Envoie les modèles de [e] (consentement « partage » obligatoire). Réussi : identifiants du serveur gardés ;
  /// réseau coupé : envoi marqué « en attente » (refait à la synchronisation) ; route absente ou partage
  /// désactivé : modèles gardés sur ce terminal seulement. Renvoie l'état du partage.
  Future<EtatPartageEmpreintes> envoyer(EmpreintesEmploye e) async {
    final RhServeur srv = serveur;
    if (srv is! RhEmpreintes) return (await statut()).etat;
    final api = srv as RhEmpreintes;
    if (!e.consentementPartage || e.modeles.isEmpty) return (await statut()).etat;
    final ref = e.refEnvoi.isEmpty ? _ref() : e.refEnvoi;
    await _remplacer(e.employeId, (x) => x.copie(envoiEnAttente: true, refEnvoi: ref));
    if (horsLigne()) return (await statut()).etat;
    final ReponseRh r;
    try {
      r = await api.envoyerEmpreintes(e.employeId, _corps(e), ref);
    } on RhHorsLigne {
      return (await statut()).etat; // gardé « en attente », refait à la synchronisation
    }
    final s = await statut();
    if (r.status == 200 && r.body?['success'] == true) {
      final ids = [for (final x in (r.body?['ids'] as List? ?? const [])) '$x'];
      await _remplacer(e.employeId, (x) => x.copie(idsServeur: [for (var i = 0; i < x.modeles.length; i++) i < ids.length ? ids[i] : null], envoiEnAttente: false));
      await _poser(s.copie(etat: EtatPartageEmpreintes.actif, message: ''));
      _noter('Empreintes envoyées au serveur — ${e.employeNom.isEmpty ? e.employeId : e.employeNom} (${ids.length} modèle(s))', r: ResultatJournal.ok);
      return EtatPartageEmpreintes.actif;
    }
    // Refus définitif (partage désactivé, route absente, droit) : plus d'envoi en attente, modèles locaux gardés.
    final etat = _etatRefus(r);
    await _remplacer(e.employeId, (x) => x.copie(envoiEnAttente: false));
    await _poser(s.copie(etat: etat, message: etat == EtatPartageEmpreintes.refuse ? messageRh(r.body, '') : ''));
    return etat;
  }

  Map<String, dynamic> _corps(EmpreintesEmploye e) {
    final par = e.recueilliPar.trim().isEmpty ? 'Terminal de pointage' : e.recueilliPar.trim();
    return {
      'modeles': [for (final m in e.modeles) base64Encode(m)],
      'format': formatEmpreinteSunmi,
      'capteur': 'A400',
      'consentement': {'le': isoLocal(e.consentementLe), 'par': par.length > 100 ? par.substring(0, 100) : par},
    };
  }

  Future<void> _remplacer(String employeId, EmpreintesEmploye Function(EmpreintesEmploye) f) async {
    final t = await coffre.lire();
    final x = t[employeId];
    if (x == null) return;
    t[employeId] = f(x);
    await coffre.ecrire(t);
  }

  // ------------------------------------------------------------------------------------------------ suppression

  /// Supprime les modèles de l'employé sur le serveur (après la suppression locale). Réseau coupé : refait à la
  /// synchronisation suivante. Sans partage : rien.
  Future<void> supprimer(String employeId) async {
    final s = await statut();
    if (serveur is! RhEmpreintes || s.etat == EtatPartageEmpreintes.absent) return;
    if (!await _supprimerServeur(employeId)) {
      await _poser(s.copie(suppressionsEnAttente: {...s.suppressionsEnAttente, employeId}.toList()));
    }
  }

  /// true : fait (ou inutile) ; false : à refaire (réseau).
  Future<bool> _supprimerServeur(String employeId) async {
    if (horsLigne()) return false;
    try {
      final r = await (serveur as RhEmpreintes).supprimerEmpreintes(employeId);
      if (r.status == 200 && r.body?['success'] == true) {
        _noter('Empreintes supprimées du serveur — employé $employeId');
      }
      return true;
    } on RhHorsLigne {
      return false;
    }
  }

  // ------------------------------------------------------------------------------------------------ synchronisation

  /// Une synchronisation à la fois (appels simultanés : la même).
  Future<BilanSynchroEmpreintes> synchroniser() async {
    while (_enCours != null) {
      await _enCours;
    }
    final c = Completer<void>();
    _enCours = c.future;
    try {
      return await _synchroniser();
    } finally {
      _enCours = null;
      c.complete();
    }
  }

  Future<BilanSynchroEmpreintes> _synchroniser() async {
    var s = await statut();
    if (horsLigne()) return BilanSynchroEmpreintes(s.etat, horsLigne: true);

    // 1. Ce qui attend depuis une coupure : suppressions puis envois (même X-Client-Ref : pas de doublon).
    var envoyes = 0;
    if (s.suppressionsEnAttente.isNotEmpty && serveur is RhEmpreintes) {
      final reste = <String>[];
      for (final id in s.suppressionsEnAttente) {
        if (!await _supprimerServeur(id)) reste.add(id);
      }
      s = s.copie(suppressionsEnAttente: reste);
      await _poser(s);
      if (reste.isNotEmpty) return BilanSynchroEmpreintes(s.etat, horsLigne: true);
    }
    for (final e in (await coffre.lire()).values.where((e) => e.envoiEnAttente).toList()) {
      final etat = await envoyer(e);
      final apres = (await coffre.lire())[e.employeId];
      if (apres?.envoiEnAttente == true) return BilanSynchroEmpreintes(etat, horsLigne: true);
      if (etat == EtatPartageEmpreintes.actif) envoyes++;
    }
    s = await statut();

    // 2. Lecture incrémentale.
    final ReponseRh r;
    try {
      r = await serveur.get('/rh/empreintes', {'format': formatEmpreinteSunmi, if (s.depuis != null) 'depuis': s.depuis});
    } on RhHorsLigne {
      return BilanSynchroEmpreintes(s.etat, envoyes: envoyes, horsLigne: true);
    }
    final b = r.body;
    if (r.status != 200 || b == null || b['success'] != true) {
      final etat = _etatRefus(r);
      await _poser(s.copie(etat: etat, message: etat == EtatPartageEmpreintes.refuse ? messageRh(b, 'Refus du serveur (${r.status}).') : ''));
      return BilanSynchroEmpreintes(etat, envoyes: envoyes);
    }
    final t = await coffre.lire();
    var ajoutes = 0, retires = 0;
    // Suppressions d'abord (un modèle supprimé puis recréé arrive avec un nouvel id).
    for (final x in (b['suppressions'] as List? ?? const [])) {
      if (x is! Map) continue;
      final id = '${x['id'] ?? ''}', emp = '${x['employeId'] ?? ''}';
      final e = t[emp];
      if (id.isEmpty || e == null) continue;
      final garder = <int>[for (var i = 0; i < e.modeles.length; i++) if (e.idServeur(i) != id) i];
      if (garder.length == e.modeles.length) continue;
      retires += e.modeles.length - garder.length;
      if (garder.isEmpty) {
        t.remove(emp);
      } else {
        t[emp] = e.copie(modeles: [for (final i in garder) e.modeles[i]], idsServeur: [for (final i in garder) e.idServeur(i)]);
      }
    }
    for (final x in (b['modeles'] as List? ?? const [])) {
      if (x is! Map) continue;
      final id = '${x['id'] ?? ''}', emp = '${x['employeId'] ?? ''}';
      if (id.isEmpty || emp.isEmpty || '${x['format'] ?? formatEmpreinteSunmi}' != formatEmpreinteSunmi) continue;
      Uint8List m;
      try {
        m = base64Decode('${x['modele'] ?? ''}');
      } catch (_) {
        continue; // modèle illisible : écarté, jamais écrit dans un journal
      }
      if (m.isEmpty) continue;
      final e = t[emp];
      if (e != null && e.idsServeur.contains(id)) continue; // déjà là (envoyé d'ici, ou synchronisation reprise)
      final base = e ??
          EmpreintesEmploye(
            employeId: emp,
            modeles: const [],
            consentementLe: DateTime.tryParse('${x['dtCreation'] ?? ''}') ?? clock(),
            recueilliPar: 'serveur',
            consentementPartage: true,
          );
      t[emp] = base.copie(
        modeles: [...base.modeles, m],
        idsServeur: [for (var i = 0; i < base.modeles.length; i++) base.idServeur(i), id],
      );
      ajoutes++;
    }
    if (ajoutes > 0 || retires > 0) await coffre.ecrire(t);
    // L'horodatage n'avance qu'une fois tout appliqué.
    final horodatage = '${b['horodatage'] ?? ''}';
    await _poser(s.copie(etat: EtatPartageEmpreintes.actif, derniere: clock(), depuis: horodatage.isEmpty ? s.depuis : horodatage, message: ''));
    if (ajoutes > 0 || retires > 0 || envoyes > 0) {
      _noter('Empreintes synchronisées avec le serveur : $ajoutes ajoutée(s), $retires retirée(s), $envoyes envoi(s)');
    }
    return BilanSynchroEmpreintes(EtatPartageEmpreintes.actif, ajoutes: ajoutes, retires: retires, envoyes: envoyes);
  }

  /// Tests : oublie l'état (préférences).
  @visibleForTesting
  static Future<void> oublier() async {
    try {
      await (await SharedPreferences.getInstance()).remove(pref);
    } catch (_) {}
  }
}
